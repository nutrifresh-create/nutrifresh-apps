// Supabase Edge Function: send-push (NutriFresh v147 — Data-Only FCM + Live Order Enrichment + Direct Reply)
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

Deno.serve(async (req: Request) => {
  try {
    const payload = await req.json();

    // 0. Ping cepat untuk pg_cron keep-warm
    if (payload?.ping === true) {
      return new Response(JSON.stringify({ ok: true, pong: true }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
    const sb = (supabaseUrl && serviceKey)
      ? createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
      : null;

    // 1. DIRECT REPLY CHAT DARI NOTIFIKASI ANDROID (TANPA BUKA APLIKASI — v147)
    if (payload?.action === "direct_reply") {
      if (!sb) {
        return new Response(JSON.stringify({ ok: false, error: "Supabase service unavailable" }), { status: 500 });
      }
      const orderId = String(payload.order_id || "").trim();
      const receiptToken = String(payload.receipt_token || "").trim().toUpperCase();
      const message = String(payload.message || "").trim().slice(0, 500);
      const rawRole = String(payload.sender_role || "customer").toLowerCase();
      const senderRole = ["customer", "store", "courier"].includes(rawRole) ? rawRole : "customer";
      const senderName = String(payload.sender_name || (senderRole === "customer" ? "Pelanggan" : (senderRole === "courier" ? "Kurir" : "Kasir NutriFresh"))).trim().slice(0, 80);

      if (!orderId || !receiptToken || !message) {
        return new Response(JSON.stringify({ ok: false, error: "Data balasan tidak lengkap" }), { status: 400 });
      }

      const { data: ord, error: fetchErr } = await sb
        .from("nf_online_orders")
        .select("id, receipt_token, customer_name, data")
        .eq("id", orderId)
        .maybeSingle();

      if (fetchErr || !ord) {
        return new Response(JSON.stringify({ ok: false, error: "Pesanan tidak ditemukan" }), { status: 404 });
      }

      const expectedTok = String(ord.receipt_token || (ord.data as Record<string, unknown>)?.receiptToken || "").trim().toUpperCase();
      if (!expectedTok || expectedTok !== receiptToken) {
        return new Response(JSON.stringify({ ok: false, error: "Token pesanan tidak valid" }), { status: 403 });
      }

      const curData = (ord.data && typeof ord.data === "object") ? { ...(ord.data as Record<string, unknown>) } : {};
      const curChat = Array.isArray(curData.orderChat) ? [...curData.orderChat] : [];
      const msgObj = {
        id: "MSG-" + Date.now() + "-" + Math.random().toString(36).slice(2, 6).toUpperCase(),
        sender: senderRole,
        name: senderRole === "customer" ? (String(ord.customer_name || senderName)) : senderName,
        text: message,
        at: new Date().toISOString(),
      };
      curChat.push(msgObj);
      curData.orderChat = curChat;

      const { error: updErr } = await sb
        .from("nf_online_orders")
        .update({ data: curData, updated_at: new Date().toISOString() })
        .eq("id", orderId);

      if (updErr) {
        return new Response(JSON.stringify({ ok: false, error: updErr.message }), { status: 500 });
      }

      return new Response(JSON.stringify({ ok: true, messageId: msgObj.id, chatCount: curChat.length }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    // 2. WEBHOOK INSERT DARI public.nf_push_outbox
    const rec = payload?.record || payload;
    if (!rec || !rec.title) {
      return new Response(JSON.stringify({ ok: false, reason: "empty payload" }), { status: 400 });
    }

    const tgToken = (Deno.env.get("TELEGRAM_BOT_TOKEN") || "").trim();
    const tgChatId = (Deno.env.get("TELEGRAM_CHAT_ID") || "").trim();
    const fcmSaRaw = (Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") || "").trim();

    const targetRole = String(rec.target_role || "").toLowerCase();
    const targetPhone = String(rec.target_phone || "").replace(/\D/g, "");
    const targetEmail = String(rec.target_email || "").trim().toLowerCase();
    const title = String(rec.title || "NutriFresh");
    const body = String(rec.body || "");
    const refId = String(rec.ref_id || "").trim();

    const results: Record<string, unknown> = {
      recId: rec.id ?? null,
      matchedTokens: 0,
      fcmSent: 0,
      telegramSent: false,
      updateError: null,
    };

    // Klasifikasi jenis notifikasi + perkaya data pesanan secara otomatis untuk Live Order & Direct Reply
    const isChatNotif = title.includes("💬") || title.includes("Pesan dari") || title.includes("Chat dari");
    const isOrderRef = refId.startsWith("ORD-");
    const eventType = isChatNotif ? "chat" : (isOrderRef ? "order_status" : "general");

    const fcmData: Record<string, string> = {
      title,
      body,
      target_role: targetRole,
      ref_id: refId,
      outbox_id: String(rec.id || ""),
      event_type: eventType,
      reply_url: supabaseUrl ? `${supabaseUrl}/functions/v1/send-push` : "",
    };

    // Ambil detail live pesanan dari nf_online_orders jika ini terkait order (untuk Live Card & Direct Reply!)
    const orderEnrichTask = (async () => {
      if (!isOrderRef || !sb) return;
      try {
        const { data: ord } = await sb
          .from("nf_online_orders")
          .select("id, order_code, receipt_token, customer_name, delivery_mode, order_status, estimated_total, final_total, shipping_fee, courier_name, data")
          .eq("id", refId)
          .maybeSingle();
        if (!ord) return;
        const oData = (ord.data && typeof ord.data === "object") ? (ord.data as Record<string, unknown>) : {};
        const status = String(ord.order_status || oData.orderStatus || "Menunggu Timbang");
        const grand = (Number(ord.final_total) || Number(ord.estimated_total) || Number(oData.finalTotal) || Number(oData.estimatedTotal) || 0)
          + (Number(ord.shipping_fee) || Number(oData.shippingFee) || 0);
        const rTok = String(ord.receipt_token || oData.receiptToken || "");

        fcmData.order_id = String(ord.id || refId);
        fcmData.order_code = String(ord.order_code || ord.id || refId);
        fcmData.order_status = status;
        fcmData.step = String(getOrderStep(status));
        fcmData.items_summary = buildItemsSummary(oData);
        fcmData.total_text = formatRp(grand);
        fcmData.receipt_token = rTok;
        fcmData.customer_name = String(ord.customer_name || oData.customerName || "Pelanggan");
        fcmData.courier_name = String(ord.courier_name || oData.courierName || "");
        fcmData.delivery_mode = String(ord.delivery_mode || oData.deliveryMode || "Kirim ke Rumah");

        if (isChatNotif) {
          const chatArr = Array.isArray(oData.orderChat) ? oData.orderChat : [];
          const lastMsg = chatArr.length > 0 ? (chatArr[chatArr.length - 1] as Record<string, unknown>) : null;
          fcmData.sender_name = String(lastMsg?.name || (targetRole === "customer" ? "Toko NutriFresh" : fcmData.customer_name));
          fcmData.chat_text = String(lastMsg?.text || body);
        }
      } catch (_) {}
    })();

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
      await orderEnrichTask;

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

      const deadTokens: string[] = [];
      let sentCount = 0;

      // DATA-ONLY + android.priority HIGH:
      // Selalu memanggil NfFirebaseMessagingService.onMessageReceived() di background & foreground
      // untuk kontrol penuh: Anti-Duplikat, Live Order ala Gojek & Direct Reply Chat!
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
