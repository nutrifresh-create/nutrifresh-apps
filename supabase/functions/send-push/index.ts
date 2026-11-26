// Supabase Edge Function: send-push (NutriFresh v144)
// Menerima Database Webhook INSERT dari tabel public.nf_push_outbox
// Mengirim Push Notification sungguhan ke HP (walau layar mati/aplikasi ditutup)
// via Firebase FCM HTTP v1 dan/atau Bot Telegram Grup Toko!

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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
  return json.access_token;
}

Deno.serve(async (req: Request) => {
  try {
    const payload = await req.json();
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

    const results: Record<string, unknown> = { fcmSent: 0, telegramSent: false };

    // 1. JALUR CEPAT: BOT TELEGRAM GRUP TOKO (KHUSUS POS, KURIR/STAFF & OFFICE)
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

    // 2. JALUR UTAMA: FIREBASE FCM HTTP v1 (ANDROID APK PELANGGAN, POS, KURIR, OFFICE)
    if (fcmSaRaw && supabaseUrl && serviceKey) {
      const sb = createClient(supabaseUrl, serviceKey);
      let q = sb.from("nf_push_devices").select("token").eq("tenant_id", rec.tenant_id || "nutrifresh");
      if (targetRole) q = q.eq("app_role", targetRole);
      if (targetRole === "customer" && targetPhone) q = q.eq("customer_phone", targetPhone);
      if (targetEmail && targetRole !== "customer") q = q.eq("user_email", targetEmail);
      const { data: devs } = await q.limit(100);
      const tokens = Array.from(new Set((devs || []).map((d: { token: string }) => d.token).filter(Boolean)));

      if (tokens.length > 0) {
        const sa = JSON.parse(fcmSaRaw);
        const accessToken = await getGoogleAccessToken(sa);
        const fcmUrl = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
        let sentCount = 0;

        for (const token of tokens) {
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
                  notification: {
                    sound: "default",
                    default_vibrate_timings: true,
                  },
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
            if (errTxt.includes("UNREGISTERED") || errTxt.includes("INVALID_ARGUMENT")) {
              await sb.from("nf_push_devices").delete().eq("token", token);
            }
          }
        }
        results.fcmSent = sentCount;
      }
    }

    if (rec.id && supabaseUrl && serviceKey) {
      const sb = createClient(supabaseUrl, serviceKey);
      await sb.from("nf_push_outbox").update({ sent_at: new Date().toISOString() }).eq("id", rec.id);
    }

    return new Response(JSON.stringify({ ok: true, ...results }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ ok: false, error: String(err) }), { status: 500 });
  }
});
