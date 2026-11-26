import os
import re
import shutil
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
ANDROID_DIR = BASE_DIR / "android"
ICONS_SRC = BASE_DIR / "icons"

MAIN_ACTIVITY_JAVA = r"""package id.my.nutrifresh.app;

import android.Manifest;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.ContentValues;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;
import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;
import androidx.core.app.ActivityCompat;
import androidx.core.app.NotificationCompat;
import androidx.core.content.ContextCompat;
import com.getcapacitor.BridgeActivity;
import com.getcapacitor.BridgeWebChromeClient;
import org.json.JSONObject;

public class MainActivity extends BridgeActivity {
    private static final int REQ_NOTIF_PERM = 6381;
    private static final String CH_ID = "nutrifresh_alerts";
    private String pendingOAuthUrl = null;
    private int notifCounter = 100;

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
                CH_ID,
                "Status Pesanan NutriFresh",
                NotificationManager.IMPORTANCE_HIGH
            );
            ch.setDescription("Notifikasi update timbangan, pembayaran & pengantaran pesanan NutriFresh");
            ch.enableVibration(true);
            NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
            if (nm != null) nm.createNotificationChannel(ch);
        }
    }

    private void captureOAuthIntent(Intent intent) {
        if (intent == null) return;
        Uri data = intent.getData();
        if (data != null && "id.my.nutrifresh.app".equalsIgnoreCase(data.getScheme())) {
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
        wv.addJavascriptInterface(new NfAndroidNativeBridge(), "NfAndroidNative");

        wv.setWebChromeClient(new BridgeWebChromeClient(this.bridge) {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                super.onProgressChanged(view, newProgress);
                if (newProgress == 100 && pendingOAuthUrl != null) {
                    deliverPendingOAuth();
                }
            }
        });
    }

    private boolean hasNotifPermissionInternal() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true;
        return ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED;
    }

    public class NfAndroidNativeBridge {
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
            runOnUiThread(() -> {
                try {
                    Intent i = new Intent(MainActivity.this, MainActivity.class);
                    i.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
                    PendingIntent pi = PendingIntent.getActivity(
                        MainActivity.this, 0, i,
                        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
                    );
                    NotificationCompat.Builder b = new NotificationCompat.Builder(MainActivity.this, CH_ID)
                        .setSmallIcon(getApplicationInfo().icon)
                        .setContentTitle(title != null ? title : "NutriFresh")
                        .setContentText(body != null ? body : "")
                        .setStyle(new NotificationCompat.BigTextStyle().bigText(body != null ? body : ""))
                        .setPriority(NotificationCompat.PRIORITY_HIGH)
                        .setAutoCancel(true)
                        .setContentIntent(pi);
                    NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
                    if (nm != null) nm.notify(++notifCounter, b.build());
                } catch (Exception ignored) {}
            });
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

        @JavascriptInterface
        public String savePngBase64(String fileName, String base64Data) {
            try {
                String cleanName = (fileName != null && !fileName.trim().isEmpty())
                    ? fileName.trim().replaceAll("[^a-zA-Z0-9._-]", "_")
                    : ("Resi_NutriFresh_" + System.currentTimeMillis() + ".png");
                if (!cleanName.toLowerCase().endsWith(".png")) cleanName += ".png";
                String cleanB64 = base64Data != null ? base64Data : "";
                int commaIdx = cleanB64.indexOf(',');
                if (commaIdx >= 0) cleanB64 = cleanB64.substring(commaIdx + 1);
                byte[] bytes = Base64.decode(cleanB64, Base64.DEFAULT);

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    ContentValues cv = new ContentValues();
                    cv.put(MediaStore.Images.Media.DISPLAY_NAME, cleanName);
                    cv.put(MediaStore.Images.Media.MIME_TYPE, "image/png");
                    cv.put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/NutriFresh");
                    Uri uri = getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, cv);
                    if (uri == null) return "ERR:Gagal membuat file di Galeri.";
                    try (OutputStream os = getContentResolver().openOutputStream(uri)) {
                        if (os == null) return "ERR:Gagal membuka stream Galeri.";
                        os.write(bytes);
                        os.flush();
                    }
                    return "OK:Galeri (Pictures/NutriFresh/" + cleanName + ")";
                } else {
                    File dir = new File(getExternalFilesDir(Environment.DIRECTORY_PICTURES), "NutriFresh");
                    if (!dir.exists()) dir.mkdirs();
                    File outFile = new File(dir, cleanName);
                    try (FileOutputStream fos = new FileOutputStream(outFile)) {
                        fos.write(bytes);
                        fos.flush();
                    }
                    return "OK:" + outFile.getAbsolutePath();
                }
            } catch (Exception e) {
                return "ERR:" + (e.getMessage() != null ? e.getMessage() : "Gagal menyimpan PNG.");
            }
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
        '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
        '<uses-permission android:name="android.permission.VIBRATE" />',
    ]
    missing = [p for p in perms if p.split('"')[1] not in txt]
    if missing:
        txt = txt.replace("<application", "\n    ".join(missing) + "\n    <application", 1)

    txt = re.sub(r'android:launchMode="[^"]*"', 'android:launchMode="singleTask"', txt)

    if 'android:scheme="id.my.nutrifresh.app"' not in txt:
        oauth_filter = """
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="id.my.nutrifresh.app" android:host="login-callback" />
            </intent-filter>
        </activity>"""
        txt = txt.replace("</activity>", oauth_filter, 1)

    manifest.write_text(txt, encoding="utf-8")
    print("[android-customer] AndroidManifest.xml updated OK.")

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
    print("[android-customer] NutriFresh Customer launcher icons installed across all DPIs.")

    ma_path = ANDROID_DIR / "app" / "src" / "main" / "java" / "id" / "my" / "nutrifresh" / "app" / "MainActivity.java"
    ma_path.parent.mkdir(parents=True, exist_ok=True)
    ma_path.write_text(MAIN_ACTIVITY_JAVA.lstrip("\n"), encoding="utf-8")
    print(f"[android-customer] MainActivity.java injected OK at {ma_path}")

if __name__ == "__main__":
    configure()
