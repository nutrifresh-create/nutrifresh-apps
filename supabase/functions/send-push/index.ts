// Supabase Edge Function: send-push (NutriFresh v151 — COD Menunggu Persetujuan + Direct Reply RPC + Smart Staff Filter)
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

function normalizeChatDedupe(rawText: string): string {
  let s = String(rawText || "").trim();
  // Buang awalan "Nama Pengirim: " jika berasal dari trigger outbox agar identik dengan dispatch_order_push
  const colonIdx = s.indexOf(":");
  if (colonIdx > 0 && colonIdx < 32) {
    s = s.slice(colonIdx + 1).trim();
  }
  return s.toLowerCase().replace(/\s+/g, " ").slice(0, 60);
}

function inferStatusFromText(title: string, body: string): string {
  const t = `${title || ""} ${body || ""}`.toLowerCase();
  if (t.includes("pesanan selesai") || t.includes("antaran lunas selesai")) return "Selesai";
  if (t.includes("dibatalkan")) return "Dibatalkan";
  if (t.includes("telah diterima")) return "Terkirim • Lunas";
  if (t.includes("sedang diantar") || t.includes("berangkat antar")) return "Diantar Kurir";
  if (t.includes("siap diantar kurir") || t.includes("siap diambil kurir")) return "Siap Diambil Kurir";
  if (t.includes("siap diambil di toko")) return "Siap Diambil";
  if (t.includes("setujui timbangan") || t.includes("acc timbangan")) return "Disetujui — Siap Kirim";
  if (t.includes("bukti bayar masuk")) return "Menunggu Verifikasi Bayar";
  if (t.includes("selesai ditimbang") || t.includes("hasil timbangan siap")) return "Menunggu Pembayaran";
  if (t.includes("sedang ditimbang")) return "Sedang Ditimbang";
  return "";
}

function isCourierStageStatus(st: string): boolean {
  return [
    "Siap Diambil Kurir",
    "Siap Kirim",
    "Diantar Kurir",
    "Terkirim • Tunggu Setor COD",
  ].includes(String(st || "").trim());
}

function isCodPayment(pm: string): boolean {
  return /cash|tunai|cod/i.test(String(pm || ""));
}

function formatStatusForRole(st: string, targetRole: string, paymentMethod = ""): string {
  const s = String(st || "").trim();
  if (targetRole === "customer") {
    if (["Menunggu Pembayaran", "Menunggu Konfirmasi"].includes(s) && isCodPayment(paymentMethod)) {
      return "Menunggu Persetujuan";
    }
    if (s.startsWith("Terkirim")) {
      return "Pesanan Diterima • Menunggu Resi";
    }
  }
  return s;
}

function getOrderStep(st: string): number {
  if (st === "Selesai" || st.startsWith("Terkirim") || st.startsWith("Pesanan Diterima")) return 5;
  if ([
    "Diantar Kurir",
    "Siap Diambil",
    "Disetujui — Siap Kirim",
    "Disetujui — Siap Diambil",
    "Siap Diambil Kurir",
  ].includes(st)) return 4;
  if (["Menunggu Pembayaran", "Menunggu Persetujuan", "Menunggu Konfirmasi", "Menunggu Verifikasi Bayar"].includes(st)) return 3;
  if (st === "Sedang Ditimbang") return 2;
  return 1;
}

interface MergedOrder {
  id: string;
  tenantId: string;
  orderCode: string;
  receiptToken: string;
  customerName: string;
  customerPhone: string;
  deliveryMode: string;
  paymentMethod: string;
  orderStatus: string;
  estimatedTotal: number;
  finalTotal: number;
  shippingFee: number;
  courierName: string;
  items: Array<Record<string, unknown>>;
  orderChat: Array<Record<string, unknown>>;
  rawData: Record<string, unknown>;
}

function buildItemsSummary(items: Array<Record<string, unknown>>): string {
  if (!Array.isArray(items) || items.length === 0) return "Pesanan buah segar NutriFresh";
  const parts = items.slice(0, 4).map((it) => {
    const q = formatQtyShort(Number(it?.qty) || 0, String(it?.unit || "Gram"));
    const nm = String(it?.name || "Buah").replace("[OBRAL]", "").trim();
    return `${q} ${nm}`;
  });
  if (items.length > 4) parts.push(`+${items.length - 4} item lainnya`);
  return parts.join(", ").slice(0, 260);
}

// Baca seluruh kolom relasional nf_online_orders + gabungkan dengan JSONB `data`
// (Kolom teratas SELALU menang atas `data` — 100% identik dengan rowToItem di supabase-adapter.js!)
// deno-lint-ignore no-explicit-any
async function fetchOrderRecord(sb: any, orderId: string, tenantId = "nutrifresh"): Promise<MergedOrder | null> {
  if (!sb || !orderId) return null;
  const cleanId = orderId.replace(/^#/, "").trim();
  let { data: row, error: qErr } = await sb
    .from("nf_online_orders")
    .select("*")
    .eq("tenant_id", tenantId)
    .eq("id", cleanId)
    .maybeSingle();
  if (qErr) console.error("[send-push] fetchOrderRecord(id) error:", qErr.code, qErr.message);

  if (!row) {
    const alt = await sb
      .from("nf_online_orders")
      .select("*")
      .eq("tenant_id", tenantId)
      .eq("order_code", cleanId)
      .maybeSingle();
    if (alt.error) console.error("[send-push] fetchOrderRecord(code) error:", alt.error.code, alt.error.message);
    row = alt.data || null;
  }
  if (!row) return null;

  const d = (row.data && typeof row.data === "object") ? (row.data as Record<string, unknown>) : {};
  const est = Number(row.estimated_total ?? d.estimatedTotal) || 0;
  const fin = Number(row.final_total ?? d.finalTotal ?? est) || 0;
  const ship = Number(row.shipping_fee ?? d.shippingFee) || 0;
  const weighed = Array.isArray(d.weighedItems) && d.weighedItems.length > 0
    ? (d.weighedItems as Array<Record<string, unknown>>)
    : (Array.isArray(row.items) && row.items.length > 0
      ? (row.items as Array<Record<string, unknown>>)
      : (Array.isArray(d.items) ? (d.items as Array<Record<string, unknown>>) : []));
  const chat = Array.isArray(row.order_chat)
    ? (row.order_chat as Array<Record<string, unknown>>)
    : (Array.isArray(d.orderChat) ? (d.orderChat as Array<Record<string, unknown>>) : []);

  return {
    id: String(row.id || cleanId),
    tenantId: String(row.tenant_id || tenantId),
    orderCode: String(row.order_code || d.orderCode || row.id || cleanId),
    receiptToken: String(row.receipt_token || d.receiptToken || d.receipt_token || "").trim().toUpperCase(),
    customerName: String(row.customer_name || d.customerName || "Pelanggan"),
    customerPhone: String(row.customer_phone || d.customerPhone || ""),
    deliveryMode: String(row.delivery_mode || d.deliveryMode || "Kirim ke Rumah"),
    paymentMethod: String(row.payment_method || d.paymentMethod || ""),
    orderStatus: String(row.order_status || d.orderStatus || "Menunggu Timbang"),
    estimatedTotal: est,
    finalTotal: fin,
    shippingFee: ship,
    courierName: String(row.courier_name || d.courierName || ""),
    items: weighed,
    orderChat: chat,
    rawData: d,
  };
}

function populateOrderEnrichment(
  fcmData: Record<string, string>,
  ord: MergedOrder,
  targetRole: string,
  isChatNotif: boolean,
  fallbackBody: string,
  overrides: Record<string, unknown> = {},
) {
  const rawStatus = String(overrides.order_status || ord.orderStatus || "Menunggu Timbang");
  const status = formatStatusForRole(rawStatus, targetRole, String(overrides.payment_method || ord.paymentMethod || ""));
  const grand = (ord.finalTotal || ord.estimatedTotal || 0) + (ord.shippingFee || 0);

  fcmData.order_id = ord.id;
  fcmData.order_code = ord.orderCode;
  fcmData.order_status = status;
  fcmData.step = String(getOrderStep(rawStatus));
  fcmData.items_summary = String(overrides.items_summary || buildItemsSummary(ord.items));
  fcmData.total_text = String(overrides.total_text || formatRp(grand));
  fcmData.receipt_token = String(overrides.receipt_token || ord.receiptToken || "");
  fcmData.customer_name = String(overrides.customer_name || ord.customerName || "Pelanggan");
  fcmData.courier_name = String(overrides.courier_name || ord.courierName || "");
  fcmData.delivery_mode = String(overrides.delivery_mode || ord.deliveryMode || "Kirim ke Rumah");

  if (isChatNotif) {
    const lastMsg = ord.orderChat.length > 0 ? ord.orderChat[ord.orderChat.length - 1] : null;
    if (!fcmData.sender_name) {
      fcmData.sender_name = String(lastMsg?.name || (targetRole === "customer" ? "Toko NutriFresh" : fcmData.customer_name));
    }
    if (!fcmData.chat_text) {
      fcmData.chat_text = String(lastMsg?.text || fallbackBody);
    }
  }
}

// deno-lint-ignore no-explicit-any
async function markOutboxSent(sb: any, orderId: string, targetRoles: string[]) {
  if (!sb || !orderId || targetRoles.length === 0) return;
  try {
    await sb
      .from("nf_push_outbox")
      .update({ sent_at: new Date().toISOString() })
      .eq("ref_id", orderId)
      .in("target_role", targetRoles)
      .is("sent_at", null);
  } catch (_) {}
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
    if (tgToken && tgChatId && ["pos", "staff", "office"].includes(targetRole)) {
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
    const tenantId = String(payload?.tenant_id || "nutrifresh");

    // =========================================================================
    // 1. DIRECT REPLY CHAT DARI NOTIFIKASI ANDROID (v150 — OFFICIAL RPC + DUAL COLUMN!)
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

      const ord = await fetchOrderRecord(sb, orderId, tenantId);
      const finalSenderName = senderRole === "customer" ? (ord?.customerName || senderName) : senderName;
      let savedViaRpc = false;

      // Jalur 1 (Pelanggan): Panggil langsung RPC resmi nf_customer_send_order_chat (SECURITY DEFINER — validasi token langsung di Postgres!)
      if (senderRole === "customer") {
        const { error: rpcErr } = await sb.rpc("nf_customer_send_order_chat", {
          p_order_id: ord?.id || orderId,
          p_token: receiptToken,
          p_message: message,
          p_sender_name: finalSenderName,
          p_tenant_id: ord?.tenantId || tenantId,
        });
        if (!rpcErr) {
          savedViaRpc = true;
        } else {
          console.error("[send-push] nf_customer_send_order_chat error:", rpcErr.message);
          if (!ord) {
            const msgLow = String(rpcErr.message || "").toLowerCase();
            const code = msgLow.includes("token") ? 403 : (msgLow.includes("tidak ditemukan") ? 404 : 500);
            return jsonRes({ ok: false, error: rpcErr.message }, code);
          }
        }
      }

      // Jalur 2 (Kasir/Kurir atau cadangan): Validasi token + update KEDUA kolom `order_chat` & `data.orderChat`
      if (!savedViaRpc) {
        if (!ord) {
          return jsonRes({ ok: false, error: "Pesanan tidak ditemukan (cek GRANT nf_online_orders ke service_role)" }, 404);
        }
        if (!ord.receiptToken || ord.receiptToken !== receiptToken) {
          return jsonRes({ ok: false, error: "Token pesanan tidak valid" }, 403);
        }
        const curChat = [...ord.orderChat];
        const msgObj = {
          id: "MSG-" + Date.now() + "-" + Math.random().toString(36).slice(2, 6).toUpperCase(),
          sender: senderRole,
          name: finalSenderName,
          text: message,
          at: new Date().toISOString(),
        };
        curChat.push(msgObj);
        const nextData = { ...ord.rawData, orderChat: curChat, updatedAt: new Date().toISOString() };
        const { error: updErr } = await sb
          .from("nf_online_orders")
          .update({
            order_chat: curChat,
            data: nextData,
            updated_at: new Date().toISOString(),
          })
          .eq("tenant_id", ord.tenantId)
          .eq("id", ord.id);

        if (updErr) {
          return jsonRes({ ok: false, error: updErr.message }, 500);
        }
      }

      // Ambil ulang data terbaru & kirim push instan (< 1 detik) ke lawan bicara
      const freshOrd = (await fetchOrderRecord(sb, ord?.id || orderId, ord?.tenantId || tenantId)) || ord;
      const ordCode = freshOrd?.orderCode || orderId;
      const ordIdFinal = freshOrd?.id || orderId;
      const ordTenant = freshOrd?.tenantId || tenantId;
      const includeCourier = isCourierStageStatus(freshOrd?.orderStatus || "");
      const targetRoles = senderRole === "customer"
        ? (includeCourier ? ["pos", "staff"] : ["pos"])
        : ["customer"];
      const notifTitle = senderRole === "customer"
        ? `💬 Chat dari ${finalSenderName} (#${ordCode})`
        : `💬 Pesan dari ${finalSenderName} (#${ordCode})`;
      const dedupeKey = `chat:${ordIdFinal}:${normalizeChatDedupe(message)}`;

      await Promise.allSettled(targetRoles.map(async (tRole) => {
        const fcmData: Record<string, string> = {
          title: notifTitle,
          body: message,
          target_role: tRole,
          ref_id: ordIdFinal,
          order_id: ordIdFinal,
          order_code: ordCode,
          receipt_token: freshOrd?.receiptToken || receiptToken,
          outbox_id: dedupeKey,
          dedupe_key: dedupeKey,
          event_type: "chat",
          sender_name: finalSenderName,
          chat_text: message,
          reply_url: replyUrl,
          reply_apikey: anonKey,
        };
        if (freshOrd) {
          populateOrderEnrichment(fcmData, freshOrd, tRole, true, message);
        }
        await sendToRoleTargets({
          sb, fcmSaRaw, tgToken, tgChatId,
          tenantId: ordTenant,
          targetRole: tRole,
          targetPhone: tRole === "customer" ? (freshOrd?.customerPhone || "") : "",
          targetEmail: "",
          title: notifTitle,
          body: message,
          fcmData,
        });
      }));

      await markOutboxSent(sb, ordIdFinal, targetRoles);
      return jsonRes({ ok: true, savedViaRpc, orderId: ordIdFinal });
    }

    // =========================================================================
    // 2. DIRECT PUSH INSTAN DARI POS / STAFF / CUSTOMER (v150 — ZERO THROTTLE!)
    // =========================================================================
    if (payload?.action === "dispatch_order_push") {
      if (!sb) return jsonRes({ ok: false, error: "Supabase service unavailable" }, 500);

      const orderId = extractOrderId(payload.order_id, payload.ref_id, payload.title);
      if (!orderId) return jsonRes({ ok: false, error: "order_id diperlukan" }, 400);

      const ord = await fetchOrderRecord(sb, orderId, tenantId);
      const custPhone = String(payload.target_phone || ord?.customerPhone || "");
      const eventType = String(payload.event_type || "order_status");
      const isChat = eventType === "chat";
      const title = String(payload.title || `Update Pesanan #${orderId}`);
      const body = String(payload.body || "");
      const effectiveStatus = String(
        payload.order_status || ord?.orderStatus || inferStatusFromText(title, body) || ""
      );

      const rolesRaw = Array.isArray(payload.target_roles)
        ? payload.target_roles
        : [payload.target_role || "customer"];
      const targetRoles = rolesRaw
        .map((r: unknown) => String(r || "").toLowerCase())
        .filter((r: string) => {
          if (!r) return false;
          // Jangan kirim chat pelanggan ke HP Kurir/Staff jika paket belum diserahkan ke kurir!
          if (isChat && r === "staff" && !isCourierStageStatus(effectiveStatus)) return false;
          return true;
        });

      const dedupeKey = String(
        payload.dedupe_key ||
        (isChat
          ? `chat:${orderId}:${normalizeChatDedupe(String(payload.chat_text || body))}`
          : `st:${orderId}:${(effectiveStatus || title).toLowerCase().trim()}`)
      );

      const perRoleResults: Record<string, unknown> = {};
      await Promise.allSettled(targetRoles.map(async (tRole) => {
        const fcmData: Record<string, string> = {
          title,
          body,
          target_role: tRole,
          ref_id: orderId,
          order_id: orderId,
          order_code: String(ord?.orderCode || orderId),
          outbox_id: dedupeKey,
          dedupe_key: dedupeKey,
          event_type: eventType,
          reply_url: replyUrl,
          reply_apikey: anonKey,
        };
        if (payload.sender_name) fcmData.sender_name = String(payload.sender_name);
        if (payload.chat_text) fcmData.chat_text = String(payload.chat_text);

        if (ord) {
          populateOrderEnrichment(fcmData, ord, tRole, isChat, body, payload);
        } else {
          if (effectiveStatus) {
            fcmData.order_status = formatStatusForRole(effectiveStatus, tRole, String(payload.payment_method || ""));
            fcmData.step = String(getOrderStep(effectiveStatus));
          }
          if (payload.receipt_token) fcmData.receipt_token = String(payload.receipt_token).toUpperCase();
          if (payload.items_summary) fcmData.items_summary = String(payload.items_summary);
          if (payload.total_text) fcmData.total_text = String(payload.total_text);
          if (payload.courier_name) fcmData.courier_name = String(payload.courier_name);
          if (payload.customer_name) fcmData.customer_name = String(payload.customer_name);
        }

        perRoleResults[tRole] = await sendToRoleTargets({
          sb, fcmSaRaw, tgToken, tgChatId,
          tenantId,
          targetRole: tRole,
          targetPhone: tRole === "customer" ? custPhone : "",
          targetEmail: String(payload.target_email || "").trim().toLowerCase(),
          title,
          body,
          fcmData,
        });
      }));

      await markOutboxSent(sb, orderId, targetRoles);
      return jsonRes({ ok: true, orderId, effectiveStatus, results: perRoleResults });
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

    const recTenant = String(rec.tenant_id || "nutrifresh");
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
    let skipStaffEarlyChat = false;
    if (orderId && sb) {
      const ord = await fetchOrderRecord(sb, orderId, recTenant);
      if (ord) {
        if (isChatNotif && targetRole === "staff" && !isCourierStageStatus(ord.orderStatus)) {
          skipStaffEarlyChat = true;
        }
        populateOrderEnrichment(fcmData, ord, targetRole, isChatNotif, body);
        orderEnriched = true;
        if (!targetPhone && targetRole === "customer") {
          targetPhone = ord.customerPhone.replace(/\D/g, "");
        }
        const statusNow = ord.orderStatus || inferStatusFromText(title, body) || title;
        fcmData.dedupe_key = isChatNotif
          ? `chat:${ord.id}:${normalizeChatDedupe(fcmData.chat_text || body)}`
          : `st:${ord.id}:${statusNow.toLowerCase().trim()}`;
      } else {
        const inferred = inferStatusFromText(title, body);
        if (inferred) {
          fcmData.order_id = orderId;
          fcmData.order_status = formatStatusForRole(inferred, targetRole);
          fcmData.step = String(getOrderStep(inferred));
        }
        fcmData.dedupe_key = isChatNotif
          ? `chat:${orderId}:${normalizeChatDedupe(body)}`
          : `st:${orderId}:${(inferred || title).toLowerCase().trim()}`;
      }
    }
    if (skipStaffEarlyChat) {
      if (rec.id !== undefined && rec.id !== null && sb) {
        await sb.from("nf_push_outbox").update({ sent_at: new Date().toISOString() }).eq("id", rec.id);
      }
      return jsonRes({ ok: true, skipped: "staff_not_in_courier_stage", orderId });
    }
    if (!fcmData.dedupe_key) {
      fcmData.dedupe_key = `outbox:${rec.id || title}`;
    }

    const sendRes = await sendToRoleTargets({
      sb, fcmSaRaw, tgToken, tgChatId,
      tenantId: recTenant,
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
