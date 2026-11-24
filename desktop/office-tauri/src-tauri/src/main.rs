#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use base64::Engine;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::time::{Duration, Instant};

#[tauri::command]
fn open_external_url(url: String) -> Result<(), String> {
    webbrowser::open(&url).map_err(|e| format!("Gagal membuka browser: {e}"))
}

#[tauri::command]
async fn start_google_oauth(auth_url: String) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || run_oauth_loopback(auth_url))
        .await
        .map_err(|e| format!("Task OAuth error: {e}"))?
}

fn run_oauth_loopback(auth_url: String) -> Result<String, String> {
    let listener = TcpListener::bind("127.0.0.1:43821")
        .map_err(|e| format!("Port login 43821 sedang dipakai: {e}"))?;
    listener
        .set_nonblocking(true)
        .map_err(|e| format!("Gagal set nonblocking: {e}"))?;

    webbrowser::open(&auth_url)
        .map_err(|e| format!("Gagal membuka browser untuk login Google: {e}"))?;

    let deadline = Instant::now() + Duration::from_secs(180);

    while Instant::now() < deadline {
        match listener.accept() {
            Ok((mut stream, _)) => {
                let _ = stream.set_nonblocking(false);
                let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));

                let mut raw = Vec::new();
                let mut buf = [0u8; 4096];
                let mut header_end: Option<usize> = None;
                let mut content_len: usize = 0;

                loop {
                    match stream.read(&mut buf) {
                        Ok(0) => break,
                        Ok(n) => {
                            raw.extend_from_slice(&buf[..n]);
                            if header_end.is_none() {
                                if let Some(pos) = raw.windows(4).position(|w| w == b"\r\n\r\n") {
                                    header_end = Some(pos + 4);
                                    let hdr_str = String::from_utf8_lossy(&raw[..pos]);
                                    for line in hdr_str.lines() {
                                        if line.to_ascii_lowercase().starts_with("content-length:") {
                                            if let Some(v) = line.split(':').nth(1) {
                                                content_len = v.trim().parse::<usize>().unwrap_or(0);
                                            }
                                        }
                                    }
                                }
                            }
                            if let Some(hend) = header_end {
                                if raw.len() >= hend + content_len {
                                    break;
                                }
                            }
                        }
                        Err(_) => break,
                    }
                }

                let req_text = String::from_utf8_lossy(&raw);
                let first_line = req_text.lines().next().unwrap_or("");

                if first_line.starts_with("POST /auth-complete") {
                    let body = if let Some(hend) = header_end {
                        String::from_utf8_lossy(&raw[hend..raw.len().min(hend + content_len)]).to_string()
                    } else {
                        String::new()
                    };
                    let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK";
                    let _ = stream.write_all(resp.as_bytes());
                    let _ = stream.flush();
                    if !body.trim().is_empty() {
                        return Ok(body);
                    }
                } else if first_line.starts_with("GET /auth-callback") {
                    let html = r#"<!DOCTYPE html>
<html lang="id"><head><meta charset="utf-8"><title>NutriFresh Login Berhasil</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#f4f9f1;color:#0f172a;text-align:center;}
.card{background:#fff;padding:32px 38px;border-radius:22px;box-shadow:0 14px 36px rgba(0,0,0,.1);border:1px solid #bbf7d0;max-width:400px;}
h2{color:#558b2f;margin:0 0 8px;font-size:20px;}p{margin:0;color:#475569;font-size:13.5px;line-height:1.5;}</style></head>
<body><div class="card"><h2 id="st">Menyelesaikan Login Google...</h2><p id="sub">Mohon tunggu sebentar.</p></div>
<script>
(async function(){
  try {
    var payload = (window.location.search || '') + '|||' + (window.location.hash || '');
    await fetch('/auth-complete', { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: payload });
    document.getElementById('st').textContent = 'Login Google Berhasil!';
    document.getElementById('sub').innerHTML = 'Silakan tutup tab ini dan kembali ke aplikasi <strong>NutriFresh</strong>.';
  } catch (e) {
    document.getElementById('st').textContent = 'Gagal mengirim sesi';
    document.getElementById('sub').textContent = String(e);
  }
})();
</script></body></html>"#;
                    let resp = format!(
                        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                        html.len(),
                        html
                    );
                    let _ = stream.write_all(resp.as_bytes());
                    let _ = stream.flush();
                } else {
                    let resp = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                    let _ = stream.write_all(resp.as_bytes());
                }
            }
            Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                std::thread::sleep(Duration::from_millis(80));
            }
            Err(e) => return Err(format!("Loopback accept error: {e}")),
        }
    }

    Err("Waktu login Google habis (3 menit).".to_string())
}

#[cfg(windows)]
mod win_printer {
    use std::ffi::c_void;
    use std::os::windows::process::CommandExt;
    use std::process::Command;

    const CREATE_NO_WINDOW: u32 = 0x08000000;

    #[repr(C)]
    struct DocInfo1W {
        p_doc_name: *const u16,
        p_output_file: *const u16,
        p_datatype: *const u16,
    }

    #[link(name = "winspool")]
    extern "system" {
        fn OpenPrinterW(
            p_printer_name: *const u16,
            ph_printer: *mut *mut c_void,
            p_default: *const c_void,
        ) -> i32;
        fn StartDocPrinterW(
            h_printer: *mut c_void,
            level: u32,
            p_doc_info: *const DocInfo1W,
        ) -> u32;
        fn StartPagePrinter(h_printer: *mut c_void) -> i32;
        fn WritePrinter(
            h_printer: *mut c_void,
            p_buf: *const u8,
            cb_buf: u32,
            pc_written: *mut u32,
        ) -> i32;
        fn EndPagePrinter(h_printer: *mut c_void) -> i32;
        fn EndDocPrinter(h_printer: *mut c_void) -> i32;
        fn ClosePrinter(h_printer: *mut c_void) -> i32;
    }

    fn to_wide(s: &str) -> Vec<u16> {
        s.encode_utf16().chain(std::iter::once(0)).collect()
    }

    pub fn list_printers() -> Result<Vec<String>, String> {
        let out = Command::new("powershell")
            .args([
                "-NoProfile",
                "-Command",
                "Get-Printer | Select-Object -ExpandProperty Name",
            ])
            .creation_flags(CREATE_NO_WINDOW)
            .output()
            .map_err(|e| format!("Gagal membaca daftar printer Windows: {e}"))?;
        let text = String::from_utf8_lossy(&out.stdout);
        let list: Vec<String> = text
            .lines()
            .map(|l| l.trim().to_string())
            .filter(|l| !l.is_empty())
            .collect();
        Ok(list)
    }

    pub fn print_raw(printer_name: &str, data: &[u8]) -> Result<(), String> {
        let name_w = to_wide(printer_name);
        let doc_w = to_wide("NutriFresh POS Print");
        let type_w = to_wide("RAW");

        unsafe {
            let mut handle: *mut c_void = std::ptr::null_mut();
            if OpenPrinterW(name_w.as_ptr(), &mut handle, std::ptr::null()) == 0 {
                return Err(format!("Printer \"{printer_name}\" tidak ditemukan atau sedang offline."));
            }
            let doc_info = DocInfo1W {
                p_doc_name: doc_w.as_ptr(),
                p_output_file: std::ptr::null(),
                p_datatype: type_w.as_ptr(),
            };
            if StartDocPrinterW(handle, 1, &doc_info) == 0 {
                ClosePrinter(handle);
                return Err("Gagal memulai dokumen cetak Windows.".to_string());
            }
            if StartPagePrinter(handle) == 0 {
                EndDocPrinter(handle);
                ClosePrinter(handle);
                return Err("Gagal memulai halaman cetak Windows.".to_string());
            }
            let mut written: u32 = 0;
            let ok = WritePrinter(handle, data.as_ptr(), data.len() as u32, &mut written);
            EndPagePrinter(handle);
            EndDocPrinter(handle);
            ClosePrinter(handle);
            if ok == 0 {
                return Err("Gagal mengirim data cetak RAW ke printer.".to_string());
            }
        }
        Ok(())
    }
}

#[tauri::command]
fn list_windows_printers() -> Result<Vec<String>, String> {
    #[cfg(windows)]
    {
        win_printer::list_printers()
    }
    #[cfg(not(windows))]
    {
        Ok(vec![])
    }
}

#[tauri::command]
fn print_raw_windows(printer_name: String, data_base64: String) -> Result<(), String> {
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(data_base64.trim())
        .map_err(|e| format!("Data cetak base64 tidak valid: {e}"))?;
    #[cfg(windows)]
    {
        win_printer::print_raw(&printer_name, &bytes)
    }
    #[cfg(not(windows))]
    {
        let _ = (printer_name, bytes);
        Err("Direct Print Windows hanya berjalan di sistem Windows.".to_string())
    }
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            open_external_url,
            start_google_oauth,
            list_windows_printers,
            print_raw_windows
        ])
        .run(tauri::generate_context!())
        .expect("Gagal menjalankan aplikasi NutriFresh Desktop");
}
