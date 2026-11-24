(function () {
    "use strict";

    const isTauri = () => !!(window.__TAURI__ && window.__TAURI__.core && window.__TAURI__.core.invoke);
    const isAndroidNative = () => !!(window.NfAndroidNative);
    const nativeAppRole = window.__NF_NATIVE_APP__ || ""; // 'pos' | 'office' | ''

    // Global Deep Link receiver called from Android MainActivity.java
    window.__nfHandleNativeOAuthUrl = function (urlStr) {
        if (typeof window.__nfPendingOAuthResolve === "function") {
            window.__nfPendingOAuthResolve(urlStr);
        }
    };

    if (!isTauri() && !isAndroidNative() && !nativeAppRole) {
        // Normal browser (nutrifresh.my.id / iPhone): do nothing, 100% untouched!
        return;
    }

    const PREF_WIN_PRINTER = "nf_native_win_printer";
    const PREF_BT_PRINTER = "nf_native_bt_printer_json";

    function uint8ToBase64(bytes) {
        let bin = "";
        const chunk = 0x8000;
        for (let i = 0; i < bytes.length; i += chunk) {
            bin += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
        }
        return btoa(bin);
    }

    function openExternalNative(url) {
        if (!url) return;
        if (isTauri()) {
            window.__TAURI__.core.invoke("open_external_url", { url }).catch(() => window.open(url, "_blank"));
            return;
        }
        if (isAndroidNative() && window.NfAndroidNative.openExternalUrl) {
            window.NfAndroidNative.openExternalUrl(url);
            return;
        }
        window.open(url, "_blank");
    }

    // Intercept external links (wa.me, maps, nutrifresh.my.id) so they launch native apps cleanly
    document.addEventListener("click", (ev) => {
        const a = ev.target && ev.target.closest ? ev.target.closest("a[href]") : null;
        if (!a) return;
        const href = (a.getAttribute("href") || "").trim();
        if (!href) return;
        if (/^(https?:\/\/|whatsapp:|tel:|mailto:)/i.test(href)) {
            if (!href.startsWith(window.location.origin)) {
                ev.preventDefault();
                openExternalNative(href);
            }
        } else if (nativeAppRole && (href === "index.html" || href.startsWith("index.html?"))) {
            ev.preventDefault();
            openExternalNative("https://nutrifresh.my.id/" + href.replace(/^index\.html/, ""));
        }
    }, true);

    // Override window.open for WhatsApp / external links inside WebView
    const origOpen = window.open.bind(window);
    window.open = function (url, target, features) {
        const s = String(url || "");
        if (/^(https?:\/\/(wa\.me|api\.whatsapp\.com|maps\.google|goo\.gl|nutrifresh\.my\.id))/i.test(s)) {
            openExternalNative(s);
            return null;
        }
        return origOpen(url, target, features);
    };

    // =========================================================================
    // CLEAN NATIVE PRINTER PICKER MODAL (Windows Spooler & Android Bluetooth)
    // =========================================================================
    function showPrinterPickerModal({ title, subtitle, items, activeKey, onPick, onClear }) {
        document.getElementById("nfNativePrinterModal")?.remove();
        const wrap = document.createElement("div");
        wrap.id = "nfNativePrinterModal";
        wrap.style.cssText = "position:fixed;inset:0;z-index:99999;background:rgba(15,23,42,.58);backdrop-filter:blur(8px);display:flex;align-items:center;justify-content:center;padding:16px;";
        const listHtml = items.length === 0
            ? `<div style="padding:18px;text-align:center;color:#64748b;font-size:13px;font-weight:700;">Belum ada printer terdeteksi.<br><span style="font-weight:500;font-size:11.5px;">Pastikan printer Bluetooth sudah di-pair di Pengaturan Android atau terinstal di Windows.</span></div>`
            : items.map((it, idx) => {
                const isAct = it.key === activeKey;
                return `<button type="button" data-idx="${idx}" style="width:100%;text-align:left;padding:11px 14px;border-radius:14px;border:1.5px solid ${isAct ? '#7CB342' : '#e2e8f0'};background:${isAct ? '#f4f9f1' : '#fff'};margin-bottom:8px;cursor:pointer;display:flex;align-items:center;justify-content:space-between;font-family:inherit;">
                    <div>
                        <div style="font-weight:800;font-size:13px;color:#0f172a;">${escapeHtml(it.name)}</div>
                        ${it.sub ? `<div style="font-size:11px;color:#64748b;font-family:monospace;">${escapeHtml(it.sub)}</div>` : ""}
                    </div>
                    <span style="font-size:11px;font-weight:900;color:${isAct ? '#558B2F' : '#2563EB'};">${isAct ? 'AKTIF ✓' : 'Pilih'}</span>
                </button>`;
            }).join("");

        wrap.innerHTML = `
            <div style="width:100%;max-width:420px;background:#fff;border-radius:24px;overflow:hidden;box-shadow:0 24px 50px rgba(0,0,0,.28);font-family:Inter,system-ui,sans-serif;">
                <div style="background:linear-gradient(135deg,#558B2F,#7CB342);padding:15px 18px;color:#fff;display:flex;align-items:center;justify-content:space-between;">
                    <div>
                        <div style="font-weight:900;font-size:15px;">${escapeHtml(title)}</div>
                        <div style="font-size:11px;opacity:.9;">${escapeHtml(subtitle)}</div>
                    </div>
                    <button type="button" id="nfNPClose" style="background:rgba(255,255,255,.2);border:none;color:#fff;width:30px;height:30px;border-radius:999px;font-weight:900;cursor:pointer;">✕</button>
                </div>
                <div style="padding:14px;max-height:55vh;overflow-y:auto;">${listHtml}</div>
                <div style="padding:10px 14px 14px;display:flex;gap:8px;justify-content:flex-end;border-top:1px solid #f1f5f9;">
                    ${activeKey ? `<button type="button" id="nfNPClear" style="padding:8px 14px;border-radius:999px;border:1px solid #fecaca;background:#fef2f2;color:#dc2626;font-weight:800;font-size:12px;cursor:pointer;">Putuskan</button>` : ""}
                    <button type="button" id="nfNPCancel" style="padding:8px 16px;border-radius:999px;border:1px solid #cbd5e1;background:#fff;color:#334155;font-weight:800;font-size:12px;cursor:pointer;">Tutup</button>
                </div>
            </div>`;
        document.body.appendChild(wrap);
        const close = () => wrap.remove();
        wrap.querySelector("#nfNPClose").onclick = close;
        wrap.querySelector("#nfNPCancel").onclick = close;
        wrap.addEventListener("click", (e) => { if (e.target === wrap) close(); });
        const clearBtn = wrap.querySelector("#nfNPClear");
        if (clearBtn) clearBtn.onclick = () => { close(); onClear && onClear(); };
        wrap.querySelectorAll("button[data-idx]").forEach((btn) => {
            btn.onclick = () => {
                const picked = items[Number(btn.getAttribute("data-idx"))];
                close();
                if (picked && onPick) onPick(picked);
            };
        });
    }

    function escapeHtml(s) {
        return String(s || "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
    }

    // =========================================================================
    // LIVE CAMERA BARCODE / QR SCANNER (html5-qrcode lazy-loaded)
    // =========================================================================
    let __html5QrPromise = null;
    function ensureHtml5QrLoaded() {
        if (window.Html5Qrcode) return Promise.resolve();
        if (__html5QrPromise) return __html5QrPromise;
        __html5QrPromise = new Promise((resolve, reject) => {
            const sc = document.createElement("script");
            sc.src = "https://unpkg.com/html5-qrcode@2.3.8/html5-qrcode.min.js";
            sc.onload = () => resolve();
            sc.onerror = () => reject(new Error("Gagal memuat modul kamera scanner (pastikan koneksi internet aktif)."));
            document.head.appendChild(sc);
        });
        return __html5QrPromise;
    }

    async function openCameraScannerOverlay({ title, onScanned }) {
        try {
            if (isAndroidNative() && window.NfAndroidNative.requestCameraPermission) {
                window.NfAndroidNative.requestCameraPermission();
            }
            await ensureHtml5QrLoaded();
        } catch (err) {
            alert(err?.message || "Kamera scanner tidak tersedia.");
            return;
        }

        document.getElementById("nfCamScanOverlay")?.remove();
        const overlay = document.createElement("div");
        overlay.id = "nfCamScanOverlay";
        overlay.style.cssText = "position:fixed;inset:0;z-index:100000;background:rgba(0,0,0,.92);display:flex;flex-direction:column;align-items:center;justify-content:center;padding:16px;font-family:Inter,system-ui,sans-serif;";
        overlay.innerHTML = `
            <div style="width:100%;max-width:420px;background:#0f172a;border:1px solid rgba(255,255,255,.18);border-radius:24px;overflow:hidden;box-shadow:0 24px 60px rgba(0,0,0,.55);">
                <div style="padding:13px 16px;display:flex;align-items:center;justify-content:space-between;background:linear-gradient(135deg,#1d4ed8,#2563eb);color:#fff;">
                    <div style="font-weight:900;font-size:14px;">📷 ${escapeHtml(title || "Scan Barcode / QR")}</div>
                    <button type="button" id="nfCamClose" style="background:rgba(255,255,255,.22);border:none;color:#fff;width:30px;height:30px;border-radius:999px;font-weight:900;cursor:pointer;">✕</button>
                </div>
                <div id="nfCamReader" style="width:100%;min-height:290px;background:#000;"></div>
                <div style="padding:12px 14px;color:#cbd5e1;font-size:12px;text-align:center;">
                    Arahkan kamera ke stiker barcode PLU produk atau kartu QR Member
                </div>
            </div>`;
        document.body.appendChild(overlay);

        const qr = new window.Html5Qrcode("nfCamReader");
        let closed = false;
        const stopAndClose = async () => {
            if (closed) return;
            closed = true;
            try { await qr.stop(); } catch (_) {}
            try { qr.clear(); } catch (_) {}
            overlay.remove();
        };

        overlay.querySelector("#nfCamClose").onclick = stopAndClose;
        try {
            await qr.start(
                { facingMode: "environment" },
                { fps: 12, qrbox: { width: 250, height: 150 }, aspectRatio: 1.33 },
                async (decodedText) => {
                    const clean = String(decodedText || "").trim();
                    if (!clean || closed) return;
                    await stopAndClose();
                    if (typeof onScanned === "function") onScanned(clean);
                },
                () => {}
            );
        } catch (err) {
            await stopAndClose();
            alert("Gagal membuka kamera: " + (err?.message || "Izinkan akses kamera pada perangkat."));
        }
    }

    window.__nfOpenCameraScanner = openCameraScannerOverlay;

    // =========================================================================
    // HOOK INTO POS APP (pos.html) ONCE window.app IS READY
    // =========================================================================
    function patchPosApp() {
        if (nativeAppRole !== "pos") return;
        const app = window.app;
        if (!app || !app.state || app.__nfNativePatched) return;
        app.__nfNativePatched = true;

        // 1. Sembunyikan menu Absensi (khusus aplikasi Staff) & link pindah ke Office (terpisah)
        const styleEl = document.createElement("style");
        styleEl.textContent = `
            #tab-absensi, #content-absensi { display: none !important; }
            a[href="office.html"] { display: none !important; }
        `;
        document.head.appendChild(styleEl);

        if (typeof app.getAllowedTabsForCurrentStaff === "function") {
            const origAllowed = app.getAllowedTabsForCurrentStaff.bind(app);
            app.getAllowedTabsForCurrentStaff = function () {
                const list = origAllowed() || [];
                const filtered = list.filter((t) => t !== "absensi");
                return filtered.length ? filtered : ["kasir"];
            };
        }

        // Pastikan tab awal tidak pernah nyangkut di absensi
        if (app.state.currentAdminTab === "absensi") {
            app.state.currentAdminTab = "kasir";
            try { app.switchAdminTab("kasir"); } catch (_) {}
        }

        // 2. Patch Direct Printer -> Android Native Bluetooth SPP & Windows Native Spooler RAW
        const origSendBytes = app.sendBytesToDirectPrinter ? app.sendBytesToDirectPrinter.bind(app) : null;
        const origDisconnect = app.disconnectDirectPrinter ? app.disconnectDirectPrinter.bind(app) : null;

        app.sendBytesToDirectPrinter = async function (bytes) {
            const dp = this.state.directPrinter;
            if (!dp || !dp.type) return false;
            const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);

            if (dp.type === "android_bt" && isAndroidNative()) {
                try {
                    const b64 = uint8ToBase64(u8);
                    const res = window.NfAndroidNative.printBase64(dp.btAddress, b64);
                    if (res === "OK") return true;
                    throw new Error(res || "Gagal kirim data ke printer Bluetooth.");
                } catch (e) {
                    this.showAlert("Gagal cetak Bluetooth: " + (e?.message || e));
                    return false;
                }
            }

            if (dp.type === "windows_raw" && isTauri()) {
                try {
                    const b64 = uint8ToBase64(u8);
                    await window.__TAURI__.core.invoke("print_raw_windows", {
                        printerName: dp.name,
                        dataBase64: b64
                    });
                    return true;
                } catch (e) {
                    this.showAlert("Gagal cetak ke printer Windows: " + (e?.message || e));
                    return false;
                }
            }

            return origSendBytes ? origSendBytes(bytes) : false;
        };

        app.disconnectDirectPrinter = async function () {
            localStorage.removeItem(PREF_WIN_PRINTER);
            localStorage.removeItem(PREF_BT_PRINTER);
            if (origDisconnect) return origDisconnect();
        };

        if (isAndroidNative()) {
            app.connectBluetoothPrinter = async function () {
                try {
                    if (window.NfAndroidNative.requestBluetoothPermissions) {
                        window.NfAndroidNative.requestBluetoothPermissions();
                    }
                    const jsonStr = window.NfAndroidNative.listBondedPrinters();
                    const list = JSON.parse(jsonStr || "[]");
                    const items = list.map((d) => ({ key: d.address, name: d.name || "Thermal Printer", sub: d.address }));
                    showPrinterPickerModal({
                        title: "Pilih Printer Bluetooth",
                        subtitle: "Cetak langsung ESC/POS & TSPL tanpa pop-up",
                        items,
                        activeKey: this.state.directPrinter?.btAddress || "",
                        onPick: (picked) => {
                            const saved = { name: picked.name, address: picked.key };
                            localStorage.setItem(PREF_BT_PRINTER, JSON.stringify(saved));
                            this.state.directPrinter = {
                                type: "android_bt",
                                name: picked.name,
                                btAddress: picked.key,
                                btDevice: null, btChar: null, serialPort: null, usbDevice: null, usbEndpoint: null, usbInterface: null
                            };
                            this.updateDirectPrinterStatusUI();
                            this.showAlert(`Printer Bluetooth "${picked.name}" tersambung!\nStruk, label barcode, dan stiker PO langsung tercetak tanpa pop-up.`);
                        },
                        onClear: () => this.disconnectDirectPrinter()
                    });
                } catch (e) {
                    this.showAlert("Gagal membaca daftar Bluetooth: " + (e?.message || e));
                }
            };

            // Auto-restore last selected Android Bluetooth printer
            try {
                const savedBt = JSON.parse(localStorage.getItem(PREF_BT_PRINTER) || "null");
                if (savedBt && savedBt.address) {
                    app.state.directPrinter = {
                        type: "android_bt",
                        name: savedBt.name || "Bluetooth Printer",
                        btAddress: savedBt.address,
                        btDevice: null, btChar: null, serialPort: null, usbDevice: null, usbEndpoint: null, usbInterface: null
                    };
                    app.updateDirectPrinterStatusUI();
                }
            } catch (_) {}
        }

        if (isTauri()) {
            const pickWindowsPrinter = async function () {
                try {
                    const list = await window.__TAURI__.core.invoke("list_windows_printers");
                    const items = (list || []).map((name) => ({ key: name, name, sub: "Windows Print Spooler (RAW USB / BT)" }));
                    showPrinterPickerModal({
                        title: "Pilih Printer Windows (Direct Print)",
                        subtitle: "Cetak langsung ESC/POS & TSPL tanpa dialog print",
                        items,
                        activeKey: this.state.directPrinter?.name || "",
                        onPick: (picked) => {
                            localStorage.setItem(PREF_WIN_PRINTER, picked.name);
                            this.state.directPrinter = {
                                type: "windows_raw",
                                name: picked.name,
                                btDevice: null, btChar: null, serialPort: null, usbDevice: null, usbEndpoint: null, usbInterface: null
                            };
                            this.updateDirectPrinterStatusUI();
                            this.showAlert(`Printer Windows "${picked.name}" aktif!\nStruk & stiker kini langsung tercetak tanpa pop-up.`);
                        },
                        onClear: () => this.disconnectDirectPrinter()
                    });
                } catch (e) {
                    this.showAlert("Gagal memuat daftar printer Windows: " + (e?.message || e));
                }
            };
            app.connectUsbPrinter = pickWindowsPrinter;
            app.connectBluetoothPrinter = pickWindowsPrinter;

            // Auto-restore last selected Windows printer
            const savedWin = (localStorage.getItem(PREF_WIN_PRINTER) || "").trim();
            if (savedWin) {
                app.state.directPrinter = {
                    type: "windows_raw",
                    name: savedWin,
                    btDevice: null, btChar: null, serialPort: null, usbDevice: null, usbEndpoint: null, usbInterface: null
                };
                app.updateDirectPrinterStatusUI();
            }
        }

        // 3. Inject Kamera Scan Buttons (Kasir PLU/QR, Member QR, Stok Search, Edit Produk Barcode)
        injectCameraScanButton("posSearch", "Scan Barcode PLU / QR Member", (code) => {
            const inp = document.getElementById("posSearch");
            if (!inp) return;
            inp.value = code;
            app.handleBarcodeScan({ key: "Enter", target: inp });
        });
        injectCameraScanButton("posCustomerPhone", "Scan Kartu QR Member", (code) => {
            const inp = document.getElementById("posCustomerPhone");
            if (!inp) return;
            inp.value = code;
            if (typeof app.lookupPosMemberDirect === "function") app.lookupPosMemberDirect(code);
        });
        injectCameraScanButton("invSearchInput", "Scan Barcode Stok", (code) => {
            const inp = document.getElementById("invSearchInput");
            if (!inp) return;
            inp.value = code;
            if (typeof app.filterInventory === "function") app.filterInventory();
        });
        injectCameraScanButton("editBarcode", "Scan Barcode Kemasan Produk", (code) => {
            const inp = document.getElementById("editBarcode");
            if (inp) inp.value = code;
        });
    }

    function injectCameraScanButton(inputId, title, onScanned) {
        const inp = document.getElementById(inputId);
        if (!inp || !inp.parentElement || inp.parentElement.querySelector(`[data-nf-scan="${inputId}"]`)) return;
        const parent = inp.parentElement;
        if (getComputedStyle(parent).position === "static") {
            parent.style.position = "relative";
        }
        inp.style.paddingRight = "38px";
        const btn = document.createElement("button");
        btn.type = "button";
        btn.setAttribute("data-nf-scan", inputId);
        btn.title = title;
        btn.style.cssText = "position:absolute;right:5px;top:50%;transform:translateY(-50%);width:28px;height:28px;border-radius:999px;border:none;background:linear-gradient(135deg,#2563eb,#1d4ed8);color:#fff;display:flex;align-items:center;justify-content:center;cursor:pointer;z-index:5;box-shadow:0 2px 6px rgba(37,99,235,.35);";
        btn.innerHTML = `<i class="fa-solid fa-camera" style="font-size:12px;"></i>`;
        btn.addEventListener("click", (e) => {
            e.preventDefault();
            e.stopPropagation();
            openCameraScannerOverlay({ title, onScanned });
        });
        parent.appendChild(btn);
    }

    // Poll cleanly until pos.html finishes initializing window.app.state
    if (nativeAppRole === "pos") {
        let tries = 0;
        const t = setInterval(() => {
            tries++;
            if (window.app && window.app.state) {
                patchPosApp();
                clearInterval(t);
            } else if (tries > 120) {
                clearInterval(t);
            }
        }, 120);
    }
})();
