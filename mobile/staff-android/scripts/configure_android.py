import os
import re
import shutil
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
ANDROID_DIR = BASE_DIR / "android"
ICONS_SRC = BASE_DIR / "icons"

REMINDER_RECEIVER_JAVA = r"""package id.my.nutrifresh.staff;

import android.app.AlarmManager;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import androidx.core.app.NotificationCompat;
import java.util.Calendar;
import org.json.JSONArray;
import org.json.JSONObject;

public class NfReminderReceiver extends BroadcastReceiver {
    public static final String CH_ID = "nutrifresh_staff_alerts";
    public static final String PREFS = "nf_staff_reminders";
    public static final String ACTION_FIRE = "id.my.nutrifresh.staff.ACTION_REMINDER";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (context == null || intent == null) return;
        String action = intent.getAction();

        if (Intent.ACTION_BOOT_COMPLETED.equals(action) || Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)) {
            rescheduleAllFromPrefs(context);
            return;
        }

        int reqId = intent.getIntExtra("req_id", 1001);
        String title = intent.getStringExtra("title");
        String body = intent.getStringExtra("body");
        boolean daily = intent.getBooleanExtra("daily", false);
        int hour = intent.getIntExtra("hour", -1);
        int minute = intent.getIntExtra("minute", -1);

        showNotification(context, reqId, title != null ? title : "NutriFresh Staff", body != null ? body : "");

        // Jika pengingat harian (Zikir Pagi / Petang), otomatis jadwalkan ulang untuk besok di jam yang sama!
        if (daily && hour >= 0 && minute >= 0) {
            scheduleDailyAlarm(context, reqId, hour, minute, title, body, true);
        }
    }

    public static void showNotification(Context context, int id, String title, String body) {
        try {
            NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null) return;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                NotificationChannel ch = new NotificationChannel(
                    CH_ID,
                    "Pengingat Shift, Dzikir & Antaran",
                    NotificationManager.IMPORTANCE_HIGH
                );
                ch.setDescription("Pengingat keberangkatan shift, zikir pagi/petang, dan antaran kurir NutriFresh");
                ch.enableVibration(true);
                nm.createNotificationChannel(ch);
            }
            Intent launch = new Intent(context, MainActivity.class);
            launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            PendingIntent pi = PendingIntent.getActivity(
                context, id, launch,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            );
            NotificationCompat.Builder b = new NotificationCompat.Builder(context, CH_ID)
                .setSmallIcon(context.getApplicationInfo().icon)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setAutoCancel(true)
                .setContentIntent(pi);
            nm.notify(id, b.build());
        } catch (Exception ignored) {}
    }

    public static void scheduleOneShotAlarm(Context context, int reqId, long triggerAtMillis, String title, String body) {
        try {
            if (triggerAtMillis <= System.currentTimeMillis() + 5000L) return;
            AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
            if (am == null) return;
            Intent i = new Intent(context, NfReminderReceiver.class);
            i.setAction(ACTION_FIRE);
            i.putExtra("req_id", reqId);
            i.putExtra("title", title);
            i.putExtra("body", body);
            i.putExtra("daily", false);
            PendingIntent pi = PendingIntent.getBroadcast(
                context, reqId, i,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            );
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi);
            } else {
                am.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi);
            }
        } catch (Exception ignored) {}
    }

    public static void scheduleDailyAlarm(Context context, int reqId, int hour, int minute, String title, String body, boolean forceNextDay) {
        try {
            AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
            if (am == null) return;
            Calendar cal = Calendar.getInstance();
            cal.set(Calendar.HOUR_OF_DAY, hour);
            cal.set(Calendar.MINUTE, minute);
            cal.set(Calendar.SECOND, 0);
            cal.set(Calendar.MILLISECOND, 0);
            if (forceNextDay || cal.getTimeInMillis() <= System.currentTimeMillis() + 5000L) {
                cal.add(Calendar.DAY_OF_MONTH, 1);
            }
            Intent i = new Intent(context, NfReminderReceiver.class);
            i.setAction(ACTION_FIRE);
            i.putExtra("req_id", reqId);
            i.putExtra("title", title);
            i.putExtra("body", body);
            i.putExtra("daily", true);
            i.putExtra("hour", hour);
            i.putExtra("minute", minute);
            PendingIntent pi = PendingIntent.getBroadcast(
                context, reqId, i,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            );
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.getTimeInMillis(), pi);
            } else {
                am.set(AlarmManager.RTC_WAKEUP, cal.getTimeInMillis(), pi);
            }
        } catch (Exception ignored) {}
    }

    public static void cancelAlarm(Context context, int reqId) {
        try {
            AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
            if (am == null) return;
            Intent i = new Intent(context, NfReminderReceiver.class);
            i.setAction(ACTION_FIRE);
            PendingIntent pi = PendingIntent.getBroadcast(
                context, reqId, i,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            );
            am.cancel(pi);
        } catch (Exception ignored) {}
    }

    public static void saveAndApplyPlan(Context context, String planJson) {
        try {
            SharedPreferences sp = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            // Batalkan alarm shift lama (slot 2000..2030) sebelum menjadwalkan yang baru
            for (int k = 2000; k <= 2030; k++) {
                cancelAlarm(context, k);
            }
            cancelAlarm(context, 1101);
            cancelAlarm(context, 1102);

            sp.edit().putString("plan_json", planJson != null ? planJson : "{}").apply();
            rescheduleAllFromPrefs(context);
        } catch (Exception ignored) {}
    }

    public static void rescheduleAllFromPrefs(Context context) {
        try {
            SharedPreferences sp = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            String raw = sp.getString("plan_json", "");
            if (raw == null || raw.trim().isEmpty()) return;
            JSONObject obj = new JSONObject(raw);

            if (obj.optBoolean("dzikirEnabled", true)) {
                int pagiH = obj.optInt("pagiHour", 6);
                int pagiM = obj.optInt("pagiMin", 0);
                int petangH = obj.optInt("petangHour", 16);
                int petangM = obj.optInt("petangMin", 30);
                scheduleDailyAlarm(
                    context, 1101, pagiH, pagiM,
                    "☀️ Waktunya Dzikir Pagi",
                    "Awali hari penuh berkah. Jangan lupa baca Dzikir Pagi & ceklis di Absensi NutriFresh Staff.",
                    false
                );
                scheduleDailyAlarm(
                    context, 1102, petangH, petangM,
                    "🌆 Waktunya Dzikir Petang",
                    "Luangkan sejenak untuk membaca Dzikir Petang & ceklis di Absensi NutriFresh Staff.",
                    false
                );
            }

            JSONArray shifts = obj.optJSONArray("shifts");
            if (shifts != null) {
                int max = Math.min(shifts.length(), 30);
                for (int i = 0; i < max; i++) {
                    JSONObject s = shifts.optJSONObject(i);
                    if (s == null) continue;
                    long ts = s.optLong("triggerAt", 0L);
                    String title = s.optString("title", "⏰ Persiapan Berangkat Shift");
                    String body = s.optString("body", "Jadwal shift Anda sebentar lagi dimulai.");
                    scheduleOneShotAlarm(context, 2000 + i, ts, title, body);
                }
            }
        } catch (Exception ignored) {}
    }
}
"""

MAIN_ACTIVITY_JAVA = r"""package id.my.nutrifresh.staff;

import android.Manifest;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.webkit.GeolocationPermissions;
import android.webkit.JavascriptInterface;
import android.webkit.PermissionRequest;
import android.webkit.WebView;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import com.getcapacitor.BridgeActivity;
import com.getcapacitor.BridgeWebChromeClient;
import java.util.ArrayList;
import java.util.List;
import org.json.JSONObject;

public class MainActivity extends BridgeActivity {
    private static final int REQ_CAM_PERM = 5381;
    private static final int REQ_GEO_PERM = 5382;
    private static final int REQ_NOTIF_PERM = 5383;
    private String pendingOAuthUrl = null;
    private PermissionRequest pendingWebPermReq = null;
    private GeolocationPermissions.Callback pendingGeoCallback = null;
    private String pendingGeoOrigin = null;
    private int notifCounter = 300;

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        createNotificationChannel();
        captureOAuthIntent(getIntent());
        setupNativeBridge();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        captureOAuthIntent(intent);
        deliverPendingOAuth();
    }

    @Override
    public void onBackPressed() {
        if (this.bridge != null && this.bridge.getWebView() != null) {
            final WebView wv = this.bridge.getWebView();
            String cur = wv.getUrl();
            if (cur != null && cur.contains("localhost") && !cur.endsWith("/") && !cur.contains("index.html") && !cur.contains("staff.html")) {
                wv.loadUrl("https://localhost/index.html");
                return;
            }
            wv.evaluateJavascript(
                "(function(){return window.__nfHandleHardwareBack ? window.__nfHandleHardwareBack() : 'EXIT';})();",
                val -> {
                    String clean = val != null ? val.replace("\"", "").trim() : "EXIT";
                    if ("EXIT".equals(clean)) {
                        runOnUiThread(() -> MainActivity.super.onBackPressed());
                    }
                }
            );
            return;
        }
        super.onBackPressed();
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel ch = new NotificationChannel(
                NfReminderReceiver.CH_ID,
                "Pengingat Shift, Dzikir & Antaran",
                NotificationManager.IMPORTANCE_HIGH
            );
            ch.setDescription("Pengingat jadwal shift, zikir pagi/petang, dan antaran kurir NutriFresh");
            ch.enableVibration(true);
            NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
            if (nm != null) nm.createNotificationChannel(ch);
        }
    }

    private void captureOAuthIntent(Intent intent) {
        if (intent == null) return;
        Uri data = intent.getData();
        if (data != null && "id.my.nutrifresh.staff".equalsIgnoreCase(data.getScheme())) {
            pendingOAuthUrl = data.toString();
        }
    }

    private void deliverPendingOAuth() {
        if (pendingOAuthUrl == null || this.bridge == null || this.bridge.getWebView() == null) return;
        final String url = pendingOAuthUrl;
        pendingOAuthUrl = null;
        final String js = "if(window.__nfHandleNativeOAuthUrl){window.__nfHandleNativeOAuthUrl(" + JSONObject.quote(url) + ");}";
        runOnUiThread(() -> {
            WebView wv = this.bridge.getWebView();
            if (wv != null) wv.evaluateJavascript(js, null);
        });
    }

    private void setupNativeBridge() {
        if (this.bridge == null || this.bridge.getWebView() == null) return;
        WebView wv = this.bridge.getWebView();
        wv.getSettings().setMediaPlaybackRequiresUserGesture(false);
        wv.getSettings().setGeolocationEnabled(true);
        wv.addJavascriptInterface(new NfAndroidNativeBridge(), "NfAndroidNative");

        wv.setWebChromeClient(new BridgeWebChromeClient(this.bridge) {
            @Override
            public void onPermissionRequest(final PermissionRequest request) {
                runOnUiThread(() -> {
                    if (ContextCompat.checkSelfPermission(MainActivity.this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                        request.grant(request.getResources());
                    } else {
                        pendingWebPermReq = request;
                        ensureCameraPermission();
                    }
                });
            }

            @Override
            public void onGeolocationPermissionsShowPrompt(final String origin, final GeolocationPermissions.Callback callback) {
                runOnUiThread(() -> {
                    if (hasLocationPermissionInternal()) {
                        callback.invoke(origin, true, false);
                    } else {
                        pendingGeoOrigin = origin;
                        pendingGeoCallback = callback;
                        ensureLocationPermissions();
                    }
                });
            }

            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                super.onProgressChanged(view, newProgress);
                if (newProgress == 100 && pendingOAuthUrl != null) {
                    deliverPendingOAuth();
                }
            }
        });
    }

    private boolean hasLocationPermissionInternal() {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
            || ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED;
    }

    private boolean hasNotifPermissionInternal() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true;
        return ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED;
    }

    private void ensureCameraPermission() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, new String[]{Manifest.permission.CAMERA}, REQ_CAM_PERM);
        }
    }

    private void ensureLocationPermissions() {
        List<String> need = new ArrayList<>();
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            need.add(Manifest.permission.ACCESS_FINE_LOCATION);
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            need.add(Manifest.permission.ACCESS_COARSE_LOCATION);
        }
        if (!need.isEmpty()) {
            ActivityCompat.requestPermissions(this, need.toArray(new String[0]), REQ_GEO_PERM);
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQ_CAM_PERM && pendingWebPermReq != null) {
            final PermissionRequest req = pendingWebPermReq;
            pendingWebPermReq = null;
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                runOnUiThread(() -> req.grant(req.getResources()));
            } else {
                runOnUiThread(req::deny);
            }
        }
        if (requestCode == REQ_GEO_PERM && pendingGeoCallback != null) {
            final GeolocationPermissions.Callback cb = pendingGeoCallback;
            final String orig = pendingGeoOrigin;
            pendingGeoCallback = null;
            pendingGeoOrigin = null;
            boolean ok = hasLocationPermissionInternal();
            runOnUiThread(() -> cb.invoke(orig, ok, false));
        }
    }

    public class NfAndroidNativeBridge {
        @JavascriptInterface
        public boolean hasCameraPermission() {
            return ContextCompat.checkSelfPermission(MainActivity.this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED;
        }

        @JavascriptInterface
        public void requestCameraPermission() {
            runOnUiThread(() -> ensureCameraPermission());
        }

        @JavascriptInterface
        public boolean hasLocationPermission() {
            return hasLocationPermissionInternal();
        }

        @JavascriptInterface
        public void requestLocationPermission() {
            runOnUiThread(() -> ensureLocationPermissions());
        }

        @JavascriptInterface
        public boolean hasNotificationPermission() {
            return hasNotifPermissionInternal();
        }

        @JavascriptInterface
        public void requestNotificationPermission() {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !hasNotifPermissionInternal()) {
                runOnUiThread(() -> ActivityCompat.requestPermissions(
                    MainActivity.this,
                    new String[]{Manifest.permission.POST_NOTIFICATIONS},
                    REQ_NOTIF_PERM
                ));
            }
        }

        @JavascriptInterface
        public void showLocalNotification(String title, String body) {
            if (!hasNotifPermissionInternal()) return;
            runOnUiThread(() -> NfReminderReceiver.showNotification(
                MainActivity.this,
                ++notifCounter,
                title != null ? title : "NutriFresh Staff",
                body != null ? body : ""
            ));
        }

        @JavascriptInterface
        public String syncStaffReminderPlan(String planJson) {
            try {
                NfReminderReceiver.saveAndApplyPlan(MainActivity.this, planJson);
                return "OK";
            } catch (Exception e) {
                return "ERR:" + e.getMessage();
            }
        }

        @JavascriptInterface
        public void openExternalAuth(String url) {
            openExternalUrl(url);
        }

        @JavascriptInterface
        public void openExternalUrl(String url) {
            runOnUiThread(() -> {
                try {
                    Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                    i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    startActivity(i);
                } catch (Exception ignored) {}
            });
        }
    }
}
"""

def configure():
    manifest = ANDROID_DIR / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.exists():
        raise FileNotFoundError(f"AndroidManifest.xml tidak ditemukan di {manifest}")

    txt = manifest.read_text(encoding="utf-8")

    perms = [
        '<uses-permission android:name="android.permission.INTERNET" />',
        '<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />',
        '<uses-permission android:name="android.permission.CAMERA" />',
        '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
        '<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />',
        '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
        '<uses-permission android:name="android.permission.VIBRATE" />',
        '<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />',
        '<uses-permission android:name="android.permission.WAKE_LOCK" />',
    ]
    missing = [p for p in perms if p.split('"')[1] not in txt]
    if missing:
        txt = txt.replace("<application", "\n    ".join(missing) + "\n    <application", 1)

    txt = re.sub(r'android:launchMode="[^"]*"', 'android:launchMode="singleTask"', txt)

    if 'android:scheme="id.my.nutrifresh.staff"' not in txt:
        oauth_filter = """
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="id.my.nutrifresh.staff" android:host="login-callback" />
            </intent-filter>
        </activity>"""
        txt = txt.replace("</activity>", oauth_filter, 1)

    if "NfReminderReceiver" not in txt:
        recv_xml = """
        <receiver
            android:name=".NfReminderReceiver"
            android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="id.my.nutrifresh.staff.ACTION_REMINDER" />
            </intent-filter>
        </receiver>
    </application>"""
        txt = txt.replace("</application>", recv_xml, 1)

    manifest.write_text(txt, encoding="utf-8")
    print("[android-staff] AndroidManifest.xml updated OK (Notifications + Alarm Receiver).")

    res_dir = ANDROID_DIR / "app" / "src" / "main" / "res"
    anydpi = res_dir / "mipmap-anydpi-v26"
    if anydpi.exists():
        shutil.rmtree(anydpi)
    for d in ICONS_SRC.iterdir():
        if d.is_dir():
            target = res_dir / d.name
            target.mkdir(parents=True, exist_ok=True)
            for png in d.glob("*.png"):
                shutil.copy2(png, target / png.name)
    print("[android-staff] NutriFresh Staff launcher icons installed across all DPIs.")

    pkg_dir = ANDROID_DIR / "app" / "src" / "main" / "java" / "id" / "my" / "nutrifresh" / "staff"
    pkg_dir.mkdir(parents=True, exist_ok=True)
    (pkg_dir / "NfReminderReceiver.java").write_text(REMINDER_RECEIVER_JAVA.lstrip("\n"), encoding="utf-8")
    (pkg_dir / "MainActivity.java").write_text(MAIN_ACTIVITY_JAVA.lstrip("\n"), encoding="utf-8")
    print(f"[android-staff] MainActivity.java + NfReminderReceiver.java injected OK at {pkg_dir}")

if __name__ == "__main__":
    configure()
