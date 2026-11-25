import os
import re
import shutil
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
ANDROID_DIR = BASE_DIR / "android"
ICONS_SRC = BASE_DIR / "icons"

MAIN_ACTIVITY_JAVA = r"""package id.my.nutrifresh.pos;

import android.Manifest;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import androidx.core.app.NotificationCompat;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothSocket;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.util.Base64;
import android.webkit.JavascriptInterface;
import android.webkit.PermissionRequest;
import android.webkit.WebView;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import com.getcapacitor.BridgeActivity;
import com.getcapacitor.BridgeWebChromeClient;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.json.JSONArray;
import org.json.JSONObject;

public class MainActivity extends BridgeActivity {
    private static final UUID SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB");
    private static final int REQ_BT_PERMS = 4382;
    private static final int REQ_CAM_PERM = 4383;
    private static final int REQ_NOTIF_PERM = 4384;
    private static final String CH_ID = "nutrifresh_pos_alerts";
    private int notifCounter = 200;
    private String pendingOAuthUrl = null;
    private PermissionRequest pendingWebPermReq = null;

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
    public void onResume() {
        super.onResume();
        if (this.bridge != null && this.bridge.getWebView() != null) {
            WebView wv = this.bridge.getWebView();
            String cur = wv.getUrl();
            if (cur != null && cur.contains("localhost") && cur.contains("office.html")) {
                wv.loadUrl("https://localhost/index.html");
            }
        }
    }

    @Override
    public void onBackPressed() {
        if (this.bridge != null && this.bridge.getWebView() != null) {
            final WebView wv = this.bridge.getWebView();
            String cur = wv.getUrl();
            if (cur != null && cur.contains("localhost") && !cur.endsWith("/") && !cur.contains("index.html") && !cur.contains("pos.html")) {
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
            NotificationChannel ch = new NotificationChannel(CH_ID, "Order Masuk NutriFresh POS", NotificationManager.IMPORTANCE_HIGH);
            ch.setDescription("Notifikasi order online baru & bukti transfer pelanggan");
            ch.enableVibration(true);
            NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
            if (nm != null) nm.createNotificationChannel(ch);
        }
    }

    private boolean hasNotifPermissionInternal() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true;
        return ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED;
    }

    private void captureOAuthIntent(Intent intent) {
        if (intent == null) return;
        Uri data = intent.getData();
        if (data != null && "id.my.nutrifresh.pos".equalsIgnoreCase(data.getScheme())) {
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
            public void onProgressChanged(WebView view, int newProgress) {
                super.onProgressChanged(view, newProgress);
                if (newProgress == 100 && pendingOAuthUrl != null) {
                    deliverPendingOAuth();
                }
            }
        });
    }

    private void ensureCameraPermission() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, new String[]{Manifest.permission.CAMERA}, REQ_CAM_PERM);
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
    }

    private void ensureBluetoothPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            List<String> need = new ArrayList<>();
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                need.add(Manifest.permission.BLUETOOTH_CONNECT);
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
                need.add(Manifest.permission.BLUETOOTH_SCAN);
            }
            if (!need.isEmpty()) {
                ActivityCompat.requestPermissions(this, need.toArray(new String[0]), REQ_BT_PERMS);
            }
        }
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
                    PendingIntent pi = PendingIntent.getActivity(MainActivity.this, 0, i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
                    NotificationCompat.Builder b = new NotificationCompat.Builder(MainActivity.this, CH_ID)
                        .setSmallIcon(getApplicationInfo().icon)
                        .setContentTitle(title != null ? title : "NutriFresh POS")
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
        public boolean hasCameraPermission() {
            return ContextCompat.checkSelfPermission(MainActivity.this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED;
        }

        @JavascriptInterface
        public void requestCameraPermission() {
            runOnUiThread(() -> ensureCameraPermission());
        }

        @JavascriptInterface
        public void requestBluetoothPermissions() {
            runOnUiThread(() -> ensureBluetoothPermissions());
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
        public String listBondedPrinters() {
            JSONArray arr = new JSONArray();
            try {
                BluetoothManager bm = (BluetoothManager) getSystemService(Context.BLUETOOTH_SERVICE);
                BluetoothAdapter adapter = bm != null ? bm.getAdapter() : null;
                if (adapter == null || !adapter.isEnabled()) return "[]";
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    ContextCompat.checkSelfPermission(MainActivity.this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                    runOnUiThread(() -> ensureBluetoothPermissions());
                    return "[]";
                }
                Set<BluetoothDevice> bonded = adapter.getBondedDevices();
                if (bonded != null) {
                    for (BluetoothDevice d : bonded) {
                        JSONObject o = new JSONObject();
                        o.put("name", d.getName() != null ? d.getName() : "Bluetooth Printer");
                        o.put("address", d.getAddress() != null ? d.getAddress() : "");
                        arr.put(o);
                    }
                }
            } catch (Exception ignored) {}
            return arr.toString();
        }

        @JavascriptInterface
        public String printBase64(String address, String base64Data) {
            if (address == null || address.trim().isEmpty() || base64Data == null || base64Data.isEmpty()) {
                return "Alamat printer atau data cetak kosong.";
            }
            BluetoothSocket socket = null;
            OutputStream out = null;
            try {
                BluetoothManager bm = (BluetoothManager) getSystemService(Context.BLUETOOTH_SERVICE);
                BluetoothAdapter adapter = bm != null ? bm.getAdapter() : null;
                if (adapter == null || !adapter.isEnabled()) {
                    return "Bluetooth belum aktif di perangkat.";
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    ContextCompat.checkSelfPermission(MainActivity.this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                    runOnUiThread(() -> ensureBluetoothPermissions());
                    return "Izin Bluetooth belum diberikan. Ketuk Izinkan lalu coba cetak lagi.";
                }
                byte[] bytes = Base64.decode(base64Data, Base64.DEFAULT);
                BluetoothDevice device = adapter.getRemoteDevice(address.trim());
                try { adapter.cancelDiscovery(); } catch (Exception ignored) {}
                socket = device.createRfcommSocketToServiceRecord(SPP_UUID);
                socket.connect();
                out = socket.getOutputStream();
                int offset = 0;
                int chunkSize = 512;
                while (offset < bytes.length) {
                    int len = Math.min(chunkSize, bytes.length - offset);
                    out.write(bytes, offset, len);
                    out.flush();
                    offset += len;
                    Thread.sleep(16);
                }
                Thread.sleep(260);
                return "OK";
            } catch (Exception e) {
                return e.getMessage() != null ? e.getMessage() : "Gagal terhubung ke printer Bluetooth.";
            } finally {
                try { if (out != null) out.close(); } catch (Exception ignored) {}
                try { if (socket != null) socket.close(); } catch (Exception ignored) {}
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

    # Add required permissions
    perms = [
        '<uses-permission android:name="android.permission.INTERNET" />',
        '<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />',
        '<uses-permission android:name="android.permission.CAMERA" />','<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />','<uses-permission android:name="android.permission.VIBRATE" />',
        '<uses-permission android:name="android.permission.BLUETOOTH" />',
        '<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />',
        '<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />',
        '<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />',
    ]
    missing = [p for p in perms if p.split('"')[1] not in txt]
    if missing:
        txt = txt.replace("<application", "\n    ".join(missing) + "\n    <application", 1)

    # Ensure singleTask launchMode so OAuth deep link resumes the exact existing POS activity
    txt = re.sub(r'android:launchMode="[^"]*"', 'android:launchMode="singleTask"', txt)

    # Add OAuth Deep Link intent-filter
    if 'android:scheme="id.my.nutrifresh.pos"' not in txt:
        oauth_filter = """
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="id.my.nutrifresh.pos" android:host="login-callback" />
            </intent-filter>
        </activity>"""
        txt = txt.replace("</activity>", oauth_filter, 1)

    manifest.write_text(txt, encoding="utf-8")
    print("[android] AndroidManifest.xml updated OK.")

    # Copy NutriFresh POS icons & remove adaptive XMLs so our badged icon always renders crisply
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
    print("[android] NutriFresh POS launcher icons installed across all DPIs.")

    # Replace MainActivity.java with native Bluetooth + Camera + OAuth bridge
    ma_path = ANDROID_DIR / "app" / "src" / "main" / "java" / "id" / "my" / "nutrifresh" / "pos" / "MainActivity.java"
    ma_path.parent.mkdir(parents=True, exist_ok=True)
    ma_path.write_text(MAIN_ACTIVITY_JAVA.lstrip("\n"), encoding="utf-8")
    print(f"[android] MainActivity.java injected OK at {ma_path}")

if __name__ == "__main__":
    configure()
