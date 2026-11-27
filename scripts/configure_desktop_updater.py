import json
import os
import re
import sys
from pathlib import Path

# NutriFresh Windows Desktop (.exe) Auto-Updater & Version Stamp Configurator (v152.2)
# Usage: python scripts/configure_desktop_updater.py <tauri_subdir> <app_role> <exe_filename>
# Example: python scripts/configure_desktop_updater.py desktop/pos-tauri pos NutriFresh_POS.exe

RUST_UPDATER_SNIPPET = r"""
// =========================================================================
// NUTRIFRESH WINDOWS DESKTOP AUTO-UPDATER (GITHUB RELEASES, ZERO EXTRA CRATES)
// =========================================================================
#[tauri::command]
async fn check_desktop_update(manifest_url: String) -> Result<String, String> {
    let url = manifest_url.trim().to_string();
    if !(url.starts_with("https://github.com/")
        || url.starts_with("https://api.github.com/")
        || url.starts_with("https://raw.githubusercontent.com/"))
    {
        return Err("URL manifest update tidak valid.".to_string());
    }

    tauri::async_runtime::spawn_blocking(move || {
        let ps_script = concat!(
            "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; ",
            "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; ",
            "$u = $env:NF_UPD_URL; ",
            "$sep = if ($u -match '\\?') { '&' } else { '?' }; ",
            "$r = Invoke-WebRequest -UseBasicParsing -Uri ($u + $sep + 't=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) ",
            "-TimeoutSec 18 -Headers @{'User-Agent'='NutriFresh-Desktop-Updater/1.0'}; ",
            "Write-Output $r.Content"
        );

        let mut cmd = std::process::Command::new("powershell.exe");
        cmd.args([
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-WindowStyle",
            "Hidden",
            "-Command",
            ps_script,
        ]);
        cmd.env("NF_UPD_URL", &url);
        #[cfg(target_os = "windows")]
        {
            use std::os::windows::process::CommandExt;
            cmd.creation_flags(0x08000000); // CREATE_NO_WINDOW
        }

        let out = cmd
            .output()
            .map_err(|e| format!("Gagal menjalankan pemeriksa update: {}", e))?;

        if !out.status.success() {
            let err_txt = String::from_utf8_lossy(&out.stderr).trim().to_string();
            return Err(if err_txt.is_empty() {
                "Belum ada rilis Desktop terbaru di GitHub Releases.".to_string()
            } else {
                err_txt.chars().take(220).collect()
            });
        }

        let body = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if body.is_empty() || !body.starts_with('{') {
            return Err("Format manifest update tidak valid.".to_string());
        }
        Ok(body)
    })
    .await
    .map_err(|e| format!("Task pemeriksa update terhenti: {}", e))?
}

#[tauri::command]
async fn download_and_install_desktop_update(
    exe_url: String,
    app: tauri::AppHandle,
) -> Result<String, String> {
    let url = exe_url.trim().to_string();
    if !(url.starts_with("https://github.com/")
        || url.starts_with("https://objects.githubusercontent.com/")
        || url.starts_with("https://release-assets.githubusercontent.com/"))
    {
        return Err("URL unduhan .exe tidak valid.".to_string());
    }

    let current_exe = std::env::current_exe()
        .map_err(|e| format!("Gagal membaca lokasi aplikasi aktif: {}", e))?;
    let current_pid = std::process::id();
    let exe_name = current_exe
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("NutriFresh.exe")
        .to_string();

    let temp_dir = std::env::temp_dir();
    let staged_exe = temp_dir.join(format!("nf_upd_{}_{}", current_pid, exe_name));
    let staged_str = staged_exe.to_string_lossy().to_string();
    let target_str = current_exe.to_string_lossy().to_string();

    // 1. Unduh file .exe terbaru secara diam-diam di background thread
    let dl_url = url.clone();
    let dl_out = staged_str.clone();
    tauri::async_runtime::spawn_blocking(move || -> Result<(), String> {
        let ps_dl = concat!(
            "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; ",
            "$ProgressPreference = 'SilentlyContinue'; ",
            "Invoke-WebRequest -UseBasicParsing -Uri $env:NF_EXE_URL -OutFile $env:NF_EXE_OUT ",
            "-TimeoutSec 240 -Headers @{'User-Agent'='NutriFresh-Desktop-Updater/1.0'}"
        );
        let mut cmd = std::process::Command::new("powershell.exe");
        cmd.args([
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-WindowStyle",
            "Hidden",
            "-Command",
            ps_dl,
        ]);
        cmd.env("NF_EXE_URL", &dl_url);
        cmd.env("NF_EXE_OUT", &dl_out);
        #[cfg(target_os = "windows")]
        {
            use std::os::windows::process::CommandExt;
            cmd.creation_flags(0x08000000);
        }

        let out = cmd
            .output()
            .map_err(|e| format!("Gagal mengunduh file update: {}", e))?;
        if !out.status.success() {
            let err_txt = String::from_utf8_lossy(&out.stderr).trim().to_string();
            let _ = std::fs::remove_file(&dl_out);
            return Err(if err_txt.is_empty() {
                "Unduhan file .exe gagal. Cek koneksi internet.".to_string()
            } else {
                err_txt.chars().take(220).collect()
            });
        }

        // Validasi file PE Windows ("MZ") & ukuran minimal 500 KB
        let meta = std::fs::metadata(&dl_out)
            .map_err(|_| "File hasil unduhan tidak ditemukan.".to_string())?;
        if meta.len() < 500_000 {
            let _ = std::fs::remove_file(&dl_out);
            return Err("File unduhan tidak lengkap atau rusak.".to_string());
        }
        let mut f = std::fs::File::open(&dl_out)
            .map_err(|_| "Gagal membaca file hasil unduhan.".to_string())?;
        let mut magic = [0u8; 2];
        use std::io::Read;
        f.read_exact(&mut magic)
            .map_err(|_| "Gagal memverifikasi header file .exe.".to_string())?;
        if &magic != b"MZ" {
            let _ = std::fs::remove_file(&dl_out);
            return Err("File yang diunduh bukan aplikasi Windows (.exe) yang valid.".to_string());
        }
        Ok(())
    })
    .await
    .map_err(|e| format!("Proses unduhan terhenti: {}", e))??;

    // 2. Buat skrip PowerShell sementara untuk menimpa .exe lama setelah proses ini keluar lalu membukanya lagi
    let ps_swap_path = temp_dir.join(format!("nf_swap_{}.ps1", current_pid));
    let ps_swap_content = format!(
        concat!(
            "$oldPid = {pid}\n",
            "$src = '{src}'\n",
            "$dst = '{dst}'\n",
            "try {{ Wait-Process -Id $oldPid -Timeout 20 -ErrorAction SilentlyContinue }} catch {{}}\n",
            "Start-Sleep -Milliseconds 700\n",
            "$replaced = $false\n",
            "for ($i = 0; $i -lt 10; $i++) {{\n",
            "  try {{\n",
            "    Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop\n",
            "    $replaced = $true\n",
            "    break\n",
            "  }} catch {{\n",
            "    Start-Sleep -Milliseconds 700\n",
            "  }}\n",
            "}}\n",
            "if ($replaced) {{\n",
            "  Remove-Item -LiteralPath $src -Force -ErrorAction SilentlyContinue\n",
            "  Start-Process -FilePath $dst\n",
            "}} else {{\n",
            "  $desk = Join-Path ([Environment]::GetFolderPath('Desktop')) (Split-Path $dst -Leaf)\n",
            "  try {{\n",
            "    Copy-Item -LiteralPath $src -Destination $desk -Force -ErrorAction Stop\n",
            "    Remove-Item -LiteralPath $src -Force -ErrorAction SilentlyContinue\n",
            "    Start-Process -FilePath $desk\n",
            "  }} catch {{\n",
            "    Start-Process -FilePath $src\n",
            "  }}\n",
            "}}\n",
            "Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue\n"
        ),
        pid = current_pid,
        src = staged_str.replace('\'', "''"),
        dst = target_str.replace('\'', "''")
    );

    std::fs::write(&ps_swap_path, ps_swap_content)
        .map_err(|e| format!("Gagal menyiapkan skrip pemasangan update: {}", e))?;

    let mut swap_cmd = std::process::Command::new("powershell.exe");
    swap_cmd.args([
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-WindowStyle",
        "Hidden",
        "-File",
        &ps_swap_path.to_string_lossy(),
    ]);
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        swap_cmd.creation_flags(0x08000000 | 0x00000008); // CREATE_NO_WINDOW | DETACHED_PROCESS
    }
    swap_cmd
        .spawn()
        .map_err(|e| format!("Gagal menjalankan pemasang otomatis: {}", e))?;

    // 3. Beri jeda 400ms agar UI menampilkan status restart lalu tutup proses lama dengan bersih
    let app_handle = app.clone();
    std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_millis(400));
        app_handle.exit(0);
    });

    Ok("RESTARTING".to_string())
}
"""


def inject_version_script_into_html(html_path: Path, meta_obj: dict):
    if not html_path.exists():
        return
    txt = html_path.read_text(encoding="utf-8")
    payload_json = json.dumps(meta_obj, ensure_ascii=False, separators=(",", ":"))
    tag = f"<script>window.__NF_DESKTOP_VERSION__={payload_json};</script>"

    # Remove old marker if re-run
    txt = re.sub(r"<script>window\.__NF_DESKTOP_VERSION__=.*?</script>\s*", "", txt)
    if "<head>" in txt:
        txt = txt.replace("<head>", "<head>\n    " + tag, 1)
    else:
        txt = tag + "\n" + txt
    html_path.write_text(txt, encoding="utf-8", newline="\n")


def patch_tauri_rust_commands(src_dir: Path):
    candidates = [src_dir / "lib.rs", src_dir / "main.rs"]
    target = None
    for c in candidates:
        if c.exists() and "generate_handler![" in c.read_text(encoding="utf-8"):
            target = c
            break
    if not target:
        raise RuntimeError(f"Could not find tauri::generate_handler![ in {src_dir}")

    rust_txt = target.read_text(encoding="utf-8")
    if "fn check_desktop_update(" not in rust_txt:
        rust_txt = rust_txt.rstrip() + "\n\n" + RUST_UPDATER_SNIPPET.strip() + "\n"

    if "check_desktop_update" not in rust_txt.split("generate_handler![", 1)[1].split("]", 1)[0]:
        rust_txt = re.sub(
            r"(generate_handler!\s*\[)",
            r"\1\n            check_desktop_update,\n            download_and_install_desktop_update,",
            rust_txt,
            count=1,
        )

    target.write_text(rust_txt, encoding="utf-8", newline="\n")
    print(f"[desktop-updater] Patched Rust commands in {target}")


def stamp_tauri_version(src_tauri_dir: Path, ver_name: str):
    conf_path = src_tauri_dir / "tauri.conf.json"
    if conf_path.exists():
        conf = json.loads(conf_path.read_text(encoding="utf-8"))
        conf["version"] = ver_name
        conf_path.write_text(json.dumps(conf, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"[desktop-updater] Stamped tauri.conf.json version -> {ver_name}")

    cargo_path = src_tauri_dir / "Cargo.toml"
    if cargo_path.exists():
        cargo_txt = cargo_path.read_text(encoding="utf-8")
        cargo_txt = re.sub(
            r'(?m)^version\s*=\s*"[^"]+"',
            f'version = "{ver_name}"',
            cargo_txt,
            count=1,
        )
        cargo_path.write_text(cargo_txt, encoding="utf-8", newline="\n")
        print(f"[desktop-updater] Stamped Cargo.toml version -> {ver_name}")


def main():
    if len(sys.argv) < 4:
        print("Usage: python scripts/configure_desktop_updater.py <tauri_subdir> <app_role> <exe_filename> [manifest_out_path]")
        sys.exit(1)

    import datetime

    app_root = Path(sys.argv[1]).resolve()
    app_role = sys.argv[2].strip().lower()
    exe_filename = sys.argv[3].strip()
    manifest_out_arg = sys.argv[4].strip() if len(sys.argv) >= 5 else ""

    run_num = int(os.environ.get("GITHUB_RUN_NUMBER", "1") or "1")
    ver_code = 100 + run_num
    ver_name = f"1.52.{run_num}"
    gh_repo = (os.environ.get("GITHUB_REPOSITORY") or "nutrifresh-create/nutrifresh-apps").strip()
    manifest_url = f"https://github.com/{gh_repo}/releases/download/latest-desktop/update-desktop-{app_role}.json"
    exe_url = f"https://github.com/{gh_repo}/releases/download/latest-desktop/{exe_filename}"

    meta_out = {
        "appRole": app_role,
        "platform": "windows",
        "versionCode": ver_code,
        "versionName": ver_name,
        "exeFileName": exe_filename,
        "updateManifestUrl": manifest_url,
    }

    (app_root / ".nf_desktop_version.json").write_text(
        json.dumps(meta_out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"[desktop-updater] Generated .nf_desktop_version.json: {meta_out}")

    # Also write public GitHub Release manifest JSON directly (avoids PowerShell quoting pitfalls)
    release_manifest = {
        "appRole": app_role,
        "platform": "windows",
        "versionCode": ver_code,
        "versionName": ver_name,
        "exeFileName": exe_filename,
        "exeUrl": exe_url,
        "notes": (os.environ.get("RELEASE_NOTES") or "").strip() or "Pembaruan fitur terbaru NutriFresh Desktop.",
        "force": str(os.environ.get("FORCE_UPDATE", "false")).strip().lower() == "true",
        "publishedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }
    manifest_target = Path(manifest_out_arg) if manifest_out_arg else Path(f"update-desktop-{app_role}.json")
    manifest_target.write_text(
        json.dumps(release_manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"[desktop-updater] Generated {manifest_target}: {release_manifest}")

    # Stamp version into Tauri config & Cargo.toml
    src_tauri_dir = app_root / "src-tauri"
    stamp_tauri_version(src_tauri_dir, ver_name)

    # Inject version metadata into dist HTML files
    dist_dir = app_root / "dist"
    for html_name in ["index.html", "pos.html", "office.html"]:
        inject_version_script_into_html(dist_dir / html_name, meta_out)

    # Patch Rust commands into src-tauri/src/lib.rs or main.rs
    patch_tauri_rust_commands(src_tauri_dir / "src")


if __name__ == "__main__":
    main()
