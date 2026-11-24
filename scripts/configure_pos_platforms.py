import os
import re
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent.parent / "apps" / "nutrifresh_pos"

def configure_android():
    manifest_path = APP_DIR / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest_path.exists():
        print("[configure] AndroidManifest.xml belum ada, skip.")
        return
    txt = manifest_path.read_text(encoding="utf-8")

    # Set nama aplikasi menjadi "NutriFresh POS"
    txt = re.sub(r'android:label="[^"]*"', 'android:label="NutriFresh POS"', txt, count=1)

    # Tambahkan izin INTERNET & Bluetooth/Camera jika belum ada
    perms = [
        '<uses-permission android:name="android.permission.INTERNET"/>',
        '<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>',
        '<uses-permission android:name="android.permission.BLUETOOTH"/>',
        '<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>',
        '<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>',
        '<uses-permission android:name="android.permission.BLUETOOTH_SCAN"/>',
    ]
    missing = [p for p in perms if p not in txt]
    if missing:
        txt = txt.replace("<application", "\n    ".join(missing) + "\n    <application", 1)

    # Tambahkan intent-filter Deep Link OAuth Supabase (id.my.nutrifresh.pos://login-callback)
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
    print("[configure] AndroidManifest.xml diperbarui OK.")

def configure_windows():
    main_cpp = APP_DIR / "windows" / "runner" / "main.cpp"
    if main_cpp.exists():
        txt = main_cpp.read_text(encoding="utf-8")
        txt = txt.replace('L"nutrifresh_pos"', 'L"NutriFresh POS"')
        main_cpp.write_text(txt, encoding="utf-8")
        print("[configure] windows/runner/main.cpp diperbarui OK.")

    rc_file = APP_DIR / "windows" / "runner" / "Runner.rc"
    if rc_file.exists():
        txt = rc_file.read_text(encoding="utf-8", errors="ignore")
        txt = txt.replace('"nutrifresh_pos"', '"NutriFresh POS"')
        rc_file.write_text(txt, encoding="utf-8")
        print("[configure] windows/runner/Runner.rc diperbarui OK.")

if __name__ == "__main__":
    configure_android()
    configure_windows()
