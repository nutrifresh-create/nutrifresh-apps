import base64
import json
import os
import re
import sys
from pathlib import Path

# Universal Android Release Signing + Auto versionCode + Smart Permissions (v145)
# + Native In-App Self-Updater (v146) + Optional Firebase FCM
# Usage: python3 scripts/configure_android_release_and_fcm.py <mobile_subdir> <package_id> <channel_id> [app_role]

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
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setAutoCancel(true)
                .setContentIntent(pi);
            nm.notify((int) (System.currentTimeMillis() & 0x7fffffff), b.build());
        } catch (Exception ignored) {}
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

    private java.net.HttpURLConnection nfOpenFollowRedirects(String rawUrl, int timeoutMs) throws Exception {
        String currentUrl = rawUrl;
        for (int hops = 0; hops < 8; hops++) {
            java.net.HttpURLConnection conn = (java.net.HttpURLConnection) new java.net.URL(currentUrl).openConnection();
            conn.setInstanceFollowRedirects(false);
            conn.setConnectTimeout(timeoutMs);
            conn.setReadTimeout(timeoutMs);
            conn.setRequestProperty("User-Agent", "NutriFresh-Android-Updater/1.46");
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
    ver_name = f"1.46.{run_num}"

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

    # 3. Universal v145+v146 Manifest Permissions + Dedicated NfUpdateFileProvider + Native Bridge
    res_xml_dir.mkdir(parents=True, exist_ok=True)
    (res_xml_dir / "nf_update_paths.xml").write_text(UPDATE_PATHS_XML.lstrip("\n"), encoding="utf-8")
    java_dir.mkdir(parents=True, exist_ok=True)
    (java_dir / "NfUpdateFileProvider.java").write_text(
        UPDATE_PROVIDER_JAVA.replace("__PACKAGE_ID__", pkg_id).lstrip("\n"), encoding="utf-8"
    )

    if manifest_path.exists():
        m_txt = manifest_path.read_text(encoding="utf-8")
        req_perms = [
            '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
            '<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />',
            '<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />',
            '<uses-permission android:name="android.permission.VIBRATE" />',
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

        manifest_path.write_text(m_txt, encoding="utf-8")

    ma_path = java_dir / "MainActivity.java"
    if ma_path.exists():
        ma = ma_path.read_text(encoding="utf-8")
        if "downloadAndInstallUpdate" not in ma and "    public class NfAndroidNativeBridge {" in ma:
            fields_block = SMART_PERM_AND_UPDATER_FIELDS.replace("__UPDATE_MANIFEST_URL__", update_manifest_url)
            ma = ma.replace("    public class NfAndroidNativeBridge {", fields_block, 1)
            ma = ma.replace(
                "    public class NfAndroidNativeBridge {",
                "    public class NfAndroidNativeBridge {" + SMART_PERM_AND_UPDATER_METHODS,
                1,
            )
            ma_path.write_text(ma, encoding="utf-8")
            print(f"[perms+updater] Injected Smart Permissions & In-App Self-Updater into {ma_path.name} ({update_manifest_url})!")

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
