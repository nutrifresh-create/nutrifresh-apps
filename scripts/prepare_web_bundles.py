import os
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEB_DIR = ROOT / "web"

SHARED_ASSETS = [
    "supabase-adapter.js",
    "native-bridge.js",
    "logo.png",
    "icon.png",
    "iconP.png",
    "manifest.json",
]

def build_bundle(entry_html: str, app_role: str, out_dir: Path):
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    # Copy shared assets
    for fn in SHARED_ASSETS:
        src = WEB_DIR / fn
        if src.exists():
            shutil.copy2(src, out_dir / fn)

    # Copy entry HTML as index.html and inject native role marker inside <head>
    html = (WEB_DIR / entry_html).read_text(encoding="utf-8")
    marker = f'<script>window.__NF_NATIVE_APP__="{app_role}";window.__NF_ANDROID_SCHEME__="id.my.nutrifresh.{app_role}";</script>\n'
    if "<head>" in html:
        html = html.replace("<head>", "<head>\n    " + marker, 1)
    else:
        html = marker + html

    (out_dir / "index.html").write_text(html, encoding="utf-8")
    # Also keep original filename alias just in case any internal script references it
    if entry_html != "index.html":
        (out_dir / entry_html).write_text(html, encoding="utf-8")

    print(f"[bundle] Built {out_dir.relative_to(ROOT)} from web/{entry_html} (role={app_role})")

if __name__ == "__main__":
    build_bundle("pos.html", "pos", ROOT / "desktop" / "pos-tauri" / "dist")
    build_bundle("office.html", "office", ROOT / "desktop" / "office-tauri" / "dist")
    build_bundle("pos.html", "pos", ROOT / "mobile" / "pos-android" / "www")
