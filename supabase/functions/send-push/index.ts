// Supabase Edge Function: send-push (NutriFresh v145 — Fast Parallel + Token Cache + Max Priority)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

let cachedAccessToken = "";
let cachedTokenExpMs = 0;

function base64UrlEncode(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let str = "";
  for (let i = 0; i < bytes.length; i++) str += String.fromCharCode(bytes[i]);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const clean = pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s+/g, "");
  const bin = atob(clean);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}

async function getGoogleAccessToken(sa: { client_email: string; private_key: string }): Promise<string> {
  if (cachedAccessToken && Date.now() < cachedTokenExpMs) {
    return cachedAccessToken;
  }
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlEncode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = base64UrlEncode(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3500,
  }));
  const signingInput = `${header}.${claim}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(signingInput));
  const jwt = `${signingInput}.${base64UrlEncode(new Uint8Array(sig))}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${encodeURIComponent(jwt)}`,
  });
  const json = await res.json();
  if (!res.ok || !json.access_token) {
    throw new Error("Google OAuth2 failed: " + JSON.stringify(json));
  }
  cachedAccessToken = json.access_token;
  cachedTokenExpMs = Date.now() + 50 * 60 * 1000;
  return cachedAccessToken;
}

Deno.serve(async (req: Request) => {
  try {
    const payload = await req.json();
    if (payload?.ping === true) {
      return new Response(JSON.stringify({ ok: true, pong: true }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    const rec = payload?.record || payload;
    if (!rec || !rec.title) {
      return new Response(JSON.stringify({ ok: false, reason: "empty payload" }), { status: 400 });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
    const tgToken = (Deno.env.get("TELEGRAM_BOT_TOKEN") || "").trim();
    const tgChatId = (Deno.env.get("TELEGRAM_CHAT_ID") || "").trim();
    const fcmSaRaw = (Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") || "").trim();

    const targetRole = String(rec.target_role || "").toLowerCase();
    const targetPhone = String(rec.target_phone || "").replace(/\D/g, "");
    const targetEmail = String(rec.target_email || "").trim().toLowerCase();
    const title = String(rec.title || "NutriFresh");
    const body = String(rec.body || "");

    const sb = (supabaseUrl && serviceKey)
      ? createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
      : null;

    const results: Record<string, unknown> = {
      recId: rec.id ?? null,
      matchedTokens: 0,
      fcmSent: 0,
      telegramSent: false,
      updateError: null,
    };

    const highChannelId =
      targetRole === "customer" ? "nutrifresh_alerts" :
      targetRole === "staff" ? "nutrifresh_staff_alerts" :
      undefined;

    const tgTask = (async () => {
      if (tgToken && tgChatId && ["pos", "staff", "office"].includes(targetRole)) {
        const roleTag = targetRole === "pos" ? "🖥️ POS KASIR" : (targetRole === "staff" ? "🛵 KURIR / STAFF" : "💼 OFFICE");
        const tgText = `<b>[${roleTag}] ${title}</b>\n${body}`;
        const tgRes = await fetch(`https://api.telegram.org/bot${tgToken}/sendMessage`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ chat_id: tgChatId, text: tgText, parse_mode: "HTML" }),
        });
        results.telegramSent = tgRes.ok;
      }
    })();

    const fcmTask = (async () => {
      if (!fcmSaRaw || !sb) return;
      let q = sb.from("nf_push_devices").select("token").eq("tenant_id", rec.tenant_id || "nutrifresh");
      if (targetRole) q = q.eq("app_role", targetRole);
      if (targetRole === "customer" && targetPhone) q = q.eq("customer_phone", targetPhone);
      if (targetEmail && targetRole !== "customer") q = q.eq("user_email", targetEmail);

      const { data: devs, error: devErr } = await q.limit(100);
      if (devErr) results.devError = devErr.message;
      const tokens = Array.from(new Set((devs || []).map((d: { token: string }) => d.token).filter(Boolean)));
      results.matchedTokens = tokens.length;
      if (tokens.length === 0) return;

      const sa = JSON.parse(fcmSaRaw);
      const accessToken = await getGoogleAccessToken(sa);
      const fcmUrl = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

      const androidNotif: Record<string, unknown> = {
        sound: "default",
        default_vibrate_timings: true,
        notification_priority: "PRIORITY_MAX",
        visibility: "PUBLIC",
      };
      if (highChannelId) androidNotif.channel_id = highChannelId;

      const deadTokens: string[] = [];
      let sentCount = 0;

      await Promise.allSettled(tokens.map(async (token) => {
        const r = await fetch(fcmUrl, {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token,
              notification: { title, body },
              android: {
                priority: "HIGH",
                ttl: "3600s",
                direct_boot_ok: true,
                notification: androidNotif,
              },
              data: {
                title,
                body,
                target_role: targetRole,
                ref_id: String(rec.ref_id || ""),
              },
            },
          }),
        });
        if (r.ok) {
          sentCount++;
        } else {
          const errTxt = await r.text();
          results.fcmLastError = errTxt.slice(0, 200);
          if (errTxt.includes("UNREGISTERED") || errTxt.includes("INVALID_ARGUMENT")) {
            deadTokens.push(token);
          }
        }
      }));

      results.fcmSent = sentCount;
      if (deadTokens.length > 0) {
        await sb.from("nf_push_devices").delete().in("token", deadTokens);
      }
    })();

    const markSentTask = (async () => {
      if (rec.id !== undefined && rec.id !== null && sb) {
        const { error: updErr } = await sb
          .from("nf_push_outbox")
          .update({ sent_at: new Date().toISOString() })
          .eq("id", rec.id);
        if (updErr) results.updateError = updErr.message;
      }
    })();

    await Promise.all([tgTask, fcmTask, markSentTask]);

    return new Response(JSON.stringify({ ok: true, ...results }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ ok: false, error: String(err) }), { status: 500 });
  }
});
