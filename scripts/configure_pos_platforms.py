import os
import re
import shutil
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent.parent / "apps" / "nutrifresh_pos"
LAUNCHER_DIR = APP_DIR / "assets" / "launcher"

MAIN_ACTIVITY_KOTLIN = """package {package_name}

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.UUID

class MainActivity : FlutterActivity() {{
    private val CHANNEL = "id.my.nutrifresh.pos/bt_printer"
    private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val REQ_BT_PERMS = 4382

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {{ call, result ->
            when (call.method) {{
                "requestPermissions" -> {{
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {{
                        val need = mutableListOf<String>()
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {{
                            need.add(Manifest.permission.BLUETOOTH_CONNECT)
                        }}
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {{
                            need.add(Manifest.permission.BLUETOOTH_SCAN)
                        }}
                        if (need.isNotEmpty()) {{
                            ActivityCompat.requestPermissions(this, need.toTypedArray(), REQ_BT_PERMS)
                        }}
                    }}
                    result.success(true)
                }}
                "getBondedDevices" -> {{
                    try {{
                        val bm = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                        val adapter: BluetoothAdapter? = bm?.adapter
                        if (adapter == null || !adapter.isEnabled) {{
                            result.success(emptyList<Map<String, String>>())
                            return@setMethodCallHandler
                        }}
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
                        ) {{
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN),
                                REQ_BT_PERMS
                            )
                            result.success(emptyList<Map<String, String>>())
                            return@setMethodCallHandler
                        }}
                        val list = adapter.bondedDevices?.map {{ d ->
                            mapOf(
                                "name" to (d.name ?: "Bluetooth Printer"),
                                "address" to (d.address ?: "")
                            )
                        }} ?: emptyList()
                        result.success(list)
                    }} catch (e: Exception) {{
                        result.error("BT_LIST_ERR", e.message, null)
                    }}
                }}
                "printBytes" -> {{
                    val address = call.argument<String>("address")
                    val bytes = call.argument<ByteArray>("bytes")
                    if (address.isNullOrBlank() || bytes == null || bytes.isEmpty()) {{
                        result.error("BT_ARG_ERR", "Alamat printer atau data cetak kosong.", null)
                        return@setMethodCallHandler
                    }}
                    Thread {{
                        try {{
                            val bm = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                            val adapter = bm?.adapter ?: throw Exception("Bluetooth tidak tersedia.")
                            if (!adapter.isEnabled) throw Exception("Bluetooth belum aktif di perangkat.")
                            val device = adapter.getRemoteDevice(address)
                            try {{ adapter.cancelDiscovery() }} catch (_: Exception) {{}}
                            val socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
                            socket.connect()
                            val out: OutputStream = socket.outputStream
                            var offset = 0
                            val chunkSize = 512
                            while (offset < bytes.size) {{
                                val len = minOf(chunkSize, bytes.size - offset)
                                out.write(bytes, offset, len)
                                out.flush()
                                offset += len
                                Thread.sleep(18)
                            }}
                            Thread.sleep(280)
                            out.close()
                            socket.close()
                            runOnUiThread {{ result.success(true) }}
                        }} catch (e: Exception) {{
                            runOnUiThread {{ result.error("BT_PRINT_ERR", e.message ?: "Gagal cetak Bluetooth", null) }}
                        }}
                    }}.start()
                }}
                else -> result.notImplemented()
            }}
        }}
    }}
}}
"""


def configure_android():
    manifest_path = APP_DIR / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest_path.exists():
        print("[configure] AndroidManifest.xml belum ada, skip.")
        return

    txt = manifest_path.read_text(encoding="utf-8")
    txt = re.sub(r'android:label="[^"]*"', 'android:label="NutriFresh POS"', txt, count=1)

    perms = [
        '<uses-permission android:name="android.permission.INTERNET"/>',
        '<uses-permission android:name="android.permission.CAMERA"/>',
        '<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>',
        '<uses-permission android:name="android.permission.BLUETOOTH"/>',
        '<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>',
        '<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>',
        '<uses-permission android:name="android.permission.BLUETOOTH_SCAN"/>',
    ]
    missing = [p for p in perms if p not in txt]
    if missing:
        txt = txt.replace("<application", "\n    ".join(missing) + "\n    <application", 1)

    if 'android:scheme="id.my.nutrifresh.pos"' not in txt:
        oauth_intent = """
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="id.my.nutrifresh.pos" android:host="login-callback" />
            </intent-filter>
        </activity>"""
        txt = txt.replace("</activity>", oauth_intent, 1)

    manifest_path.write_text(txt, encoding="utf-8")
    print("[configure] AndroidManifest.xml OK.")

    # Copy native Android launcher icons (mipmap-mdpi .. mipmap-xxxhdpi)
    src_android_icons = LAUNCHER_DIR / "android"
    dst_res = APP_DIR / "android" / "app" / "src" / "main" / "res"
    if src_android_icons.exists() and dst_res.exists():
        for mipmap_dir in src_android_icons.iterdir():
            if mipmap_dir.is_dir():
                target_dir = dst_res / mipmap_dir.name
                target_dir.mkdir(parents=True, exist_ok=True)
                for png in mipmap_dir.glob("*.png"):
                    shutil.copy2(png, target_dir / png.name)
        print("[configure] Android ic_launcher.png resmi NutriFresh terpasang di semua DPI.")

    # Inject clean Kotlin Bluetooth ESC/POS bridge into MainActivity.kt
    kotlin_root = APP_DIR / "android" / "app" / "src" / "main" / "kotlin"
    if kotlin_root.exists():
        matches = list(kotlin_root.rglob("MainActivity.kt"))
        if matches:
            ma = matches[0]
            old_src = ma.read_text(encoding="utf-8")
            m_pkg = re.search(r'^\s*package\s+([a-zA-Z0-9_.]+)', old_src, re.M)
            pkg = m_pkg.group(1) if m_pkg else "id.my.nutrifresh.nutrifresh_pos"
            ma.write_text(MAIN_ACTIVITY_KOTLIN.format(package_name=pkg), encoding="utf-8")
            print(f"[configure] MainActivity.kt ({pkg}) Bluetooth ESC/POS bridge OK.")


def configure_windows():
    win_dir = APP_DIR / "windows"
    if not win_dir.exists():
        print("[configure] Folder windows belum ada, skip.")
        return

    main_cpp = win_dir / "runner" / "main.cpp"
    if main_cpp.exists():
        txt = main_cpp.read_text(encoding="utf-8")
        txt = txt.replace('L"nutrifresh_pos"', 'L"NutriFresh POS"')
        main_cpp.write_text(txt, encoding="utf-8")
        print("[configure] windows/runner/main.cpp OK.")

    rc_file = win_dir / "runner" / "Runner.rc"
    if rc_file.exists():
        txt = rc_file.read_text(encoding="utf-8", errors="ignore")
        txt = txt.replace('"nutrifresh_pos"', '"NutriFresh POS"')
        rc_file.write_text(txt, encoding="utf-8")
        print("[configure] windows/runner/Runner.rc OK.")

    # Copy native Windows app_icon.ico
    src_ico = LAUNCHER_DIR / "app_icon.ico"
    dst_ico = win_dir / "runner" / "resources" / "app_icon.ico"
    if src_ico.exists() and dst_ico.parent.exists():
        shutil.copy2(src_ico, dst_ico)
        print("[configure] Windows app_icon.ico resmi NutriFresh terpasang OK.")


if __name__ == "__main__":
    configure_android()
    configure_windows()
