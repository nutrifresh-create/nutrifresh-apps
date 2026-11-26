import base64
import os
import re
import sys
from pathlib import Path

# Universal Android Release Signing + Auto versionCode + Optional Firebase FCM Injector (v144)
# Usage: python3 scripts/configure_android_release_and_fcm.py <mobile_subdir> <package_id> <channel_id>

FCM_SERVICE_JAVA = """package __PACKAGE_ID__;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Intent;
import android.os.Build;
import androidx.core.app.NotificationCompat;
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;
import java.util.Map;

public class NfFirebaseMessagingService extends FirebaseMessagingService {
    private static final String CH_ID = "__CHANNEL_ID__";

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
        showNotification(title, body);
    }

    private void showNotification(String title, String body) {
        try {
            NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
            if (nm == null) return;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                NotificationChannel ch = new NotificationChannel(
                    CH_ID,
                    "Notifikasi NutriFresh",
                    NotificationManager.IMPORTANCE_HIGH
                );
                ch.enableVibration(true);
                nm.createNotificationChannel(ch);
            }
            Intent intent = new Intent(this, MainActivity.class);
            intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            PendingIntent pi = PendingIntent.getActivity(
                this,
                (int) (System.currentTimeMillis() & 0x7fff),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            );
            NotificationCompat.Builder b = new NotificationCompat.Builder(this, CH_ID)
                .setSmallIcon(getApplicationInfo().icon)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setAutoCancel(true)
                .setContentIntent(pi);
            nm.notify((int) (System.currentTimeMillis() & 0x7fffffff), b.build());
        } catch (Exception ignored) {}
    }
}
"""


def main():
    if len(sys.argv) < 4:
        print("Usage: configure_android_release_and_fcm.py <mobile_subdir> <package_id> <channel_id>")
        sys.exit(1)

    app_root = Path(sys.argv[1]).resolve()
    pkg_id = sys.argv[2].strip()
    channel_id = sys.argv[3].strip()
    android_dir = app_root / "android"
    app_gradle = android_dir / "app" / "build.gradle"
    root_gradle = android_dir / "build.gradle"
    manifest_path = android_dir / "app" / "src" / "main" / "AndroidManifest.xml"
    pkg_rel = Path(*pkg_id.split("."))
    java_dir = android_dir / "app" / "src" / "main" / "java" / pkg_rel

    if not app_gradle.exists():
        raise FileNotFoundError(f"Missing {app_gradle}")

    # 1. Auto-increment versionCode & versionName so Android allows direct in-place Update!
    run_num = int(os.environ.get("GITHUB_RUN_NUMBER", "1") or "1")
    ver_code = 100 + run_num
    ver_name = f"1.44.{run_num}"

    g_txt = app_gradle.read_text(encoding="utf-8")
    g_txt = re.sub(r"versionCode\s+\d+", f"versionCode {ver_code}", g_txt)
    g_txt = re.sub(r'versionName\s+"[^"]*"', f'versionName "{ver_name}"', g_txt)

    # 2. Persistent Release Keystore Signing (from GitHub Secrets)
    ks_b64 = (os.environ.get("ANDROID_KEYSTORE_BASE64") or "").strip()
    ks_pass = (os.environ.get("ANDROID_KEYSTORE_PASSWORD") or "").strip()
    key_alias = (os.environ.get("ANDROID_KEY_ALIAS") or "nutrifresh_key").strip()
    key_pass = (os.environ.get("ANDROID_KEY_PASSWORD") or ks_pass).strip()
    marker = android_dir / ".nf_release_signed"
    if marker.exists():
        marker.unlink()

    if ks_b64 and ks_pass:
        ks_file = android_dir / "app" / "nutrifresh-release.jks"
        ks_file.write_bytes(base64.b64decode(ks_b64))
        signing_block = (
            "\n    signingConfigs {\n"
            "        release {\n"
            '            storeFile file("nutrifresh-release.jks")\n'
            f'            storePassword "{ks_pass}"\n'
            f'            keyAlias "{key_alias}"\n'
            f'            keyPassword "{key_pass}"\n'
            "        }\n"
            "    }\n"
            "    buildTypes {"
        )
        if "signingConfigs {" not in g_txt:
            g_txt = g_txt.replace("    buildTypes {", signing_block, 1)
        if "signingConfig signingConfigs.release" not in g_txt:
            g_txt = re.sub(
                r"(release\s*\{)",
                r"\1\n            signingConfig signingConfigs.release",
                g_txt,
                count=1,
            )
        marker.write_text("release", encoding="utf-8")
        print(f"[signing] Permanent Release Keystore configured! versionCode={ver_code}, versionName={ver_name}")
    else:
        print(f"[signing] ANDROID_KEYSTORE_BASE64 not set yet -> fallback to debug signing (versionCode={ver_code})")

    # 3. Optional Firebase Cloud Messaging (FCM) for real background Push Notifications!
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
        svc_code = FCM_SERVICE_JAVA.replace("__PACKAGE_ID__", pkg_id).replace("__CHANNEL_ID__", channel_id).lstrip("\n")
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

        ma_path = java_dir / "MainActivity.java"
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
        print(f"[fcm] Firebase Cloud Messaging enabled for {pkg_id}!")
    else:
        print(f"[fcm] FIREBASE_GOOGLE_SERVICES_JSON not configured yet -> skipped cleanly (build continues).")

    app_gradle.write_text(g_txt, encoding="utf-8")


if __name__ == "__main__":
    main()
