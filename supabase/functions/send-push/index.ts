// Supabase Edge Function: send-push (NutriFresh v149 — Instant Direct Push, Fixed Direct Reply + Live Order + Phone Variants!)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function jsonRes(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), { status, headers: CORS_HEADERS });
}

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

function formatRp(val: number): string {
  const n = Math.round(Number(val) || 0);
  return "Rp " + n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");
}

function formatQtyShort(qty: number, unit: string): string {
  const n = Math.round(Number(qty) || 0);
  if (unit === "Gram") {
    if (n >= 1000) {
      const kg = (n / 1000).toFixed(2).replace(/\.?0+$/, "").replace(".", ",");
      return `${kg} Kg`;
    }
    return `${n} gr`;
  }
  return `${n} ${unit || "Pcs"}`;
}

function phoneVariants(raw: string): string[] {
  const d = String(raw || "").replace(/\D/g, "");
  if (!d) return [];
  const s = new Set<string>([d]);
  if (d.startsWith("0")) {
    s.add("62" + d.slice(1));
    s.add(d.slice(1));
  } else if (d.startsWith("62")) {
    s.add("0" + d.slice(2));
    s.add(d.slice(2));
  } else if (d.startsWith("8")) {
    s.add("0" + d);
    s.add("62" + d);
  }
  return Array.from(s);
}

function extractOrderId(...sources: Array<unknown>): string {
  for (const src of sources) {
    const s = String(src || "").trim();
    if (!s) continue;
    const cleaned = s.replace(/^#/, "");
    if (/^ORD-[A-Z0-9-]+$/i.test(cleaned)) return cleaned.toUpperCase();
    const m = s.match(/ORD-[A-Z0-9-]+/i);
    if (m && m[0]) return m[0].toUpperCase();
  }
  return "";
}

function getOrderStep(st: string): number {
  if (st === "Selesai") return 5;
  if ([
    "Diantar Kurir",
    "Siap Diambil",
    "Disetujui — Siap Kirim",
    "Disetujui — Siap Diambil",
    "Siap Diambil Kurir",
    "Terkirim • Tunggu Setor COD",
    "Terkirim • Lunas",
  ].includes(st)) return 4;
  if (["Menunggu Pembayaran", "Menunggu Konfirmasi", "Menunggu Verifikasi Bayar"].includes(st)) return 3;
  if (st === "Sedang Ditimbang") return 2;
  return 1;
}

function buildItemsSummary(ordData: Record<string, unknown>): string {
  const weighed = Array.isArray(ordData?.weighedItems) && ordData.weighedItems.length > 0
    ? ordData.weighedItems
    : (Array.isArray(ordData?.items) ? ordData.items : []);
  if (!Array.isArray(weighed) || weighed.length === 0) return "Pesanan buah segar NutriFresh";
  const parts = weighed.slice(0, 4).map((it: Record<string, unknown>) => {
    const q = formatQtyShort(Number(it?.qty) || 0, String(it?.unit || "Gram"));
    const nm = String(it?.name || "Buah").replace("[OBRAL]", "").trim();
    return `${q} ${nm}`;
  });
  if (weighed.length > 4) parts.push(`+${weighed.length - 4} item lainnya`);
  return parts.join(", ").slice(0, 260);
}

// deno-lint-ignore no-explicit-any
async function fetchOrderJson(sb: any, orderId: string): Promise<{ id: string; data: Record<string, unknown> } | null> {
  if (!sb || !orderId) return null;
  const cleanId = orderId.replace(/^#/, "").trim();
  const { data: ord } = await sb
    .from("nf_online_orders")
    .select("id, data")
    .eq("id", cleanId)
    .maybeSingle();
  if (!ord) return null;
  const oData = (ord.data && typeof ord.data === "object") ? (ord.data as Record<string, unknown>) : {};
  return { id: String(ord.id || cleanId), data: oData };
}

function populateOrderEnrichment(
  fcmData: Record<string, string>,
  ordId: string,
  oData: Record<string, unknown>,
  targetRole: string,
  isChatNotif: boolean,
  fallbackBody: string,
) {
  const status = String(oData.orderStatus || oData.order_status || "Menunggu Timbang");
  const grand = (Number(oData.finalTotal) || Number(oData.estimatedTotal) || 0)
    + (Number(oData.shippingFee) || 0);
  const rTok = String(oData.receiptToken || oData.receipt_token || "");

  fcmData.order_id = ordId;
  fcmData.order_code = String(oData.orderCode || oData.order_code || ordId);
  fcmData.order_status = status;
  fcmData.step = String(getOrderStep(status));
  fcmData.items_summary = buildItemsSummary(oData);
  fcmData.total_text = formatRp(grand);
  fcmData.receipt_token = rTok;
  fcmData.customer_name = String(oData.customerName || oData.customer_name || "Pelanggan");
  fcmData.courier_name = String(oData.courierName || oData.courier_name || "");
  fcmData.delivery_mode = String(oData.deliveryMode || oData.delivery_mode || "Kirim ke Rumah");

  if (isChatNotif) {
    const chatArr = Array.isArray(oData.orderChat) ? oData.orderChat : [];
    const lastMsg = chatArr.length > 0 ? (chatArr[chatArr.length - 1] as Record<string, unknown>) : null;
    if (!fcmData.sender_name) {
      fcmData.sender_name = String(lastMsg?.name || (targetRole === "customer" ? "Toko NutriFresh" : fcmData.customer_name));
    }
    if (!fcmData.chat_text) {
      fcmData.chat_text = String(lastMsg?.text || fallbackBody);
    }
  }
}

// deno-lint-ignore no-explicit-any
async function sendToRoleTargets(opts: {
  sb: any;
  fcmSaRaw: string;
  tgToken: string;
  tgChatId: string;
  tenantId: string;
  targetRole: string;
  targetPhone: string;
  targetEmail: string;
  title: string;
  body: string;
  fcmData: Record<string, string>;
}): Promise<{ matchedTokens: number; fcmSent: number; telegramSent: boolean; fcmLastError?: string }> {
  const out: { matchedTokens: number; fcmSent: number; telegramSent: boolean; fcmLastError?: string } = {
    matchedTokens: 0,
    fcmSent: 0,
    telegramSent: false,
  };
  const { sb, fcmSaRaw, tgToken, tgChatId, tenantId, targetRole, targetPhone, targetEmail, title, body, fcmData } = opts;

  const tgTask = (async () => {
    if (tgToken && tgChatId && ["pos", "staff", "office"].includes(targetRole) && fcmData.silent_live_only !== "1") {
      const roleTag = targetRole === "pos" ? "🖥️ POS KASIR" : (targetRole === "staff" ? "🛵 KURIR / STAFF" : "💼 OFFICE");
      const tgText = `<b>[${roleTag}] ${title}</b>\n${body}`;
      const tgRes = await fetch(`https://api.telegram.org/bot${tgToken}/sendMessage`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ chat_id: tgChatId, text: tgText, parse_mode: "HTML" }),
      });
      out.telegramSent = tgRes.ok;
    }
  })();

  const fcmTask = (async () => {
    if (!fcmSaRaw || !sb) return;
    let q = sb.from("nf_push_devices").select("token").eq("tenant_id", tenantId || "nutrifresh");
    if (targetRole) q = q.eq("app_role", targetRole);
    if (targetRole === "customer") {
      const variants = phoneVariants(targetPhone);
      if (variants.length === 0) return;
      q = q.in("customer_phone", variants);
    } else if (targetEmail) {
      q = q.eq("user_email", targetEmail);
    }

    const { data: devs } = await q.limit(100);
    const tokens = Array.from(new Set((devs || []).map((d: { token: string }) => d.token).filter(Boolean)));
    out.matchedTokens = tokens.length;
    if (tokens.length === 0) return;

    const sa = JSON.parse(fcmSaRaw);
    const accessToken = await getGoogleAccessToken(sa);
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

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
            android: {
              priority: "HIGH",
              ttl: "3600s",
              direct_boot_ok: true,
            },
            data: fcmData,
          },
        }),
      });
      if (r.ok) {
        sentCount++;
      } else {
        const errTxt = await r.text();
        out.fcmLastError = errTxt.slice(0, 200);
        if (errTxt.includes("UNREGISTERED") || errTxt.includes("INVALID_ARGUMENT")) {
          deadTokens.push(token);
        }
      }
    }));

    out.fcmSent = sentCount;
    if (deadTokens.length > 0) {
      await sb.from("nf_push_devices").delete().in("token", deadTokens);
    }
  })();

  await Promise.all([tgTask, fcmTask]);
  return out;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  try {
    const payload = await req.json();

    // 0. Ping cepat untuk pg_cron keep-warm
    if (payload?.ping === true) {
      return jsonRes({ ok: true, pong: true });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || "";
    const tgToken = (Deno.env.get("TELEGRAM_BOT_TOKEN") || "").trim();
    const tgChatId = (Deno.env.get("TELEGRAM_CHAT_ID") || "").trim();
    const fcmSaRaw = (Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") || "").trim();

    const sb = (supabaseUrl && serviceKey)
      ? createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
      : null;

    const replyUrl = supabaseUrl ? `${supabaseUrl}/functions/v1/send-push` : "";

    // =========================================================================
    // 1. DIRECT REPLY CHAT DARI NOTIFIKASI ANDROID (v149 — SAVES + INSTANT PUSH)
    // =========================================================================
    if (payload?.action === "direct_reply") {
      if (!sb) return jsonRes({ ok: false, error: "Supabase service unavailable" }, 500);

      const orderId = extractOrderId(payload.order_id);
      const receiptToken = String(payload.receipt_token || "").trim().toUpperCase();
      const message = String(payload.message || "").trim().slice(0, 500);
      const rawRole = String(payload.sender_role || "customer").toLowerCase();
      const senderRole = ["customer", "store", "courier"].includes(rawRole) ? rawRole : "customer";
      const senderName = String(
        payload.sender_name ||
        (senderRole === "customer" ? "Pelanggan" : (senderRole === "courier" ? "Kurir" : "Kasir NutriFresh"))
      ).trim().slice(0, 80);

      if (!orderId || !receiptToken || !message) {
        return jsonRes({ ok: false, error: "Data balasan tidak lengkap" }, 400);
      }

      const ordRec = await fetchOrderJson(sb, orderId);
      if (!ordRec) {
        return jsonRes({ ok: false, error: "Pesanan tidak ditemukan" }, 404);
      }

      const curData = { ...ordRec.data };
      const expectedTok = String(curData.receiptToken || curData.receipt_token || "").trim().toUpperCase();
      if (!expectedTok || expectedTok !== receiptToken) {
        return jsonRes({ ok: false, error: "Token pesanan tidak valid" }, 403);
      }

      const curChat = Array.isArray(curData.orderChat) ? [...curData.orderChat] : [];
      const custNameFromData = String(curData.customerName || curData.customer_name || senderName);
      const finalSenderName = senderRole === "customer" ? custNameFromData : senderName;
      const msgObj = {
        id: "MSG-" + Date.now() + "-" + Math.random().toString(36).slice(2, 6).toUpperCase(),
        sender: senderRole,
        name: finalSenderName,
        text: message,
        at: new Date().toISOString(),
      };
      curChat.push(msgObj);
      curData.orderChat = curChat;
      curData.updatedAt = new Date().toISOString();

      const { error: updErr } = await sb
        .from("nf_online_orders")
        .update({ data: curData, updated_at: new Date().toISOString() })
        .eq("id", ordRec.id);

      if (updErr) {
        return jsonRes({ ok: false, error: updErr.message }, 500);
      }

      // Langsung kirim push notifikasi ke lawan bicara (< 1 detik!)
      const targetRoles = senderRole === "customer" ? ["pos", "staff"] : ["customer"];
      const custPhone = String(curData.customerPhone || curData.customer_phone || "");
      const notifTitle = senderRole === "customer"
        ? `💬 Chat dari ${finalSenderName} (#${ordRec.id})`
        : `💬 Pesan dari ${finalSenderName} (#${ordRec.id})`;
      const notifBody = message;

      await Promise.allSettled(targetRoles.map(async (tRole) => {
        const fcmData: Record<string, string> = {
          title: notifTitle,
          body: notifBody,
          target_role: tRole,
          ref_id: ordRec.id,
          outbox_id: `chat:${ordRec.id}:${msgObj.id}`,
          dedupe_key: `chat:${ordRec.id}:${msgObj.id}`,
          event_type: "chat",
          sender_name: finalSenderName,
          chat_text: message,
          reply_url: replyUrl,
          reply_apikey: anonKey,
        };
        populateOrderEnrichment(fcmData, ordRec.id, curData, tRole, true, notifBody);
        await sendToRoleTargets({
          sb, fcmSaRaw, tgToken, tgChatId,
          tenantId: "nutrifresh",
          targetRole: tRole,
          targetPhone: tRole === "customer" ? custPhone : "",
          targetEmail: "",
          title: notifTitle,
          body: notifBody,
          fcmData,
        });
      }));

      return jsonRes({ ok: true, messageId: msgObj.id, chatCount: curChat.length });
    }

    // =========================================================================
    // 2. DIRECT PUSH INSTAN DARI POS / STAFF / CUSTOMER (v149 — ZERO DELAY!)
    // =========================================================================
    if (payload?.action === "dispatch_order_push") {
      if (!sb) return jsonRes({ ok: false, error: "Supabase service unavailable" }, 500);

      const orderId = extractOrderId(payload.order_id, payload.ref_id, payload.title);
      if (!orderId) return jsonRes({ ok: false, error: "order_id diperlukan" }, 400);

      const ordRec = await fetchOrderJson(sb, orderId);
      const oData = ordRec ? ordRec.data : {};
      const custPhone = String(payload.target_phone || oData.customerPhone || oData.customer_phone || "");
      const rolesRaw = Array.isArray(payload.target_roles)
        ? payload.target_roles
        : [payload.target_role || "customer"];
      const targetRoles = rolesRaw.map((r: unknown) => String(r || "").toLowerCase()).filter(Boolean);

      const eventType = String(payload.event_type || "order_status");
      const isChat = eventType === "chat";
      const title = String(payload.title || `Update Pesanan #${orderId}`);
      const body = String(payload.body || "");
      const silentLiveOnly = payload.silent_live_only === true ? "1" : "0";
      const statusNow = String(oData.orderStatus || oData.order_status || "");
      const dedupeKey = String(
        payload.dedupe_key ||
        (isChat ? `chat:${orderId}:${String(payload.chat_text || body).slice(0, 40)}` : `st:${orderId}:${statusNow}`)
      );

      const perRoleResults: Record<string, unknown> = {};
      await Promise.allSettled(targetRoles.map(async (tRole) => {
        const fcmData: Record<string, string> = {
          title,
          body,
          target_role: tRole,
          ref_id: orderId,
          outbox_id: dedupeKey,
          dedupe_key: dedupeKey,
          event_type: eventType,
          silent_live_only: silentLiveOnly,
          reply_url: replyUrl,
          reply_apikey: anonKey,
        };
        if (payload.sender_name) fcmData.sender_name = String(payload.sender_name);
        if (payload.chat_text) fcmData.chat_text = String(payload.chat_text);
        if (ordRec) {
          populateOrderEnrichment(fcmData, ordRec.id, oData, tRole, isChat, body);
        }
        perRoleResults[tRole] = await sendToRoleTargets({
          sb, fcmSaRaw, tgToken, tgChatId,
          tenantId: String(payload.tenant_id || "nutrifresh"),
          targetRole: tRole,
          targetPhone: tRole === "customer" ? custPhone : "",
          targetEmail: String(payload.target_email || "").trim().toLowerCase(),
          title,
          body,
          fcmData,
        });
      }));

      // Tandai outbox tertunda untuk order & role yang sama agar cron 10 menit tidak kirim ulang dobel!
      try {
        await sb
          .from("nf_push_outbox")
          .update({ sent_at: new Date().toISOString() })
          .eq("ref_id", orderId)
          .in("target_role", targetRoles)
          .is("sent_at", null);
      } catch (_) {}

      return jsonRes({ ok: true, orderId, results: perRoleResults });
    }

    // =========================================================================
    // 3. WEBHOOK INSERT DARI public.nf_push_outbox
    // =========================================================================
    const rec = payload?.record || payload;
    if (!rec || !rec.title) {
      return jsonRes({ ok: false, reason: "empty payload" }, 400);
    }
    if (rec.sent_at) {
      return jsonRes({ ok: true, skipped: "already_sent", recId: rec.id ?? null });
    }

    const targetRole = String(rec.target_role || "").toLowerCase();
    let targetPhone = String(rec.target_phone || "").replace(/\D/g, "");
    const targetEmail = String(rec.target_email || "").trim().toLowerCase();
    const title = String(rec.title || "NutriFresh");
    const body = String(rec.body || "");
    const rawRefId = String(rec.ref_id || "").trim();
    const orderId = extractOrderId(rawRefId, title, body);

    const isChatNotif = title.includes("💬") || title.includes("Pesan dari") || title.includes("Chat dari");
    const eventType = isChatNotif ? "chat" : (orderId ? "order_status" : "general");

    const fcmData: Record<string, string> = {
      title,
      body,
      target_role: targetRole,
      ref_id: orderId || rawRefId,
      outbox_id: String(rec.id || ""),
      event_type: eventType,
      reply_url: replyUrl,
      reply_apikey: anonKey,
    };

    let orderEnriched = false;
    if (orderId && sb) {
      const ordRec = await fetchOrderJson(sb, orderId);
      if (ordRec) {
        populateOrderEnrichment(fcmData, ordRec.id, ordRec.data, targetRole, isChatNotif, body);
        orderEnriched = true;
        if (!targetPhone && targetRole === "customer") {
          targetPhone = String(ordRec.data.customerPhone || ordRec.data.customer_phone || "").replace(/\D/g, "");
        }
        const statusNow = fcmData.order_status || "";
        fcmData.dedupe_key = isChatNotif
          ? `chat:${ordRec.id}:${(fcmData.chat_text || body).slice(0, 40)}`
          : `st:${ordRec.id}:${statusNow}`;
      }
    }
    if (!fcmData.dedupe_key) {
      fcmData.dedupe_key = `outbox:${rec.id || title}`;
    }

    const sendRes = await sendToRoleTargets({
      sb, fcmSaRaw, tgToken, tgChatId,
      tenantId: String(rec.tenant_id || "nutrifresh"),
      targetRole,
      targetPhone,
      targetEmail,
      title,
      body,
      fcmData,
    });

    let updateError: string | null = null;
    if (rec.id !== undefined && rec.id !== null && sb) {
      const { error: updErr } = await sb
        .from("nf_push_outbox")
        .update({ sent_at: new Date().toISOString() })
        .eq("id", rec.id);
      if (updErr) updateError = updErr.message;
    }

    return jsonRes({
      ok: true,
      recId: rec.id ?? null,
      orderId,
      orderEnriched,
      ...sendRes,
      updateError,
    });
  } catch (err) {
    return jsonRes({ ok: false, error: String(err) }, 500);
  }
});
