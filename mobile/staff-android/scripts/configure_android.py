import os
import re
import shutil
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
ANDROID_DIR = BASE_DIR / "android"
ICONS_SRC = BASE_DIR / "icons"

MAIN_ACTIVITY_JAVA = r"""package id.my.nutrifresh.staff;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
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
    private String pendingOAuthUrl = null;
    private PermissionRequest pendingWebPermReq = null;
    private GeolocationPermissions.Callback pendingGeoCallback = null;
    private String pendingGeoOrigin = null;

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
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

    manifest.write_text(txt, encoding="utf-8")
    print("[android-staff] AndroidManifest.xml updated OK.")

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

    ma_path = ANDROID_DIR / "app" / "src" / "main" / "java" / "id" / "my" / "nutrifresh" / "staff" / "MainActivity.java"
    ma_path.parent.mkdir(parents=True, exist_ok=True)
    ma_path.write_text(MAIN_ACTIVITY_JAVA.lstrip("\n"), encoding="utf-8")
    print(f"[android-staff] MainActivity.java injected OK at {ma_path}")

if __name__ == "__main__":
    configure()
