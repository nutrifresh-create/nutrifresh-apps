import base64
import json
import os
import re
import sys
from pathlib import Path

# Universal Android Release Signing + Auto versionCode + Smart Permissions (v145)
# + Native In-App Self-Updater (v146) + Gojek-Style Live Order, Direct Reply & Zero-Duplicate FCM (v147)
# Usage: python3 scripts/configure_android_release_and_fcm.py <mobile_subdir> <package_id> <channel_id> [app_role]

LIVE_ORDER_HELPER_JAVA = r"""package __PACKAGE_ID__;

import android.app.Activity;
import android.app.Application;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.Bundle;
import androidx.core.app.NotificationCompat;
import androidx.core.app.Person;
import androidx.core.app.RemoteInput;
import java.lang.ref.WeakReference;
import java.util.Iterator;
import java.util.LinkedHashSet;
import java.util.Map;
import org.json.JSONArray;
import org.json.JSONObject;

public class NfLiveOrderHelper {
    public static final String CH_ALERTS = "__CHANNEL_ID__";
    public static final String CH_LIVE = "__CHANNEL_ID___live";
    public static final String APP_ROLE = "__APP_ROLE__";
    public static final String PREFS = "nf_live_order_prefs";
    public static final String REPLY_KEY = "nf_direct_reply_text";
    public static final String EXTRA_OPEN_ORDER_ID = "nf_open_order_id";
    public static final String DEFAULT_REPLY_URL = "https://dsidhlpgdanmgndrbksx.supabase.co/functions/v1/send-push";
    public static final String DEFAULT_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRzaWRobHBnZGFubWduZHJia3N4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTUyMzU4MjksImV4cCI6MjExMDgxMTgyOX0.lMPZB67yKcaT55sJjSZG-p0QJuuEc4Tfvez3GA_GA7o";
    public static final int LIVE_ORDER_NOTIF_ID = 904200;

    private static volatile boolean appInForeground = false;
    private static volatile boolean lifecycleRegistered = false;
    private static WeakReference<MainActivity> activeMainActivity = new WeakReference<>(null);
    private static final LinkedHashSet<String> recentOutboxIds = new LinkedHashSet<>();
    private static final LinkedHashSet<Integer> activeChatNotifIds = new LinkedHashSet<>();
    private static volatile String pendingOpenOrderId = "";

    public static void ensureChannels(Context ctx) {
        if (ctx == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        try {
            NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null) return;

            NotificationChannel chAlerts = new NotificationChannel(
                CH_ALERTS,
                "Notifikasi & Chat NutriFresh",
                NotificationManager.IMPORTANCE_HIGH
            );
            chAlerts.setDescription("Notifikasi pesanan buah, status timbangan, kurir & pesan chat NutriFresh");
            chAlerts.enableVibration(true);
            chAlerts.setShowBadge(true);
            nm.createNotificationChannel(chAlerts);

            NotificationChannel chLive = new NotificationChannel(
                CH_LIVE,
                "Status Pesanan Aktif (Live)",
                NotificationManager.IMPORTANCE_LOW
            );
            chLive.setDescription("Kartu status pesanan aktif ala Gojek saat berada di luar aplikasi");
            chLive.setSound(null, null);
            chLive.enableVibration(false);
            chLive.setShowBadge(false);
            nm.createNotificationChannel(chLive);
        } catch (Exception ignored) {}
    }

    public static void registerLifecycle(final MainActivity activity) {
        if (activity == null) return;
        ensureChannels(activity);
        activeMainActivity = new WeakReference<>(activity);
        appInForeground = true;
        cancelLiveOrderNotification(activity);
        clearTrackedChatNotifications(activity);
        handleLaunchIntent(activity, activity.getIntent());

        if (lifecycleRegistered) return;
        lifecycleRegistered = true;
        try {
            activity.getApplication().registerActivityLifecycleCallbacks(new Application.ActivityLifecycleCallbacks() {
                @Override
                public void onActivityCreated(Activity act, Bundle savedInstanceState) {
                    if (act instanceof MainActivity) {
                        ensureChannels(act);
                        activeMainActivity = new WeakReference<>((MainActivity) act);
                    }
                }
                @Override
                public void onActivityStarted(Activity act) {
                    if (act instanceof MainActivity) {
                        activeMainActivity = new WeakReference<>((MainActivity) act);
                    }
                }
                @Override
                public void onActivityResumed(Activity act) {
                    if (act instanceof MainActivity) {
                        activeMainActivity = new WeakReference<>((MainActivity) act);
                        appInForeground = true;
                        cancelLiveOrderNotification(act);
                        clearTrackedChatNotifications(act);
                        dispatchJs("if(window.__nfOnAppResume){window.__nfOnAppResume();}");
                        flushPendingOpenOrder();
                    }
                }
                @Override
                public void onActivityPaused(Activity act) {
                    if (act instanceof MainActivity) {
                        appInForeground = false;
                        showLiveOrderIfActive(act);
                    }
                }
                @Override
                public void onActivityStopped(Activity act) {
                    if (act instanceof MainActivity) {
                        appInForeground = false;
                        showLiveOrderIfActive(act);
                    }
                }
                @Override
                public void onActivitySaveInstanceState(Activity act, Bundle outState) {}
                @Override
                public void onActivityDestroyed(Activity act) {}
            });
        } catch (Exception ignored) {}
    }

    public static boolean isAppInForeground() {
        return appInForeground;
    }

    public static void handleLaunchIntent(Context ctx, Intent intent) {
        if (intent == null) return;
        try {
            String ordId = intent.getStringExtra(EXTRA_OPEN_ORDER_ID);
            if (ordId != null && !ordId.trim().isEmpty()) {
                pendingOpenOrderId = ordId.trim();
                intent.removeExtra(EXTRA_OPEN_ORDER_ID);
                flushPendingOpenOrder();
            }
        } catch (Exception ignored) {}
    }

    public static void flushPendingOpenOrder() {
        final String ordId = pendingOpenOrderId;
        if (ordId == null || ordId.isEmpty()) return;
        final MainActivity act = activeMainActivity.get();
        if (act == null || act.isFinishing()) return;
        pendingOpenOrderId = "";
        act.runOnUiThread(() -> {
            try {
                if (act.getBridge() != null && act.getBridge().getWebView() != null) {
                    act.getBridge().getWebView().postDelayed(() -> {
                        try {
                            if (act.getBridge() != null && act.getBridge().getWebView() != null) {
                                act.getBridge().getWebView().evaluateJavascript(
                                    "if(window.__nfOpenOrderFromNotif){window.__nfOpenOrderFromNotif(" + JSONObject.quote(ordId) + ");}",
                                    null
                                );
                            }
                        } catch (Exception ignored) {}
                    }, 450);
                }
            } catch (Exception ignored) {}
        });
    }

    public static void dispatchJs(final String jsCode) {
        final MainActivity act = activeMainActivity.get();
        if (act == null || act.isFinishing()) return;
        act.runOnUiThread(() -> {
            try {
                if (act.getBridge() != null && act.getBridge().getWebView() != null) {
                    act.getBridge().getWebView().evaluateJavascript(jsCode, null);
                }
            } catch (Exception ignored) {}
        });
    }

    public static void dispatchPushToWebView(final String jsonPayload) {
        dispatchJs("if(window.__nfOnPushReceived){window.__nfOnPushReceived(" + JSONObject.quote(jsonPayload) + ");}");
    }

    public static synchronized boolean isDuplicateOutboxId(Context ctx, String dedupeKey) {
        if (dedupeKey == null || dedupeKey.trim().isEmpty()) return false;
        String key = dedupeKey.trim();
        if (recentOutboxIds.contains(key)) return true;
        long now = System.currentTimeMillis();
        if (ctx != null) {
            try {
                SharedPreferences sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
                JSONObject map = new JSONObject(sp.getString("seen_push_keys", "{}"));
                long prevTs = map.optLong(key, 0L);
                if (prevTs > 0L && (now - prevTs) < 900000L) { // 15 menit anti-duplikat persisten
                    recentOutboxIds.add(key);
                    return true;
                }
                // Bersihkan key kadaluarsa (> 20 menit)
                JSONObject fresh = new JSONObject();
                Iterator<String> keys = map.keys();
                while (keys.hasNext()) {
                    String k = keys.next();
                    long ts = map.optLong(k, 0L);
                    if (ts > 0L && (now - ts) < 1200000L) fresh.put(k, ts);
                }
                fresh.put(key, now);
                sp.edit().putString("seen_push_keys", fresh.toString()).apply();
            } catch (Exception ignored) {}
        }
        recentOutboxIds.add(key);
        if (recentOutboxIds.size() > 60) {
            Iterator<String> it = recentOutboxIds.iterator();
            if (it.hasNext()) {
                it.next();
                it.remove();
            }
        }
        return false;
    }

    public static void saveLiveOrderState(Context ctx, String jsonStr) {
        if (ctx == null || jsonStr == null) return;
        try {
            JSONObject obj = new JSONObject(jsonStr);
            boolean active = obj.optBoolean("active", false);
            SharedPreferences sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            if (!active) {
                sp.edit().putBoolean("active", false).apply();
                cancelLiveOrderNotification(ctx);
                return;
            }
            String oidSave = obj.optString("orderId", "").trim();
            String tokSave = obj.optString("receiptToken", "").trim();
            SharedPreferences.Editor ed = sp.edit()
                .putBoolean("active", true)
                .putString("order_id", oidSave)
                .putString("order_code", obj.optString("orderCode", oidSave))
                .putString("receipt_token", tokSave)
                .putString("customer_name", obj.optString("customerName", "Pelanggan"))
                .putString("status", obj.optString("status", "Menunggu Timbang"))
                .putInt("step", Math.max(1, Math.min(5, obj.optInt("step", 1))))
                .putString("items_summary", obj.optString("itemsSummary", "Pesanan buah segar NutriFresh"))
                .putString("total_text", obj.optString("totalText", "Rp 0"))
                .putString("courier_name", obj.optString("courierName", ""))
                .putString("delivery_mode", obj.optString("deliveryMode", "Kirim ke Rumah"))
                .putString("reply_url", obj.optString("replyUrl", DEFAULT_REPLY_URL))
                .putString("reply_apikey", obj.optString("replyApiKey", sp.getString("reply_apikey", DEFAULT_ANON_KEY)));
            if (!oidSave.isEmpty() && !tokSave.isEmpty()) ed.putString("tok_" + oidSave, tokSave);
            ed.commit();
            if (!appInForeground) {
                showLiveOrderIfActive(ctx);
            }
        } catch (Exception ignored) {}
    }

    public static void updateLiveOrderFromFcm(Context ctx, Map<String, String> data) {
        if (ctx == null || data == null) return;
        if (!"customer".equals(APP_ROLE)) return;
        String orderId = safe(data.get("order_id")).replace("#", "");
        if (orderId.isEmpty()) orderId = safe(data.get("ref_id")).replace("#", "");
        if (!orderId.startsWith("ORD-")) return;

        SharedPreferences sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String rTok = safe(data.get("receipt_token"));
        if (!rTok.isEmpty()) {
            sp.edit().putString("tok_" + orderId, rTok).putString("receipt_token", rTok).commit();
        }

        String status = safe(data.get("order_status"));
        if (status.isEmpty()) return;

        if ("Selesai".equalsIgnoreCase(status) || "Dibatalkan".equalsIgnoreCase(status)) {
            sp.edit().putBoolean("active", false).commit();
            cancelLiveOrderNotification(ctx);
            return;
        }

        int step = 1;
        try { step = Integer.parseInt(safe(data.get("step"))); } catch (Exception ignored) {}
        step = Math.max(1, Math.min(5, step));

        SharedPreferences.Editor ed = sp.edit();
        ed.putBoolean("active", true);
        ed.putString("order_id", orderId);
        if (!safe(data.get("order_code")).isEmpty()) ed.putString("order_code", safe(data.get("order_code")));
        else if (sp.getString("order_code", "").isEmpty()) ed.putString("order_code", orderId);
        if (!rTok.isEmpty()) {
            ed.putString("receipt_token", rTok);
            ed.putString("tok_" + orderId, rTok);
        }
        if (!safe(data.get("customer_name")).isEmpty()) ed.putString("customer_name", safe(data.get("customer_name")));
        ed.putString("status", status);
        ed.putInt("step", step);
        if (!safe(data.get("items_summary")).isEmpty()) ed.putString("items_summary", safe(data.get("items_summary")));
        if (!safe(data.get("total_text")).isEmpty()) ed.putString("total_text", safe(data.get("total_text")));
        if (!safe(data.get("courier_name")).isEmpty()) ed.putString("courier_name", safe(data.get("courier_name")));
        if (!safe(data.get("delivery_mode")).isEmpty()) ed.putString("delivery_mode", safe(data.get("delivery_mode")));
        if (!safe(data.get("reply_url")).isEmpty()) ed.putString("reply_url", safe(data.get("reply_url")));
        if (!safe(data.get("reply_apikey")).isEmpty()) ed.putString("reply_apikey", safe(data.get("reply_apikey")));
        ed.commit();

        if (!appInForeground) {
            showLiveOrderIfActive(ctx);
        }
    }

    public static void cancelLiveOrderNotification(Context ctx) {
        if (ctx == null) return;
        try {
            NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm != null) nm.cancel(LIVE_ORDER_NOTIF_ID);
        } catch (Exception ignored) {}
    }

    public static synchronized void clearTrackedChatNotifications(Context ctx) {
        if (ctx == null) return;
        try {
            NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm != null) {
                for (Integer id : activeChatNotifIds) {
                    nm.cancel(id);
                }
            }
            activeChatNotifIds.clear();
            // Bersihkan riwayat pesan notifikasi yang sudah dibaca agar notifikasi chat baru tampil bersih
            SharedPreferences sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            SharedPreferences.Editor ed = sp.edit();
            boolean changed = false;
            for (String k : sp.getAll().keySet()) {
                if (k != null && (k.startsWith("chat_hist_") || k.equals("last_reply_note"))) {
                    ed.remove(k);
                    changed = true;
                }
            }
            if (changed) ed.apply();
        } catch (Exception ignored) {}
    }

    public static void showLiveOrderIfActive(Context ctx) {
        if (ctx == null || !"customer".equals(APP_ROLE) || appInForeground) return;
        try {
            SharedPreferences sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            if (!sp.getBoolean("active", false)) {
                cancelLiveOrderNotification(ctx);
                return;
            }
            String status = sp.getString("status", "Menunggu Timbang");
            if ("Selesai".equalsIgnoreCase(status) || "Dibatalkan".equalsIgnoreCase(status)) {
                sp.edit().putBoolean("active", false).apply();
                cancelLiveOrderNotification(ctx);
                return;
            }
            ensureChannels(ctx);
            NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null) return;

            String orderId = sp.getString("order_id", "");
            String orderCode = sp.getString("order_code", orderId);
            String receiptToken = sp.getString("receipt_token", "");
            String customerName = sp.getString("customer_name", "Pelanggan");
            int step = Math.max(1, Math.min(5, sp.getInt("step", 1)));
            String itemsSummary = sp.getString("items_summary", "Pesanan buah segar NutriFresh");
            String totalText = sp.getString("total_text", "Rp 0");
            String courierName = sp.getString("courier_name", "");
            String replyUrl = sp.getString("reply_url", DEFAULT_REPLY_URL);
            String replyApiKey = sp.getString("reply_apikey", "");

            String emoji = (step >= 5 || status.startsWith("Pesanan Diterima")) ? "✅" : (step == 4 ? "🛵" : (step == 3 ? ((status.contains("Persetujuan") || status.contains("Konfirmasi")) ? "⚖️" : "💳") : (step == 2 ? "⚖️" : "🍐")));
            String title = emoji + " " + status + " • #" + orderCode;
            String shortLine = totalText + " • " + itemsSummary;
            StringBuilder big = new StringBuilder();
            big.append("Tahap ").append(step).append("/5: ").append(status);
            big.append("\nBuah: ").append(itemsSummary);
            big.append("\nTotal: ").append(totalText);
            if (!courierName.isEmpty()) {
                big.append("\nKurir: ").append(courierName);
            }
            String lastReplyNote = sp.getString("last_reply_note", "");
            long lastReplyAt = sp.getLong("last_reply_at", 0L);
            if (!lastReplyNote.isEmpty() && (System.currentTimeMillis() - lastReplyAt) < 90000L) {
                big.append("\n").append(lastReplyNote);
            }

            Intent launch = new Intent(ctx, MainActivity.class);
            launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            launch.putExtra(EXTRA_OPEN_ORDER_ID, orderId);
            PendingIntent pi = PendingIntent.getActivity(
                ctx,
                LIVE_ORDER_NOTIF_ID,
                launch,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            );

            NotificationCompat.Builder b = new NotificationCompat.Builder(ctx, CH_LIVE)
                .setSmallIcon(ctx.getApplicationInfo().icon)
                .setContentTitle(title)
                .setContentText(shortLine)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(big.toString()))
                .setProgress(5, step, false)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setAutoCancel(false)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_PROGRESS)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setContentIntent(pi);

            // Kartu Live Order bersih tanpa tombol Balas (ketuk untuk membuka Pesanan Saya)

            nm.notify(LIVE_ORDER_NOTIF_ID, b.build());
        } catch (Exception ignored) {}
    }

    public static void showAlertNotification(
        Context ctx,
        String title,
        String body,
        String eventType,
        String refId,
        Map<String, String> data
    ) {
        if (ctx == null) return;
        try {
            ensureChannels(ctx);
            NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null) return;

            String cleanRef = safe(refId);
            boolean isChat = "chat".equalsIgnoreCase(safe(eventType))
                || title.contains("💬") || title.contains("Pesan dari") || title.contains("Chat dari");

            int notifId;
            if (isChat && !cleanRef.isEmpty()) {
                notifId = 700000 + Math.abs(cleanRef.hashCode() % 100000);
            } else if (!cleanRef.isEmpty()) {
                notifId = 600000 + Math.abs(cleanRef.hashCode() % 100000);
            } else {
                notifId = 500000 + Math.abs((title + "|" + body).hashCode() % 100000);
            }

            Intent launch = new Intent(ctx, MainActivity.class);
            launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            if (!cleanRef.isEmpty()) launch.putExtra(EXTRA_OPEN_ORDER_ID, cleanRef);
            PendingIntent pi = PendingIntent.getActivity(
                ctx,
                notifId,
                launch,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            );

            if (isChat && !cleanRef.isEmpty()) {
                synchronized (NfLiveOrderHelper.class) {
                    activeChatNotifIds.add(notifId);
                }
                String senderName = data != null ? safe(data.get("sender_name")) : "";
                if (senderName.isEmpty()) {
                    senderName = "customer".equals(APP_ROLE) ? "Toko NutriFresh" : "Pelanggan";
                }
                String chatText = data != null ? safe(data.get("chat_text")) : "";
                if (chatText.isEmpty()) chatText = body;

                appendChatHistoryLine(ctx, cleanRef, senderName, chatText, false);

                String cleanOrdRef = cleanRef.replace("#", "");
                SharedPreferences spKey = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
                String receiptToken = data != null ? safe(data.get("receipt_token")) : "";
                if (!receiptToken.isEmpty()) {
                    spKey.edit().putString("tok_" + cleanOrdRef, receiptToken).apply();
                } else {
                    receiptToken = spKey.getString("tok_" + cleanOrdRef, "");
                    if (receiptToken.isEmpty() && cleanOrdRef.equals(spKey.getString("order_id", ""))) {
                        receiptToken = spKey.getString("receipt_token", "");
                    }
                }
                String replyUrl = data != null && !safe(data.get("reply_url")).isEmpty() ? safe(data.get("reply_url")) : DEFAULT_REPLY_URL;
                String replyApiKey = data != null && !safe(data.get("reply_apikey")).isEmpty() ? safe(data.get("reply_apikey")) : spKey.getString("reply_apikey", DEFAULT_ANON_KEY);
                if (replyApiKey == null || replyApiKey.trim().isEmpty()) replyApiKey = DEFAULT_ANON_KEY;
                spKey.edit().putString("reply_apikey", replyApiKey).apply();
                String myName = "customer".equals(APP_ROLE)
                    ? (data != null && !safe(data.get("customer_name")).isEmpty() ? safe(data.get("customer_name")) : "Pelanggan")
                    : ("staff".equals(APP_ROLE) ? "Kurir NutriFresh" : "Kasir NutriFresh");
                String myRole = "customer".equals(APP_ROLE) ? "customer" : ("staff".equals(APP_ROLE) ? "courier" : "store");

                showChatNotification(ctx, notifId, cleanRef, title, receiptToken, myRole, myName, replyUrl, replyApiKey, false);
                return;
            }

            NotificationCompat.Builder b = new NotificationCompat.Builder(ctx, CH_ALERTS)
                .setSmallIcon(ctx.getApplicationInfo().icon)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setAutoCancel(true)
                .setContentIntent(pi);

            nm.notify(notifId, b.build());
        } catch (Exception ignored) {}
    }

    public static void appendChatHistoryLine(Context ctx, String orderId, String senderName, String text, boolean isSelf) {
        try {
            SharedPreferences sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            String key = "chat_hist_" + orderId;
            JSONArray arr = new JSONArray(sp.getString(key, "[]"));
            JSONObject item = new JSONObject();
            item.put("sender", senderName);
            item.put("text", text);
            item.put("ts", System.currentTimeMillis());
            item.put("self", isSelf);
            arr.put(item);
            // Keep only last 6 messages in notification thread
            while (arr.length() > 6) {
                arr.remove(0);
            }
            sp.edit().putString(key, arr.toString()).apply();
        } catch (Exception ignored) {}
    }

    public static void showChatNotification(
        Context ctx,
        int notifId,
        String orderId,
        String convTitle,
        String receiptToken,
        String myRole,
        String myName,
        String replyUrl,
        String replyApiKey,
        boolean silentUpdate
    ) {
        try {
            ensureChannels(ctx);
            NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null) return;

            Person me = new Person.Builder().setName("Anda").build();
            NotificationCompat.MessagingStyle style = new NotificationCompat.MessagingStyle(me)
                .setConversationTitle(convTitle != null && !convTitle.isEmpty() ? convTitle : ("Chat #" + orderId));

            SharedPreferences sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            JSONArray arr = new JSONArray(sp.getString("chat_hist_" + orderId, "[]"));
            String lastText = "";
            for (int i = 0; i < arr.length(); i++) {
                JSONObject it = arr.optJSONObject(i);
                if (it == null) continue;
                boolean isSelf = it.optBoolean("self", false);
                String txt = it.optString("text", "");
                long ts = it.optLong("ts", System.currentTimeMillis());
                lastText = txt;
                Person p = isSelf ? me : new Person.Builder().setName(it.optString("sender", "NutriFresh")).build();
                style.addMessage(txt, ts, p);
            }

            Intent launch = new Intent(ctx, MainActivity.class);
            launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            launch.putExtra(EXTRA_OPEN_ORDER_ID, orderId);
            PendingIntent pi = PendingIntent.getActivity(
                ctx,
                notifId,
                launch,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            );

            NotificationCompat.Builder b = new NotificationCompat.Builder(ctx, CH_ALERTS)
                .setSmallIcon(ctx.getApplicationInfo().icon)
                .setContentTitle(convTitle != null && !convTitle.isEmpty() ? convTitle : ("Chat #" + orderId))
                .setContentText(lastText)
                .setStyle(style)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setAutoCancel(true)
                .setContentIntent(pi);

            if (silentUpdate) {
                b.setSilent(true).setOnlyAlertOnce(true);
            } else {
                b.setDefaults(NotificationCompat.DEFAULT_ALL);
            }

            if (orderId != null && !orderId.isEmpty() && receiptToken != null && !receiptToken.isEmpty()) {
                NotificationCompat.Action replyAction = buildDirectReplyAction(
                    ctx, orderId, receiptToken, myRole, myName, replyUrl, replyApiKey, notifId, false
                );
                if (replyAction != null) b.addAction(replyAction);
            }

            nm.notify(notifId, b.build());
        } catch (Exception ignored) {}
    }

    private static NotificationCompat.Action buildDirectReplyAction(
        Context ctx,
        String orderId,
        String receiptToken,
        String myRole,
        String myName,
        String replyUrl,
        String replyApiKey,
        int notifId,
        boolean isLiveOrder
    ) {
        try {
            RemoteInput remoteInput = new RemoteInput.Builder(REPLY_KEY)
                .setLabel("Tulis balasan cepat...")
                .build();
            Intent replyIntent = new Intent(ctx, NfDirectReplyReceiver.class);
            replyIntent.putExtra("order_id", orderId);
            replyIntent.putExtra("receipt_token", receiptToken);
            replyIntent.putExtra("sender_role", myRole);
            replyIntent.putExtra("sender_name", myName);
            replyIntent.putExtra("reply_url", replyUrl != null && !replyUrl.isEmpty() ? replyUrl : DEFAULT_REPLY_URL);
            replyIntent.putExtra("reply_apikey", replyApiKey != null ? replyApiKey : "");
            replyIntent.putExtra("notif_id", notifId);
            replyIntent.putExtra("is_live_order", isLiveOrder);

            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= 31) {
                flags |= PendingIntent.FLAG_MUTABLE;
            }
            PendingIntent replyPi = PendingIntent.getBroadcast(
                ctx,
                notifId + (isLiveOrder ? 17 : 31),
                replyIntent,
                flags
            );
            return new NotificationCompat.Action.Builder(
                android.R.drawable.ic_menu_send,
                isLiveOrder ? "💬 Balas Chat" : "Balas",
                replyPi
            ).addRemoteInput(remoteInput).setAllowGeneratedReplies(true).build();
        } catch (Exception e) {
            return null;
        }
    }

    private static String safe(String s) {
        return s == null ? "" : s.trim();
    }
}
"""

DIRECT_REPLY_RECEIVER_JAVA = r"""package __PACKAGE_ID__;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import androidx.core.app.RemoteInput;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import org.json.JSONObject;

public class NfDirectReplyReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(final Context context, final Intent intent) {
        if (context == null || intent == null) return;
        Bundle remoteInput = RemoteInput.getResultsFromIntent(intent);
        if (remoteInput == null) return;
        CharSequence seq = remoteInput.getCharSequence(NfLiveOrderHelper.REPLY_KEY);
        final String replyText = seq != null ? seq.toString().trim() : "";
        if (replyText.isEmpty()) return;

        final String orderId = intent.getStringExtra("order_id");
        final String receiptToken = intent.getStringExtra("receipt_token");
        final String senderRole = intent.getStringExtra("sender_role");
        final String senderName = intent.getStringExtra("sender_name");
        final String replyUrl = intent.getStringExtra("reply_url");
        String tmpApiKey = intent.getStringExtra("reply_apikey");
        if (tmpApiKey == null || tmpApiKey.trim().isEmpty()) {
            tmpApiKey = context.getSharedPreferences(NfLiveOrderHelper.PREFS, Context.MODE_PRIVATE).getString("reply_apikey", NfLiveOrderHelper.DEFAULT_ANON_KEY);
        }
        if (tmpApiKey == null || tmpApiKey.trim().isEmpty()) tmpApiKey = NfLiveOrderHelper.DEFAULT_ANON_KEY;
        final String replyApiKey = tmpApiKey.trim();
        final int notifId = intent.getIntExtra("notif_id", 700001);
        final boolean isLiveOrder = intent.getBooleanExtra("is_live_order", false);

        if (orderId == null || orderId.isEmpty() || receiptToken == null || receiptToken.isEmpty()) return;

        final PendingResult pendingResult = goAsync();
        new Thread(() -> {
            HttpURLConnection conn = null;
            boolean ok = false;
            int httpCode = 0;
            try {
                String cleanOid = orderId.replace("#", "").trim();
                String endpoint = (replyUrl != null && replyUrl.startsWith("http")) ? replyUrl : NfLiveOrderHelper.DEFAULT_REPLY_URL;
                JSONObject body = new JSONObject();
                body.put("action", "direct_reply");
                body.put("order_id", cleanOid);
                body.put("receipt_token", receiptToken.trim());
                body.put("sender_role", senderRole != null ? senderRole : "customer");
                body.put("sender_name", senderName != null ? senderName : "Pelanggan");
                body.put("message", replyText);

                conn = (HttpURLConnection) new URL(endpoint).openConnection();
                conn.setRequestMethod("POST");
                conn.setConnectTimeout(15000);
                conn.setReadTimeout(15000);
                conn.setDoOutput(true);
                conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8");
                conn.setRequestProperty("apikey", replyApiKey);
                conn.setRequestProperty("Authorization", "Bearer " + replyApiKey);
                byte[] outBytes = body.toString().getBytes("UTF-8");
                OutputStream os = conn.getOutputStream();
                os.write(outBytes);
                os.flush();
                os.close();

                httpCode = conn.getResponseCode();
                ok = (httpCode >= 200 && httpCode < 300);
            } catch (Exception ignored) {
                ok = false;
            } finally {
                if (conn != null) conn.disconnect();
            }

            try {
                if (isLiveOrder) {
                    context.getSharedPreferences(NfLiveOrderHelper.PREFS, Context.MODE_PRIVATE)
                        .edit()
                        .putString("last_reply_note", ok ? ("Pesan terkirim: \"" + replyText + "\" ✓") : ("Gagal kirim pesan — coba lagi"))
                        .putLong("last_reply_at", System.currentTimeMillis())
                        .apply();
                    NfLiveOrderHelper.showLiveOrderIfActive(context);
                    if (ok) {
                        NfLiveOrderHelper.appendChatHistoryLine(context, orderId, "Anda", replyText + " ✓", true);
                    }
                } else {
                    if (ok) {
                        NfLiveOrderHelper.appendChatHistoryLine(context, orderId, "Anda", replyText + " ✓", true);
                        NfLiveOrderHelper.showChatNotification(
                            context, notifId, orderId, "Chat Pesanan #" + orderId,
                            receiptToken, senderRole != null ? senderRole : "customer",
                            senderName != null ? senderName : "Pelanggan", replyUrl, replyApiKey, true
                        );
                    } else {
                        // Tampilkan status gagal sementara tanpa menyimpan permanen ke riwayat pesan
                        NfLiveOrderHelper.showChatNotification(
                            context, notifId, orderId, (httpCode > 0 ? ("Gagal kirim (" + httpCode + ") • Coba lagi") : "Gagal kirim (Jaringan) • Coba lagi"),
                            receiptToken, senderRole != null ? senderRole : "customer",
                            senderName != null ? senderName : "Pelanggan", replyUrl, replyApiKey, true
                        );
                    }
                }
                if (ok) {
                    NfLiveOrderHelper.dispatchJs("if(window.__nfOnAppResume){window.__nfOnAppResume();}");
                }
            } catch (Exception ignored) {}

            try { pendingResult.finish(); } catch (Exception ignored) {}
        }).start();
    }
}
"""

FCM_SERVICE_JAVA = """package __PACKAGE_ID__;

import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;
import java.util.Map;
import org.json.JSONObject;

public class NfFirebaseMessagingService extends FirebaseMessagingService {
    @Override
    public void onNewToken(String token) {
        super.onNewToken(token);
        try {
            getSharedPreferences("nf_push_prefs", MODE_PRIVATE)
                .edit()
                .putString("fcm_token", token)
                .apply();
        } catch (Exception ignored) {}
    }

    @Override
    public void onMessageReceived(RemoteMessage remoteMessage) {
        super.onMessageReceived(remoteMessage);
        String title = "NutriFresh";
        String body = "";
        if (remoteMessage.getNotification() != null) {
            if (remoteMessage.getNotification().getTitle() != null) title = remoteMessage.getNotification().getTitle();
            if (remoteMessage.getNotification().getBody() != null) body = remoteMessage.getNotification().getBody();
        }
        Map<String, String> data = remoteMessage.getData();
        if (data != null) {
            if (data.containsKey("title") && data.get("title") != null) title = data.get("title");
            if (data.containsKey("body") && data.get("body") != null) body = data.get("body");
        }

        // Selalu simpan reply_apikey terbaru & perbarui kartu Live Order terlebih dahulu (instan di background!)
        if (data != null && data.get("reply_apikey") != null && !data.get("reply_apikey").trim().isEmpty()) {
            try {
                getSharedPreferences(NfLiveOrderHelper.PREFS, MODE_PRIVATE)
                    .edit()
                    .putString("reply_apikey", data.get("reply_apikey").trim())
                    .apply();
            } catch (Exception ignored) {}
        }
        NfLiveOrderHelper.updateLiveOrderFromFcm(this, data);

        String dedupeKey = (data != null && data.get("dedupe_key") != null && !data.get("dedupe_key").trim().isEmpty())
            ? data.get("dedupe_key").trim()
            : (data != null ? data.get("outbox_id") : "");
        if (NfLiveOrderHelper.isDuplicateOutboxId(this, dedupeKey)) {
            return;
        }

        String eventType = data != null && data.get("event_type") != null ? data.get("event_type") : "general";
        String refId = data != null && data.get("ref_id") != null ? data.get("ref_id") : "";

        // Jika pengguna sedang membuka aplikasi (foreground):
        // Langsung picu refresh WebView instan (< 1 detik) + banner in-app!
        if (NfLiveOrderHelper.isAppInForeground()) {
            try {
                JSONObject j = new JSONObject();
                j.put("title", title);
                j.put("body", body);
                j.put("eventType", eventType);
                j.put("refId", refId);
                j.put("outboxId", dedupeKey != null ? dedupeKey : "");
                if (data != null) {
                    if (data.get("order_status") != null) j.put("orderStatus", data.get("order_status"));
                    if (data.get("sender_name") != null) j.put("senderName", data.get("sender_name"));
                }
                NfLiveOrderHelper.dispatchPushToWebView(j.toString());
            } catch (Exception ignored) {}
            return;
        }

        // Pengguna sedang di luar aplikasi (Home Screen / WA / Layar Mati):
        // Selalu tampilkan notifikasi IMPORTANCE_HIGH agar FCM Android tidak pernah menunda/throttle aplikasi!
        NfLiveOrderHelper.showAlertNotification(this, title, body, eventType, refId, data);
    }
}
"""

UPDATE_PROVIDER_JAVA = """package __PACKAGE_ID__;

import androidx.core.content.FileProvider;

public class NfUpdateFileProvider extends FileProvider {
}
"""

UPDATE_PATHS_XML = """<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <cache-path name="nf_updates_cache" path="." />
    <external-files-path name="nf_updates_ext" path="." />
    <files-path name="nf_updates_files" path="." />
</paths>
"""

SMART_PERM_AND_UPDATER_FIELDS = r"""
    private static final String NF_UPDATE_MANIFEST_URL = "__UPDATE_MANIFEST_URL__";
    private final java.util.concurrent.atomic.AtomicBoolean nfUpdateDownloading = new java.util.concurrent.atomic.AtomicBoolean(false);
    private android.webkit.WebView nfHiddenPrintWebView = null;

    private java.net.HttpURLConnection nfOpenFollowRedirects(String rawUrl, int timeoutMs) throws Exception {
        String currentUrl = rawUrl;
        for (int hops = 0; hops < 8; hops++) {
            java.net.HttpURLConnection conn = (java.net.HttpURLConnection) new java.net.URL(currentUrl).openConnection();
            conn.setInstanceFollowRedirects(false);
            conn.setConnectTimeout(timeoutMs);
            conn.setReadTimeout(timeoutMs);
            conn.setRequestProperty("User-Agent", "NutriFresh-Android-Updater/1.51");
            conn.setRequestProperty("Cache-Control", "no-cache");
            int code = conn.getResponseCode();
            if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
                String loc = conn.getHeaderField("Location");
                conn.disconnect();
                if (loc == null || loc.isEmpty()) throw new Exception("Redirect kosong dari server.");
                java.net.URL base = new java.net.URL(currentUrl);
                currentUrl = new java.net.URL(base, loc).toExternalForm();
                continue;
            }
            return conn;
        }
        throw new Exception("Terlalu banyak pengalihan (redirect) saat mengunduh.");
    }

    private void nfEmitUpdateProgress(final int percent, final String status, final String message) {
        runOnUiThread(() -> {
            try {
                if (this.bridge != null && this.bridge.getWebView() != null) {
                    String js = "if(window.__nfOnUpdateProgress){window.__nfOnUpdateProgress("
                        + percent + ","
                        + org.json.JSONObject.quote(status != null ? status : "") + ","
                        + org.json.JSONObject.quote(message != null ? message : "") + ");}";
                    this.bridge.getWebView().evaluateJavascript(js, null);
                }
            } catch (Exception ignored) {}
        });
    }

    private boolean nfLaunchApkInstaller(java.io.File apkFile) {
        try {
            if (apkFile == null || !apkFile.exists() || apkFile.length() < 100000) return false;
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                if (!getPackageManager().canRequestPackageInstalls()) {
                    nfEmitUpdateProgress(100, "NEED_PERMISSION", "Aktifkan izin 'Izinkan dari sumber ini' lalu tekan Kembali.");
                    return false;
                }
            }
            android.net.Uri apkUri = androidx.core.content.FileProvider.getUriForFile(
                MainActivity.this,
                getPackageName() + ".nfupdateprovider",
                apkFile
            );
            android.content.Intent intent = new android.content.Intent(android.content.Intent.ACTION_VIEW);
            intent.setDataAndType(apkUri, "application/vnd.android.package-archive");
            intent.addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION | android.content.Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
            nfEmitUpdateProgress(100, "INSTALLING", "Membuka layar pemasangan Android...");
            return true;
        } catch (Exception e) {
            nfEmitUpdateProgress(0, "ERROR", "Gagal membuka pemasang APK: " + e.getMessage());
            return false;
        }
    }

    public class NfAndroidNativeBridge {"""

SMART_PERM_AND_UPDATER_METHODS = r"""
        @JavascriptInterface
        public void syncActiveOrderState(final String jsonStr) {
            try {
                NfLiveOrderHelper.saveLiveOrderState(MainActivity.this, jsonStr);
            } catch (Exception ignored) {}
        }

        @JavascriptInterface
        public void printHtmlDocument(final String jobName, final String htmlContent) {
            runOnUiThread(() -> {
                try {
                    if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.KITKAT) return;
                    final String safeJob = (jobName != null && !jobName.trim().isEmpty()) ? jobName.trim() : "NutriFresh_Dokumen";
                    final android.webkit.WebView wv = new android.webkit.WebView(MainActivity.this);
                    wv.getSettings().setJavaScriptEnabled(false);
                    wv.setWebViewClient(new android.webkit.WebViewClient() {
                        @Override
                        public void onPageFinished(android.webkit.WebView view, String url) {
                            try {
                                android.print.PrintManager pm = (android.print.PrintManager) getSystemService(PRINT_SERVICE);
                                if (pm != null) {
                                    android.print.PrintDocumentAdapter adapter = android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP
                                        ? view.createPrintDocumentAdapter(safeJob)
                                        : view.createPrintDocumentAdapter();
                                    pm.print(safeJob, adapter, new android.print.PrintAttributes.Builder().build());
                                }
                            } catch (Exception ignored) {}
                            nfHiddenPrintWebView = null;
                        }
                    });
                    nfHiddenPrintWebView = wv;
                    wv.loadDataWithBaseURL("https://nutrifresh.my.id/", htmlContent != null ? htmlContent : "", "text/html", "UTF-8", null);
                } catch (Exception ignored) {}
            });
        }

        @JavascriptInterface
        public void clearLiveOrderNotification() {
            try {
                NfLiveOrderHelper.saveLiveOrderState(MainActivity.this, "{\"active\":false}");
            } catch (Exception ignored) {}
        }

        @JavascriptInterface
        public String getAppVersionJson() {
            try {
                android.content.pm.PackageInfo pi = getPackageManager().getPackageInfo(getPackageName(), 0);
                long vCode = android.os.Build.VERSION.SDK_INT >= 28 ? pi.getLongVersionCode() : pi.versionCode;
                org.json.JSONObject obj = new org.json.JSONObject();
                obj.put("versionCode", vCode);
                obj.put("versionName", pi.versionName != null ? pi.versionName : "1.0");
                obj.put("packageName", getPackageName());
                obj.put("updateUrl", NF_UPDATE_MANIFEST_URL);
                return obj.toString();
            } catch (Exception e) {
                return "{}";
            }
        }

        @JavascriptInterface
        public boolean canInstallUnknownApps() {
            try {
                if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.O) return true;
                return getPackageManager().canRequestPackageInstalls();
            } catch (Exception e) {
                return true;
            }
        }

        @JavascriptInterface
        public void openInstallUnknownAppsSettings() {
            runOnUiThread(() -> {
                try {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        android.content.Intent i = new android.content.Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES);
                        i.setData(android.net.Uri.parse("package:" + getPackageName()));
                        startActivity(i);
                        return;
                    }
                } catch (Exception ignored) {}
                openAppInfoSettings();
            });
        }

        @JavascriptInterface
        public void checkAppUpdateAsync(final String customUrl) {
            new Thread(() -> {
                String targetUrl = (customUrl != null && !customUrl.trim().isEmpty()) ? customUrl.trim() : NF_UPDATE_MANIFEST_URL;
                String sep = targetUrl.contains("?") ? "&" : "?";
                String finalUrl = targetUrl + sep + "t=" + System.currentTimeMillis();
                String resultJson = "{\"ok\":false,\"error\":\"Gagal menghubungi server rilis.\"}";
                java.net.HttpURLConnection conn = null;
                try {
                    conn = nfOpenFollowRedirects(finalUrl, 10000);
                    int code = conn.getResponseCode();
                    if (code >= 200 && code < 300) {
                        java.io.BufferedReader br = new java.io.BufferedReader(new java.io.InputStreamReader(conn.getInputStream(), "UTF-8"));
                        StringBuilder sb = new StringBuilder();
                        String line;
                        while ((line = br.readLine()) != null) sb.append(line);
                        br.close();
                        String body = sb.toString().trim();
                        if (body.startsWith("{")) {
                            org.json.JSONObject remote = new org.json.JSONObject(body);
                            org.json.JSONObject wrap = new org.json.JSONObject();
                            wrap.put("ok", true);
                            wrap.put("remote", remote);
                            resultJson = wrap.toString();
                        } else {
                            resultJson = "{\"ok\":false,\"error\":\"Format data versi tidak valid.\"}";
                        }
                    } else {
                        resultJson = "{\"ok\":false,\"statusCode\":" + code + ",\"error\":\"Rilis belum tersedia (HTTP " + code + ").\"}";
                    }
                } catch (Exception e) {
                    try {
                        org.json.JSONObject errObj = new org.json.JSONObject();
                        errObj.put("ok", false);
                        errObj.put("error", e.getMessage() != null ? e.getMessage() : "Koneksi gagal");
                        resultJson = errObj.toString();
                    } catch (Exception ignored) {}
                } finally {
                    if (conn != null) conn.disconnect();
                }
                final String out = resultJson;
                runOnUiThread(() -> {
                    try {
                        if (MainActivity.this.bridge != null && MainActivity.this.bridge.getWebView() != null) {
                            MainActivity.this.bridge.getWebView().evaluateJavascript(
                                "if(window.__nfOnUpdateCheckResult){window.__nfOnUpdateCheckResult(" + org.json.JSONObject.quote(out) + ");}",
                                null
                            );
                        }
                    } catch (Exception ignored) {}
                });
            }).start();
        }

        @JavascriptInterface
        public void downloadAndInstallUpdate(final String apkUrl) {
            if (apkUrl == null || !apkUrl.trim().startsWith("http")) {
                nfEmitUpdateProgress(0, "ERROR", "Alamat unduhan APK tidak valid.");
                return;
            }
            if (!nfUpdateDownloading.compareAndSet(false, true)) {
                return;
            }
            new Thread(() -> {
                java.net.HttpURLConnection conn = null;
                java.io.InputStream in = null;
                java.io.FileOutputStream fos = null;
                try {
                    nfEmitUpdateProgress(2, "DOWNLOADING", "Menghubungkan ke server unduhan...");
                    conn = nfOpenFollowRedirects(apkUrl.trim(), 25000);
                    int code = conn.getResponseCode();
                    if (code < 200 || code >= 300) {
                        throw new Exception("Server menolak unduhan (HTTP " + code + ").");
                    }
                    long total = conn.getContentLengthLong();
                    java.io.File outDir = new java.io.File(getCacheDir(), "nf_updates");
                    if (!outDir.exists()) outDir.mkdirs();
                    java.io.File tmpFile = new java.io.File(outDir, "update_tmp.apk");
                    java.io.File finalFile = new java.io.File(outDir, "update.apk");
                    if (tmpFile.exists()) tmpFile.delete();

                    in = new java.io.BufferedInputStream(conn.getInputStream());
                    fos = new java.io.FileOutputStream(tmpFile);
                    byte[] buf = new byte[16384];
                    long downloaded = 0;
                    int read;
                    int lastPct = 2;
                    while ((read = in.read(buf)) != -1) {
                        fos.write(buf, 0, read);
                        downloaded += read;
                        if (total > 0) {
                            int pct = (int) Math.min(99, (downloaded * 100L) / total);
                            if (pct >= lastPct + 2 || pct == 99) {
                                lastPct = pct;
                                String mbDone = String.format(java.util.Locale.US, "%.1f", downloaded / (1024.0 * 1024.0));
                                String mbTot = String.format(java.util.Locale.US, "%.1f", total / (1024.0 * 1024.0));
                                nfEmitUpdateProgress(pct, "DOWNLOADING", "Mengunduh " + mbDone + " / " + mbTot + " MB (" + pct + "%)");
                            }
                        } else {
                            String mbDone = String.format(java.util.Locale.US, "%.1f", downloaded / (1024.0 * 1024.0));
                            nfEmitUpdateProgress(50, "DOWNLOADING", "Mengunduh " + mbDone + " MB...");
                        }
                    }
                    fos.flush();
                    fos.close();
                    fos = null;
                    in.close();
                    in = null;

                    if (tmpFile.length() < 300000) {
                        tmpFile.delete();
                        throw new Exception("File APK tidak lengkap atau rusak.");
                    }
                    if (finalFile.exists()) finalFile.delete();
                    if (!tmpFile.renameTo(finalFile)) {
                        throw new Exception("Gagal menyiapkan file APK.");
                    }
                    nfEmitUpdateProgress(100, "READY", "Unduhan selesai! Membuka pemasang Android...");
                    runOnUiThread(() -> nfLaunchApkInstaller(finalFile));
                } catch (Exception e) {
                    nfEmitUpdateProgress(0, "ERROR", e.getMessage() != null ? e.getMessage() : "Gagal mengunduh pembaruan.");
                } finally {
                    try { if (fos != null) fos.close(); } catch (Exception ignored) {}
                    try { if (in != null) in.close(); } catch (Exception ignored) {}
                    if (conn != null) conn.disconnect();
                    nfUpdateDownloading.set(false);
                }
            }).start();
        }

        @JavascriptInterface
        public boolean installDownloadedUpdate() {
            final java.io.File finalFile = new java.io.File(new java.io.File(getCacheDir(), "nf_updates"), "update.apk");
            if (!finalFile.exists() || finalFile.length() < 300000) return false;
            runOnUiThread(() -> nfLaunchApkInstaller(finalFile));
            return true;
        }

        @JavascriptInterface
        public boolean isIgnoringBatteryOptimizations() {
            try {
                if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.M) return true;
                android.os.PowerManager pm = (android.os.PowerManager) getSystemService(POWER_SERVICE);
                return pm != null && pm.isIgnoringBatteryOptimizations(getPackageName());
            } catch (Exception e) {
                return false;
            }
        }

        @JavascriptInterface
        public void requestIgnoreBatteryOptimizations() {
            runOnUiThread(() -> {
                try {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                        android.os.PowerManager pm = (android.os.PowerManager) getSystemService(POWER_SERVICE);
                        if (pm != null && pm.isIgnoringBatteryOptimizations(getPackageName())) return;
                        android.content.Intent i = new android.content.Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
                        i.setData(android.net.Uri.parse("package:" + getPackageName()));
                        startActivity(i);
                        return;
                    }
                } catch (Exception ignored) {}
                openAppInfoSettings();
            });
        }

        @JavascriptInterface
        public void openNotificationSettings() {
            runOnUiThread(() -> {
                try {
                    android.content.Intent i = new android.content.Intent();
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        i.setAction(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS);
                        i.putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, getPackageName());
                    } else {
                        i.setAction(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
                        i.setData(android.net.Uri.parse("package:" + getPackageName()));
                    }
                    startActivity(i);
                } catch (Exception e) {
                    openAppInfoSettings();
                }
            });
        }

        @JavascriptInterface
        public void openAppInfoSettings() {
            runOnUiThread(() -> {
                try {
                    android.content.Intent i = new android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
                    i.setData(android.net.Uri.parse("package:" + getPackageName()));
                    startActivity(i);
                } catch (Exception ignored) {}
            });
        }

        @JavascriptInterface
        public boolean isNotificationPermanentlyDenied() {
            try {
                if (android.os.Build.VERSION.SDK_INT < 33) return false;
                boolean granted = androidx.core.content.ContextCompat.checkSelfPermission(MainActivity.this, "android.permission.POST_NOTIFICATIONS") == android.content.pm.PackageManager.PERMISSION_GRANTED;
                if (granted) return false;
                int asked = getSharedPreferences("nf_perm_prefs", MODE_PRIVATE).getInt("notif_asked_count", 0);
                boolean canShowRationale = androidx.core.app.ActivityCompat.shouldShowRequestPermissionRationale(MainActivity.this, "android.permission.POST_NOTIFICATIONS");
                return asked >= 1 && !canShowRationale;
            } catch (Exception e) {
                return false;
            }
        }

        @JavascriptInterface
        public String requestNotificationPermissionSmart() {
            try {
                if (android.os.Build.VERSION.SDK_INT < 33) {
                    boolean enabled = androidx.core.app.NotificationManagerCompat.from(MainActivity.this).areNotificationsEnabled();
                    if (!enabled) {
                        openNotificationSettings();
                        return "OPENED_SETTINGS";
                    }
                    return "GRANTED";
                }
                boolean granted = androidx.core.content.ContextCompat.checkSelfPermission(MainActivity.this, "android.permission.POST_NOTIFICATIONS") == android.content.pm.PackageManager.PERMISSION_GRANTED;
                if (granted) return "GRANTED";
                if (isNotificationPermanentlyDenied()) {
                    openNotificationSettings();
                    return "OPENED_SETTINGS";
                }
                int asked = getSharedPreferences("nf_perm_prefs", MODE_PRIVATE).getInt("notif_asked_count", 0);
                getSharedPreferences("nf_perm_prefs", MODE_PRIVATE).edit().putInt("notif_asked_count", asked + 1).apply();
                runOnUiThread(() -> androidx.core.app.ActivityCompat.requestPermissions(
                    MainActivity.this,
                    new String[]{"android.permission.POST_NOTIFICATIONS"},
                    5399
                ));
                return "REQUESTED";
            } catch (Exception e) {
                openNotificationSettings();
                return "OPENED_SETTINGS";
            }
        }

        @JavascriptInterface
        public String getPermissionStatusJson() {
            try {
                boolean notifOk = android.os.Build.VERSION.SDK_INT < 33
                    ? androidx.core.app.NotificationManagerCompat.from(MainActivity.this).areNotificationsEnabled()
                    : (androidx.core.content.ContextCompat.checkSelfPermission(MainActivity.this, "android.permission.POST_NOTIFICATIONS") == android.content.pm.PackageManager.PERMISSION_GRANTED);
                boolean camOk = androidx.core.content.ContextCompat.checkSelfPermission(MainActivity.this, android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED;
                boolean locOk = androidx.core.content.ContextCompat.checkSelfPermission(MainActivity.this, android.Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    || androidx.core.content.ContextCompat.checkSelfPermission(MainActivity.this, android.Manifest.permission.ACCESS_COARSE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED;
                boolean batOk = isIgnoringBatteryOptimizations();
                boolean notifForever = !notifOk && isNotificationPermanentlyDenied();
                org.json.JSONObject obj = new org.json.JSONObject();
                obj.put("notif", notifOk);
                obj.put("notifDeniedForever", notifForever);
                obj.put("batteryUnrestricted", batOk);
                obj.put("camera", camOk);
                obj.put("location", locOk);
                obj.put("canInstallUpdates", canInstallUnknownApps());
                obj.put("sdkInt", android.os.Build.VERSION.SDK_INT);
                return obj.toString();
            } catch (Exception e) {
                return "{}";
            }
        }
"""


def infer_app_role(pkg_id: str, app_root: Path) -> str:
    low = (pkg_id + " " + app_root.name).lower()
    if "pos" in low:
        return "pos"
    if "staff" in low:
        return "staff"
    if "office" in low:
        return "office"
    return "customer"


def main():
    if len(sys.argv) < 4:
        print("Usage: configure_android_release_and_fcm.py <mobile_subdir> <package_id> <channel_id> [app_role]")
        sys.exit(1)

    app_root = Path(sys.argv[1]).resolve()
    pkg_id = sys.argv[2].strip()
    channel_id = sys.argv[3].strip()
    app_role = sys.argv[4].strip().lower() if len(sys.argv) >= 5 else infer_app_role(pkg_id, app_root)

    android_dir = app_root / "android"
    app_gradle = android_dir / "app" / "build.gradle"
    root_gradle = android_dir / "build.gradle"
    manifest_path = android_dir / "app" / "src" / "main" / "AndroidManifest.xml"
    res_xml_dir = android_dir / "app" / "src" / "main" / "res" / "xml"
    pkg_rel = Path(*pkg_id.split("."))
    java_dir = android_dir / "app" / "src" / "main" / "java" / pkg_rel

    if not app_gradle.exists():
        raise FileNotFoundError(f"Missing {app_gradle}")

    # 1. Auto-increment versionCode & versionName so Android allows direct in-place Update!
    run_num = int(os.environ.get("GITHUB_RUN_NUMBER", "1") or "1")
    ver_code = 100 + run_num
    ver_name = f"1.51.{run_num}"

    gh_repo = (os.environ.get("GITHUB_REPOSITORY") or "nutrifresh-create/nutrifresh-apps").strip()
    update_manifest_url = f"https://github.com/{gh_repo}/releases/download/latest-apks/update-{app_role}.json"

    g_txt = app_gradle.read_text(encoding="utf-8")
    g_txt = re.sub(r"versionCode\s+\d+", f"versionCode {ver_code}", g_txt)
    g_txt = re.sub(r'versionName\s+"[^"]*"', f'versionName "{ver_name}"', g_txt)

    # Write build metadata for GitHub Releases auto-publisher step
    meta_out = {
        "appRole": app_role,
        "packageId": pkg_id,
        "versionCode": ver_code,
        "versionName": ver_name,
        "updateManifestUrl": update_manifest_url,
    }
    (android_dir / ".nf_version.json").write_text(json.dumps(meta_out, indent=2), encoding="utf-8")

    # 2. Persistent Release Keystore Signing (from GitHub Secrets)
    ks_b64 = (os.environ.get("ANDROID_KEYSTORE_BASE64") or "").strip()
    ks_pass = (os.environ.get("ANDROID_KEYSTORE_PASSWORD") or "").strip()
    key_alias = (os.environ.get("ANDROID_KEY_ALIAS") or "nutrifresh_key").strip()
    key_pass = (os.environ.get("ANDROID_KEY_PASSWORD") or ks_pass).strip()
    marker = android_dir / ".nf_release_signed"
    if marker.exists():
        marker.unlink()

    def groovy_sq(val: str) -> str:
        return "'" + str(val).replace("\\", "\\\\").replace("'", "\\'") + "'"

    if ks_b64 and ks_pass:
        ks_file = android_dir / "app" / "nutrifresh-release.jks"
        ks_file.write_bytes(base64.b64decode(ks_b64))
        signing_block = (
            "\n    signingConfigs {\n"
            "        release {\n"
            "            storeFile file('nutrifresh-release.jks')\n"
            f"            storePassword {groovy_sq(ks_pass)}\n"
            f"            keyAlias {groovy_sq(key_alias)}\n"
            f"            keyPassword {groovy_sq(key_pass)}\n"
            "        }\n"
            "    }\n"
            "    buildTypes {"
        )
        if "signingConfigs {" not in g_txt:
            g_txt = re.sub(r"([ \t]*buildTypes\s*\{)", signing_block, g_txt, count=1)
        if "signingConfig signingConfigs.release" not in g_txt:
            bt_match = re.search(r"buildTypes\s*\{", g_txt)
            if bt_match:
                before_bt = g_txt[:bt_match.end()]
                after_bt = g_txt[bt_match.end():]
                after_bt = re.sub(
                    r"(release\s*\{)",
                    r"\1\n            signingConfig signingConfigs.release",
                    after_bt,
                    count=1,
                )
                g_txt = before_bt + after_bt
        marker.write_text("release", encoding="utf-8")
        print(f"[signing] Permanent Release Keystore configured! versionCode={ver_code}, versionName={ver_name}")
    else:
        print(f"[signing] ANDROID_KEYSTORE_BASE64 not set yet -> fallback to debug signing (versionCode={ver_code})")

    # 3. Universal v145+v146+v147 Java Classes (NfUpdateFileProvider, NfLiveOrderHelper, NfDirectReplyReceiver)
    res_xml_dir.mkdir(parents=True, exist_ok=True)
    (res_xml_dir / "nf_update_paths.xml").write_text(UPDATE_PATHS_XML.lstrip("\n"), encoding="utf-8")
    java_dir.mkdir(parents=True, exist_ok=True)
    (java_dir / "NfUpdateFileProvider.java").write_text(
        UPDATE_PROVIDER_JAVA.replace("__PACKAGE_ID__", pkg_id).lstrip("\n"), encoding="utf-8"
    )
    (java_dir / "NfLiveOrderHelper.java").write_text(
        LIVE_ORDER_HELPER_JAVA
        .replace("__PACKAGE_ID__", pkg_id)
        .replace("__CHANNEL_ID__", channel_id)
        .replace("__APP_ROLE__", app_role)
        .lstrip("\n"),
        encoding="utf-8",
    )
    (java_dir / "NfDirectReplyReceiver.java").write_text(
        DIRECT_REPLY_RECEIVER_JAVA.replace("__PACKAGE_ID__", pkg_id).lstrip("\n"),
        encoding="utf-8",
    )

    if manifest_path.exists():
        m_txt = manifest_path.read_text(encoding="utf-8")
        req_perms = [
            '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
            '<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />',
            '<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />',
            '<uses-permission android:name="android.permission.VIBRATE" />',
            '<uses-permission android:name="android.permission.WAKE_LOCK" />',
        ]
        missing_perms = [p for p in req_perms if p.split('"')[1] not in m_txt]
        if missing_perms:
            m_txt = m_txt.replace("<application", "\n    ".join(missing_perms) + "\n    <application", 1)
            added_names = [p.split('"')[1] for p in missing_perms]
            print(f"[perms] Added manifest permissions: {added_names}")

        if "NfUpdateFileProvider" not in m_txt:
            provider_xml = (
                '\n        <provider\n'
                '            android:name=".NfUpdateFileProvider"\n'
                '            android:authorities="${applicationId}.nfupdateprovider"\n'
                '            android:exported="false"\n'
                '            android:grantUriPermissions="true">\n'
                '            <meta-data\n'
                '                android:name="android.support.FILE_PROVIDER_PATHS"\n'
                '                android:resource="@xml/nf_update_paths" />\n'
                '        </provider>\n'
                '    </application>'
            )
            m_txt = m_txt.replace("</application>", provider_xml, 1)
            print("[updater] Registered dedicated NfUpdateFileProvider in AndroidManifest.xml!")

        if "NfDirectReplyReceiver" not in m_txt:
            recv_xml = (
                '\n        <receiver\n'
                '            android:name=".NfDirectReplyReceiver"\n'
                '            android:exported="false" />\n'
                '        <meta-data\n'
                '            android:name="com.google.firebase.messaging.default_notification_channel_id"\n'
                f'            android:value="{channel_id}" />\n'
                '    </application>'
            )
            m_txt = m_txt.replace("</application>", recv_xml, 1)
            print(f"[v147] Registered NfDirectReplyReceiver & default FCM channel '{channel_id}' in AndroidManifest.xml!")

        manifest_path.write_text(m_txt, encoding="utf-8")

    ma_path = java_dir / "MainActivity.java"
    if ma_path.exists():
        ma = ma_path.read_text(encoding="utf-8")
        if "NfLiveOrderHelper.registerLifecycle" not in ma:
            ma = ma.replace(
                "setupNativeBridge();",
                "setupNativeBridge();\n        NfLiveOrderHelper.registerLifecycle(this);",
                1,
            )
        if "NfLiveOrderHelper.handleLaunchIntent" not in ma:
            if "super.onNewIntent(intent);" in ma:
                ma = ma.replace(
                    "super.onNewIntent(intent);",
                    "super.onNewIntent(intent);\n        NfLiveOrderHelper.handleLaunchIntent(this, intent);",
                    1,
                )
        if "downloadAndInstallUpdate" not in ma and "    public class NfAndroidNativeBridge {" in ma:
            fields_block = SMART_PERM_AND_UPDATER_FIELDS.replace("__UPDATE_MANIFEST_URL__", update_manifest_url)
            ma = ma.replace("    public class NfAndroidNativeBridge {", fields_block, 1)
            ma = ma.replace(
                "    public class NfAndroidNativeBridge {",
                "    public class NfAndroidNativeBridge {" + SMART_PERM_AND_UPDATER_METHODS,
                1,
            )
            print(f"[v147] Injected Live Order, Smart Permissions & In-App Self-Updater into {ma_path.name}!")
        ma_path.write_text(ma, encoding="utf-8")

    # 4. Optional Firebase Cloud Messaging (FCM) for real background Push Notifications!
    gs_json = (os.environ.get("FIREBASE_GOOGLE_SERVICES_JSON") or "").strip()
    local_gs = app_root / "google-services.json"
    target_gs = android_dir / "app" / "google-services.json"
    has_fcm = False

    if gs_json:
        if gs_json.startswith("{"):
            target_gs.write_text(gs_json, encoding="utf-8")
        else:
            target_gs.write_bytes(base64.b64decode(gs_json))
        has_fcm = True
    elif local_gs.exists():
        target_gs.write_bytes(local_gs.read_bytes())
        has_fcm = True

    if has_fcm:
        gs_content = target_gs.read_text(encoding="utf-8", errors="ignore")
        if pkg_id not in gs_content:
            print(f"[fcm] WARNING: google-services.json does not contain package '{pkg_id}'. Skipping FCM plugin for this app.")
            target_gs.unlink(missing_ok=True)
            has_fcm = False

    if has_fcm:
        rg_txt = root_gradle.read_text(encoding="utf-8")
        if "com.google.gms:google-services" not in rg_txt:
            rg_txt = re.sub(
                r"(dependencies\s*\{)",
                r'\1\n        classpath "com.google.gms:google-services:4.4.2"',
                rg_txt,
                count=1,
            )
            root_gradle.write_text(rg_txt, encoding="utf-8")

        if "firebase-messaging" not in g_txt:
            g_txt = re.sub(
                r"(dependencies\s*\{)",
                r'\1\n    implementation "com.google.firebase:firebase-messaging:24.0.0"',
                g_txt,
                count=1,
            )
        if "com.google.gms.google-services" not in g_txt:
            g_txt += "\napply plugin: 'com.google.gms.google-services'\n"

        java_dir.mkdir(parents=True, exist_ok=True)
        svc_code = FCM_SERVICE_JAVA.replace("__PACKAGE_ID__", pkg_id).lstrip("\n")
        (java_dir / "NfFirebaseMessagingService.java").write_text(svc_code, encoding="utf-8")

        m_txt = manifest_path.read_text(encoding="utf-8")
        if "NfFirebaseMessagingService" not in m_txt:
            svc_xml = (
                '\n        <service\n'
                '            android:name=".NfFirebaseMessagingService"\n'
                '            android:exported="false">\n'
                '            <intent-filter>\n'
                '                <action android:name="com.google.firebase.MESSAGING_EVENT" />\n'
                '            </intent-filter>\n'
                '        </service>\n'
                '    </application>'
            )
            m_txt = m_txt.replace("</application>", svc_xml, 1)
            manifest_path.write_text(m_txt, encoding="utf-8")

        if ma_path.exists():
            ma = ma_path.read_text(encoding="utf-8")
            if "FirebaseMessaging" not in ma:
                ma = ma.replace(
                    "import com.getcapacitor.BridgeActivity;",
                    "import com.getcapacitor.BridgeActivity;\nimport com.google.firebase.messaging.FirebaseMessaging;",
                    1,
                )
                ma = ma.replace(
                    "setupNativeBridge();",
                    "setupNativeBridge();\n        refreshFcmTokenAsync();",
                    1,
                )
                helper_method = """
    private void refreshFcmTokenAsync() {
        try {
            FirebaseMessaging.getInstance().getToken().addOnCompleteListener(task -> {
                if (task.isSuccessful() && task.getResult() != null) {
                    final String tok = task.getResult();
                    try {
                        getSharedPreferences("nf_push_prefs", MODE_PRIVATE).edit().putString("fcm_token", tok).apply();
                    } catch (Exception ignored) {}
                    runOnUiThread(() -> {
                        if (this.bridge != null && this.bridge.getWebView() != null) {
                            this.bridge.getWebView().evaluateJavascript(
                                "if(window.__nfOnFcmToken){window.__nfOnFcmToken(" + org.json.JSONObject.quote(tok) + ");}",
                                null
                            );
                        }
                    });
                }
            });
        } catch (Exception ignored) {}
    }

    public class NfAndroidNativeBridge {"""
                ma = ma.replace("    public class NfAndroidNativeBridge {", helper_method, 1)
                ma = ma.replace(
                    "    public class NfAndroidNativeBridge {",
                    '    public class NfAndroidNativeBridge {\n'
                    '        @JavascriptInterface\n'
                    '        public String getFcmToken() {\n'
                    '            try {\n'
                    '                return getSharedPreferences("nf_push_prefs", MODE_PRIVATE).getString("fcm_token", "");\n'
                    '            } catch (Exception e) {\n'
                    '                return "";\n'
                    '            }\n'
                    '        }\n',
                    1,
                )
                ma_path.write_text(ma, encoding="utf-8")
        print(f"[fcm] Firebase Cloud Messaging v147 (Zero-Duplicate + Live Order + Direct Reply) enabled for {pkg_id}!")
    else:
        print(f"[fcm] FIREBASE_GOOGLE_SERVICES_JSON not configured yet -> skipped cleanly (build continues).")

    app_gradle.write_text(g_txt, encoding="utf-8")


if __name__ == "__main__":
    main()
