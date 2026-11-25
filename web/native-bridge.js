(function () {
    "use strict";

    const isTauri = () => !!(window.__TAURI__ && window.__TAURI__.core && window.__TAURI__.core.invoke);
    const isAndroidNative = () => !!(window.NfAndroidNative);
    const nativeAppRole = window.__NF_NATIVE_APP__ || ""; // 'pos' | 'office' | ''
    const isNativeEnv = () => isTauri() || isAndroidNative() || !!nativeAppRole;
    const isPosPage = () => nativeAppRole === "pos" || !!document.getElementById("posSearch");

    // Global Deep Link receiver called from Android MainActivity.java
    window.__nfHandleNativeOAuthUrl = function (urlStr) {
        if (typeof window.__nfPendingOAuthResolve === "function") {
            window.__nfPendingOAuthResolve(urlStr);
        }
    };

    const PREF_WIN_PRINTER = "nf_native_win_printer";
    const PREF_BT_PRINTER = "nf_native_bt_printer_json";

    function escapeHtml(s) {
        return String(s || "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
    }

    function uint8ToBase64(bytes) {
        let bin = "";
        const chunk = 0x8000;
        for (let i = 0; i < bytes.length; i += chunk) {
            bin += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
        }
        return btoa(bin);
    }

    function getReadyApp() {
        const a = window.__nutriReadyApp;
        if (a && typeof a === "object" && a.state && typeof a.state === "object") return a;
        return null;
    }

    // Immediately hide Absensi & Office links in Native POS (higher specificity than pos.html v121 rules!)
    if (nativeAppRole === "pos") {
        const earlyStyle = document.createElement("style");
        earlyStyle.textContent = `
            html body #adminTopHeader > div > div:last-child a[href*="office.html"],
            html body a[href*="office.html"],
            html body #adminView > div:first-child nav #tab-absensi,
            html body #adminView #tab-absensi,
            html body #tab-absensi,
            html body #content-absensi {
                display: none !important;
                visibility: hidden !important;
                pointer-events: none !important;
            }
        `;
        (document.head || document.documentElement).appendChild(earlyStyle);

        // Hard block openOfficeWithDarkLoader so POS APK/EXE never navigates to https://localhost/office.html
        window.openOfficeWithDarkLoader = function (ev) {
            if (ev) {
                ev.preventDefault();
                ev.stopPropagation();
            }
            return false;
        };
    }

    // Immediately hide cross-app links in Native Office (.exe / .apk), Staff (.apk) & Customer (.apk)
    if (nativeAppRole === "office") {
        const offStyle = document.createElement("style");
        offStyle.textContent = `
            html body > header > div:first-child > div:last-child button[onclick*="goToStore"],
            html body #officeAuthGateModal a[href="index.html"] {
                display: none !important;
            }
        `;
        (document.head || document.documentElement).appendChild(offStyle);
    } else if (nativeAppRole === "staff") {
        const stfStyle = document.createElement("style");
        stfStyle.textContent = `
            html body #staffLoginCrossLinks,
            html body #staffLoginScreen a[href="index.html"],
            html body #staffLoginScreen a[href="pos.html"] {
                display: none !important;
            }
        `;
        (document.head || document.documentElement).appendChild(stfStyle);
    } else if (nativeAppRole === "customer") {
        const custStyle = document.createElement("style");
        custStyle.textContent = `
            html body #staffQuickAccessBanner,
            html body #staffReentryPromptBar,
            html body #footerPortalAccessWrap,
            html body #btnAdminPanelReturn {
                display: none !important;
            }
        `;
        (document.head || document.documentElement).appendChild(custStyle);
    }

    function stripNativeHiddenNodes() {
        if (nativeAppRole === "pos") {
            document.querySelectorAll('#tab-absensi, #content-absensi, a[href*="office.html"]').forEach((el) => {
                el.remove();
            });
            // Trigger resize so iOS26 sliding lens immediately snaps cleanly to Kasir tab
            try { window.dispatchEvent(new Event("resize")); } catch (_) {}
        } else if (nativeAppRole === "office") {
            document.querySelectorAll('button[onclick*="goToStore"], #officeAuthGateModal a[href="index.html"]').forEach((el) => {
                el.remove();
            });
        } else if (nativeAppRole === "staff") {
            document.querySelectorAll('#staffLoginCrossLinks').forEach((el) => {
                el.remove();
            });
        } else if (nativeAppRole === "customer") {
            document.querySelectorAll('#staffQuickAccessBanner, #staffReentryPromptBar, #footerPortalAccessWrap, #btnAdminPanelReturn').forEach((el) => {
                el.remove();
            });
        }
    }

    // =========================================================================
    // EXTERNAL LINKS BRIDGE (NATIVE APK / EXE ONLY)
    // =========================================================================
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

    if (isNativeEnv()) {
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
            } else if (nativeAppRole === "pos" && href.includes("office.html")) {
                ev.preventDefault();
                ev.stopPropagation();
            } else if (nativeAppRole && (href === "index.html" || href.startsWith("index.html?"))) {
                ev.preventDefault();
                openExternalNative("https://nutrifresh.my.id/" + href.replace(/^index\.html/, ""));
            }
        }, true);

        const origOpen = window.open.bind(window);
        window.open = function (url, target, features) {
            const s = String(url || "");
            if (/^(https?:\/\/(wa\.me|api\.whatsapp\.com|maps\.google|goo\.gl|nutrifresh\.my\.id))/i.test(s)) {
                openExternalNative(s);
                return null;
            }
            return origOpen(url, target, features);
        };
    }

    // =========================================================================
    // LIVE CAMERA BARCODE / QR SCANNER (WORKS IN APK, TABLET/HP WEB & PC WEBCAM)
    // =========================================================================
    let __html5QrPromise = null;
    function ensureHtml5QrLoaded() {
        if (window.Html5Qrcode) return Promise.resolve();
        if (__html5QrPromise) return __html5QrPromise;
        __html5QrPromise = new Promise((resolve, reject) => {
            const sc = document.createElement("script");
            sc.src = "https://unpkg.com/html5-qrcode@2.3.8/html5-qrcode.min.js";
            sc.onload = () => resolve();
            sc.onerror = () => {
                __html5QrPromise = null;
                reject(new Error("Gagal memuat modul kamera scanner (pastikan koneksi internet aktif)."));
            };
            document.head.appendChild(sc);
        });
        return __html5QrPromise;
    }

    async function waitForAndroidCameraPermission() {
        if (!isAndroidNative()) return true;
        try {
            if (typeof window.NfAndroidNative.hasCameraPermission === "function") {
                if (window.NfAndroidNative.hasCameraPermission()) return true;
                window.NfAndroidNative.requestCameraPermission();
                const deadline = Date.now() + 12000;
                while (Date.now() < deadline) {
                    await new Promise((r) => setTimeout(r, 250));
                    if (window.NfAndroidNative.hasCameraPermission()) return true;
                }
                return false;
            }
            if (typeof window.NfAndroidNative.requestCameraPermission === "function") {
                window.NfAndroidNative.requestCameraPermission();
                await new Promise((r) => setTimeout(r, 400));
            }
        } catch (_) {}
        return true;
    }

    async function openCameraScannerOverlay({ title, onScanned }) {
        try {
            const permOk = await waitForAndroidCameraPermission();
            if (!permOk) {
                alert("Izin kamera belum diberikan. Buka Pengaturan Android → Aplikasi → NutriFresh POS → Izin → Kamera, lalu izinkan.");
                return;
            }
            await ensureHtml5QrLoaded();
        } catch (err) {
            alert(err?.message || "Kamera scanner tidak tersedia.");
            return;
        }

        document.getElementById("nfCamScanOverlay")?.remove();
        const overlay = document.createElement("div");
        overlay.id = "nfCamScanOverlay";
        overlay.style.cssText = "position:fixed;inset:0;z-index:100000;background:rgba(2,6,23,.92);backdrop-filter:blur(6px);display:flex;flex-direction:column;align-items:center;justify-content:center;padding:16px;font-family:Inter,system-ui,sans-serif;";
        overlay.innerHTML = `
            <div style="width:100%;max-width:440px;background:#0f172a;border:1px solid rgba(255,255,255,.18);border-radius:26px;overflow:hidden;box-shadow:0 24px 60px rgba(0,0,0,.6);">
                <div style="padding:13px 16px;display:flex;align-items:center;justify-content:space-between;gap:8px;background:linear-gradient(135deg,#1d4ed8,#2563eb);color:#fff;">
                    <div style="font-weight:900;font-size:13.5px;display:flex;align-items:center;gap:7px;min-width:0;">
                        <i class="fa-solid fa-camera"></i>
                        <span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${escapeHtml(title || "Scan Barcode / QR")}</span>
                    </div>
                    <div style="display:flex;align-items:center;gap:6px;flex-shrink:0;">
                        <button type="button" id="nfCamTorch" title="Senter / Flash" style="background:rgba(255,255,255,.22);border:none;color:#fff;width:32px;height:32px;border-radius:999px;cursor:pointer;display:none;align-items:center;justify-content:center;"><i class="fa-solid fa-bolt"></i></button>
                        <button type="button" id="nfCamFlip" title="Ganti Kamera Depan/Belakang" style="background:rgba(255,255,255,.22);border:none;color:#fff;width:32px;height:32px;border-radius:999px;cursor:pointer;display:flex;align-items:center;justify-content:center;"><i class="fa-solid fa-camera-rotate"></i></button>
                        <button type="button" id="nfCamClose" title="Tutup" style="background:rgba(255,255,255,.22);border:none;color:#fff;width:32px;height:32px;border-radius:999px;font-weight:900;cursor:pointer;">✕</button>
                    </div>
                </div>
                <div id="nfCamReader" style="width:100%;min-height:300px;background:#000;"></div>
                <div style="padding:12px 16px;color:#cbd5e1;font-size:11.5px;text-align:center;line-height:1.45;">
                    Arahkan kamera ke <strong>stiker barcode PLU / timbangan</strong> atau <strong>QR Kartu Member</strong>
                </div>
            </div>`;
        document.body.appendChild(overlay);

        const formats = window.Html5QrcodeSupportedFormats ? [
            window.Html5QrcodeSupportedFormats.QR_CODE,
            window.Html5QrcodeSupportedFormats.EAN_13,
            window.Html5QrcodeSupportedFormats.EAN_8,
            window.Html5QrcodeSupportedFormats.CODE_128,
            window.Html5QrcodeSupportedFormats.CODE_39,
            window.Html5QrcodeSupportedFormats.UPC_A,
            window.Html5QrcodeSupportedFormats.UPC_E,
            window.Html5QrcodeSupportedFormats.ITF,
            window.Html5QrcodeSupportedFormats.CODABAR
        ] : undefined;

        const qr = new window.Html5Qrcode("nfCamReader", formats ? { formatsToSupport: formats, verbose: false } : false);
        let closed = false;
        let facingMode = "environment";
        let torchOn = false;

        const stopAndClose = async () => {
            if (closed) return;
            closed = true;
            try { await qr.stop(); } catch (_) {}
            try { qr.clear(); } catch (_) {}
            overlay.remove();
        };

        const startStream = async (mode) => {
            const torchBtn = overlay.querySelector("#nfCamTorch");
            if (torchBtn) torchBtn.style.display = "none";
            torchOn = false;
            await qr.start(
                { facingMode: mode },
                { fps: 14, qrbox: { width: 255, height: 155 }, aspectRatio: 1.33 },
                async (decodedText) => {
                    const clean = String(decodedText || "").trim();
                    if (!clean || closed) return;
                    try { if (navigator.vibrate) navigator.vibrate(70); } catch (_) {}
                    await stopAndClose();
                    if (typeof onScanned === "function") onScanned(clean);
                },
                () => {}
            );
            // Tampilkan tombol Senter jika kamera mendukung torch
            try {
                const caps = qr.getRunningTrackCameraCapabilities && qr.getRunningTrackCameraCapabilities();
                if (caps && caps.torchFeature && caps.torchFeature().isSupported() && torchBtn) {
                    torchBtn.style.display = "flex";
                    torchBtn.onclick = async () => {
                        try {
                            torchOn = !torchOn;
                            await caps.torchFeature().apply(torchOn);
                            torchBtn.style.background = torchOn ? "#facc15" : "rgba(255,255,255,.22)";
                            torchBtn.style.color = torchOn ? "#0f172a" : "#fff";
                        } catch (_) {}
                    };
                }
            } catch (_) {}
        };

        overlay.querySelector("#nfCamClose").onclick = stopAndClose;
        overlay.addEventListener("click", (e) => { if (e.target === overlay) stopAndClose(); });

        overlay.querySelector("#nfCamFlip").onclick = async () => {
            if (closed) return;
            facingMode = facingMode === "environment" ? "user" : "environment";
            try {
                await qr.stop();
                await startStream(facingMode);
            } catch (_) {}
        };

        try {
            await startStream(facingMode);
        } catch (err) {
            // Fallback ke kamera depan / default jika kamera belakang tidak tersedia (misal webcam PC)
            try {
                await startStream("user");
            } catch (err2) {
                await stopAndClose();
                alert("Gagal membuka kamera: " + (err2?.message || err?.message || "Izinkan akses kamera pada perangkat."));
            }
        }
    }

    window.__nfOpenCameraScanner = openCameraScannerOverlay;

    // =========================================================================
    // INJECT CAMERA SCAN BUTTONS INTO POS UI (UNMISTAKABLE & CLEAN LAYOUT)
    // =========================================================================
    function injectPosCameraButtons() {
        if (!isPosPage()) return;

        // 1. Tombol Utama Biru "Scan" tepat di samping kotak pencarian Kasir (#posSearch)
        const posSearch = document.getElementById("posSearch");
        if (posSearch && posSearch.parentElement && posSearch.parentElement.parentElement && !document.getElementById("nfBtnPosCameraScan")) {
            const toolbar = posSearch.parentElement.parentElement;
            const scanBtn = document.createElement("button");
            scanBtn.id = "nfBtnPosCameraScan";
            scanBtn.type = "button";
            scanBtn.title = "Scan Barcode PLU / Timbangan / QR Member dengan Kamera";
            scanBtn.style.cssText = "height:36px;padding:0 12px;border-radius:9999px;border:none;background:linear-gradient(135deg,#2563eb,#1d4ed8);color:#fff;font-weight:900;font-size:11.5px;display:inline-flex;align-items:center;justify-content:center;gap:5px;cursor:pointer;flex-shrink:0;box-shadow:0 4px 12px -3px rgba(37,99,235,.55);white-space:nowrap;";
            scanBtn.innerHTML = `<i class="fa-solid fa-camera" style="font-size:12.5px;"></i><span>Scan</span>`;
            scanBtn.addEventListener("click", (e) => {
                e.preventDefault();
                e.stopPropagation();
                openCameraScannerOverlay({
                    title: "Scan Barcode PLU / QR Member",
                    onScanned: (code) => {
                        const inp = document.getElementById("posSearch");
                        if (!inp) return;
                        inp.value = code;
                        const app = getReadyApp() || window.app;
                        if (app && typeof app.handleBarcodeScan === "function") {
                            app.handleBarcodeScan({ key: "Enter", target: inp });
                        }
                    }
                });
            });
            // Sisipkan tepat setelah wrapper input pencarian (sebelum tombol Grid/List)
            toolbar.insertBefore(scanBtn, posSearch.parentElement.nextSibling);
        }

        // 2. Tombol Scan QR Member di kolom No. WA / Scan QR MEM-... (#posCustomerPhone)
        injectInlineScanBtn("posCustomerPhone", "Scan Kartu QR Member", { rightPx: 4, padRightPx: 36 }, (code) => {
            const inp = document.getElementById("posCustomerPhone");
            if (!inp) return;
            inp.value = code;
            const app = getReadyApp() || window.app;
            if (app && typeof app.lookupPosMemberDirect === "function") {
                app.lookupPosMemberDirect(code);
            }
        });

        // 3. Tombol Scan Barcode di filter Stok (#invSearchInput — tidak menabrak tombol X!)
        injectInlineScanBtn("invSearchInput", "Scan Barcode Produk di Rak", { rightPx: 28, padRightPx: 62 }, (code) => {
            const inp = document.getElementById("invSearchInput");
            if (!inp) return;
            inp.value = code;
            const app = getReadyApp() || window.app;
            if (app && typeof app.filterInventory === "function") {
                app.filterInventory();
            }
        });

        // 4. Tombol Scan Barcode Kemasan di Modal Tambah/Edit Produk (#editBarcode)
        const editBc = document.getElementById("editBarcode");
        if (editBc && editBc.parentElement && !document.querySelector('[data-nf-scan="editBarcode"]')) {
            const wrap = document.createElement("div");
            wrap.style.cssText = "position:relative;display:flex;align-items:center;";
            editBc.parentElement.insertBefore(wrap, editBc);
            wrap.appendChild(editBc);
            injectInlineScanBtn("editBarcode", "Scan Barcode Kemasan Produk", { rightPx: 5, padRightPx: 38 }, (code) => {
                const inp = document.getElementById("editBarcode");
                if (inp) inp.value = code;
            });
        }
    }

    function injectInlineScanBtn(inputId, title, { rightPx = 5, padRightPx = 38 }, onScanned) {
        const inp = document.getElementById(inputId);
        if (!inp || !inp.parentElement || inp.parentElement.querySelector(`[data-nf-scan="${inputId}"]`)) return;
        const parent = inp.parentElement;
        if (getComputedStyle(parent).position === "static") {
            parent.style.position = "relative";
        }
        inp.style.paddingRight = padRightPx + "px";
        const btn = document.createElement("button");
        btn.type = "button";
        btn.setAttribute("data-nf-scan", inputId);
        btn.title = title;
        btn.style.cssText = `position:absolute;right:${rightPx}px;top:50%;transform:translateY(-50%);width:26px;height:26px;border-radius:9999px;border:none;background:linear-gradient(135deg,#2563eb,#1d4ed8);color:#fff;display:flex;align-items:center;justify-content:center;cursor:pointer;z-index:6;box-shadow:0 2px 6px rgba(37,99,235,.4);`;
        btn.innerHTML = `<i class="fa-solid fa-camera" style="font-size:11px;"></i>`;
        btn.addEventListener("click", (e) => {
            e.preventDefault();
            e.stopPropagation();
            openCameraScannerOverlay({ title, onScanned });
        });
        parent.appendChild(btn);
    }

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

    // =========================================================================
    // HOOK INTO REAL POS APP (window.__nutriReadyApp) FOR NATIVE FEATURES
    // =========================================================================
    let posNativePatched = false;

    function patchPosNativeApp(app) {
        if (!app || posNativePatched) return;
        posNativePatched = true;

        // Pastikan tombol Office/Absensi terhapus & tombol scan terpasang di UI
        stripNativeHiddenNodes();
        injectPosCameraButtons();

        if (nativeAppRole !== "pos") return;

        // 1. Keluarkan tab Absensi dari daftar tab di aplikasi POS Native
        if (typeof app.getAllowedTabsForCurrentStaff === "function") {
            const origAllowed = app.getAllowedTabsForCurrentStaff.bind(app);
            app.getAllowedTabsForCurrentStaff = function () {
                const list = origAllowed() || [];
                const filtered = list.filter((t) => t !== "absensi");
                return filtered.length ? filtered : ["kasir"];
            };
        }

        if (typeof app.switchAdminTab === "function") {
            const origSwitch = app.switchAdminTab.bind(app);
            app.switchAdminTab = function (t) {
                return origSwitch(t === "absensi" ? "kasir" : t);
            };
        }

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
    }

    function onDomReadyInit() {
        stripNativeHiddenNodes();
        injectPosCameraButtons();
    }

    // Boot cleanly: strip hidden native buttons & inject camera buttons immediately on DOM ready
    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", onDomReadyInit);
    } else {
        onDomReadyInit();
    }

    let tries = 0;
    const poll = setInterval(() => {
        tries++;
        const realApp = getReadyApp();
        if (realApp) {
            patchPosNativeApp(realApp);
            clearInterval(poll);
        } else if (tries > 200) {
            clearInterval(poll);
        }
    }, 150);


    // =========================================================================
    // UNIVERSAL SMART BACK BUTTON (ANDROID APK + MOBILE PWA/WEB)
    // Priority: Close Overlay -> Close Modal -> Back to Home Tab -> 2x Tap Exit
    // =========================================================================
    let __nfLastBackAt = 0;

    function showNfBackToast(msg) {
        let el = document.getElementById("nfSmartBackToast");
        if (!el) {
            el = document.createElement("div");
            el.id = "nfSmartBackToast";
            el.style.cssText = "position:fixed;left:50%;bottom:84px;transform:translateX(-50%);z-index:100005;background:rgba(15,23,42,.92);color:#fff;padding:9px 16px;border-radius:9999px;font-family:Inter,system-ui,sans-serif;font-size:12px;font-weight:800;box-shadow:0 10px 26px rgba(0,0,0,.35);pointer-events:none;transition:opacity .2s ease;white-space:nowrap;";
            document.body.appendChild(el);
        }
        el.textContent = msg;
        el.style.opacity = "1";
        clearTimeout(el.__t);
        el.__t = setTimeout(() => { el.style.opacity = "0"; }, 1800);
    }

    function closeTopmostVisibleModal() {
        // 1. Dynamic overlays (Camera Scanner, Native Printer Picker)
        const camClose = document.getElementById("nfCamClose");
        if (camClose) { camClose.click(); return true; }
        const prModal = document.getElementById("nfNativePrinterModal");
        if (prModal) { prModal.remove(); return true; }

        // 2. Standard app modals (visible & not .hidden)
        const candidates = Array.from(document.querySelectorAll(
            'div[id$="Modal"], #memberModal, #customerItemModal, #customerCartModal, #parcelPreOrderModal, #publicReceiptModal, #customerOrdersModal, #webEntryChoiceModal, #iosInstallGuideModal, #payslipModal, #officePhotoModal, #staffPhotoModal, #staffAlertModal, #customModal'
        )).filter((el) => {
            if (!el || el.classList.contains("hidden")) return false;
            if (el.id === "officeAuthGateModal") return false;
            const st = window.getComputedStyle(el);
            return st.display !== "none" && st.visibility !== "hidden" && st.opacity !== "0";
        });

        if (candidates.length === 0) return false;
        // Sort by z-index descending, then DOM order descending
        candidates.sort((a, b) => {
            const za = parseInt(window.getComputedStyle(a).zIndex, 10) || 0;
            const zb = parseInt(window.getComputedStyle(b).zIndex, 10) || 0;
            return zb - za;
        });
        const top = candidates[0];
        if (top.id === "publicReceiptModal" && window.app && typeof window.app.closePublicReceiptModal === "function") {
            window.app.closePublicReceiptModal();
            return true;
        }
        if (top.id === "posItemInputModal" && window.app && typeof window.app.closePosItemInputModal === "function") {
            window.app.closePosItemInputModal();
            return true;
        }
        top.classList.add("hidden");
        return true;
    }

    window.__nfHandleHardwareBack = function () {
        // 1. Tutup pop-up / overlay yang sedang terbuka
        if (closeTopmostVisibleModal()) return "HANDLED";

        const realApp = getReadyApp();

        // 2. KATALOG (index.html): keluar mode cari / reset kategori ke Beranda
        const custView = document.getElementById("customerView");
        if (custView && realApp) {
            if (custView.classList.contains("nf-search-active")) {
                if (typeof realApp.exitCustomerSearchMode === "function") realApp.exitCustomerSearchMode(true);
                return "HANDLED";
            }
            if (realApp.state && realApp.state.customerActiveCategory && realApp.state.customerActiveCategory !== "Semua") {
                if (typeof realApp.resetCustomerFilters === "function") realApp.resetCustomerFilters();
                return "HANDLED";
            }
        }

        // 3. POS (pos.html): kembali dari Keranjang mobile -> Pilih Buah, atau dari tab lain (Atur/Stok/Laporan/PO/Tim/Member) -> Kasir
        if (document.getElementById("posSearch") && realApp && realApp.state) {
            if (realApp.state.currentAdminTab === "kasir" && realApp.state.mobilePosSubTab === "cart" && window.innerWidth < 1024) {
                if (typeof realApp.setMobilePosSubTab === "function") realApp.setMobilePosSubTab("products");
                return "HANDLED";
            }
            if (realApp.state.currentAdminTab && realApp.state.currentAdminTab !== "kasir") {
                if (typeof realApp.switchAdminTab === "function") realApp.switchAdminTab("kasir");
                return "HANDLED";
            }
        }

        // 4. STAFF (staff.html): kembali dari tab Pengajuan/Gaji/Profil -> Absensi
        if (window.staffApp && window.staffApp.state && window.staffApp.state.activeTab && window.staffApp.state.activeTab !== "absensi") {
            if (typeof window.staffApp.switchTab === "function") window.staffApp.switchTab("absensi");
            return "HANDLED";
        }

        // 5. OFFICE (office.html): kembali ke tab awal (Kas & Beban / Persetujuan HR)
        if (window.officeApp && window.officeApp.state) {
            const homeTab = window.officeApp.isTabAllowedForRole("ringkasan") ? "ringkasan" : "hrd";
            if (window.officeApp.state.activeTab && window.officeApp.state.activeTab !== homeTab && window.officeApp.isTabAllowedForRole(homeTab)) {
                window.officeApp.switchTab(homeTab, true);
                return "HANDLED";
            }
        }

        // 6. Sudah di layar depan utama -> wajib tekan 2x dalam 2 detik untuk keluar
        const now = Date.now();
        if (now - __nfLastBackAt < 2000) {
            return "EXIT";
        }
        __nfLastBackAt = now;
        showNfBackToast("Tekan sekali lagi untuk keluar aplikasi");
        return "HANDLED";
    };

    // Guard tombol Back browser HP / PWA (Chrome Android / Standalone Web)
    if (!isAndroidNative() && !isTauri() && /Android|Mobile|iPhone|iPad/i.test(navigator.userAgent || "")) {
        try {
            window.history.pushState({ nfBackGuard: 1 }, "");
            window.addEventListener("popstate", function () {
                const res = window.__nfHandleHardwareBack();
                if (res !== "EXIT") {
                    try { window.history.pushState({ nfBackGuard: 1 }, ""); } catch (_) {}
                }
            });
        } catch (_) {}
    }



    // =========================================================================
    // UNIFIED NOTIFICATION ENGINE (ANDROID NATIVE APK + PWA/WEB + PC DESKTOP)
    // =========================================================================
    let __nfAudioCtx = null;

    function unlockAudioCtx() {
        try {
            const Ctx = window.AudioContext || window.webkitAudioContext;
            if (!Ctx) return null;
            if (!__nfAudioCtx) __nfAudioCtx = new Ctx();
            if (__nfAudioCtx.state === "suspended") __nfAudioCtx.resume().catch(() => {});
            return __nfAudioCtx;
        } catch (_) { return null; }
    }

    function playChime(type = "order") {
        try {
            const ctx = unlockAudioCtx();
            if (!ctx) return;
            const now = ctx.currentTime;
            const freqs = type === "order" ? [880, 1174.66, 1567.98] : [659.25, 987.77];
            freqs.forEach((f, idx) => {
                const osc = ctx.createOscillator();
                const gain = ctx.createGain();
                osc.type = "sine";
                osc.frequency.setValueAtTime(f, now + idx * 0.11);
                gain.gain.setValueAtTime(0.001, now + idx * 0.11);
                gain.gain.exponentialRampToValueAtTime(0.22, now + idx * 0.11 + 0.02);
                gain.gain.exponentialRampToValueAtTime(0.001, now + idx * 0.11 + 0.28);
                osc.connect(gain);
                gain.connect(ctx.destination);
                osc.start(now + idx * 0.11);
                osc.stop(now + idx * 0.11 + 0.30);
            });
        } catch (_) {}
    }

    // Unlock Web Audio on first user interaction so POS/Customer bell can ring reliably
    ["click", "touchstart", "keydown"].forEach((evName) => {
        document.addEventListener(evName, () => { unlockAudioCtx(); }, { once: true, passive: true });
    });

    function showInAppNotifyBanner(title, body, onClickCb) {
        let box = document.getElementById("nfLiveNotifyBanner");
        if (box) box.remove();
        box = document.createElement("div");
        box.id = "nfLiveNotifyBanner";
        box.style.cssText = "position:fixed;top:14px;left:50%;transform:translateX(-50%);z-index:100020;width:calc(100% - 24px);max-width:410px;background:rgba(15,23,42,.95);color:#fff;border:1.5px solid rgba(132,204,22,.65);border-radius:20px;padding:12px 15px;box-shadow:0 18px 40px rgba(0,0,0,.38);display:flex;align-items:center;gap:11px;font-family:Inter,system-ui,sans-serif;cursor:pointer;backdrop-filter:blur(10px);";
        box.innerHTML = `
            <div style="width:36px;height:36px;border-radius:12px;background:#7cb342;color:#fff;display:flex;align-items:center;justify-content:center;flex-shrink:0;font-size:15px;"><i class="fa-solid fa-bell"></i></div>
            <div style="min-width:0;flex:1;">
                <div style="font-size:12.5px;font-weight:900;color:#d9f99d;line-height:1.2;">${escapeHtml(title)}</div>
                <div style="font-size:11.5px;color:#e2e8f0;margin-top:2px;line-height:1.3;">${escapeHtml(body)}</div>
            </div>
            <button type="button" style="background:rgba(255,255,255,.15);border:none;color:#fff;width:26px;height:26px;border-radius:999px;font-weight:900;cursor:pointer;flex-shrink:0;">✕</button>`;
        box.querySelector("button").onclick = (e) => { e.stopPropagation(); box.remove(); };
        box.onclick = () => { box.remove(); if (typeof onClickCb === "function") onClickCb(); };
        document.body.appendChild(box);
        setTimeout(() => { if (box.parentNode) box.remove(); }, 6500);
    }

    window.nfPlayChime = playChime;
    window.nfNotify = {
        getStatus() {
            if (isAndroidNative() && typeof window.NfAndroidNative.hasNotificationPermission === "function") {
                return window.NfAndroidNative.hasNotificationPermission() ? "granted" : "default";
            }
            if (typeof window.Notification === "undefined") return "unsupported";
            return window.Notification.permission || "default";
        },
        async requestPermission() {
            unlockAudioCtx();
            if (isAndroidNative() && typeof window.NfAndroidNative.requestNotificationPermission === "function") {
                try {
                    window.NfAndroidNative.requestNotificationPermission();
                    const deadline = Date.now() + 8000;
                    while (Date.now() < deadline) {
                        await new Promise((r) => setTimeout(r, 300));
                        if (window.NfAndroidNative.hasNotificationPermission()) {
                            playChime("status");
                            return "granted";
                        }
                    }
                    return window.NfAndroidNative.hasNotificationPermission() ? "granted" : "default";
                } catch (_) { return "default"; }
            }
            if (typeof window.Notification === "undefined") return "unsupported";
            try {
                const res = await window.Notification.requestPermission();
                if (res === "granted") playChime("status");
                return res;
            } catch (_) { return "default"; }
        },
        async send({ title = "NutriFresh", body = "", tag = "nf-alert", sound = "order", onClick = null } = {}) {
            try { if (navigator.vibrate) navigator.vibrate([120, 60, 120]); } catch (_) {}
            playChime(sound);
            showInAppNotifyBanner(title, body, onClick);

            // 1. Android Native Notification (Status Bar + Sound + Vibration)
            if (isAndroidNative() && typeof window.NfAndroidNative.showLocalNotification === "function") {
                try {
                    window.NfAndroidNative.showLocalNotification(String(title), String(body));
                    return true;
                } catch (_) {}
            }

            // 2. ServiceWorker / Web Notification API (Chrome Android PWA, Windows PC, Edge, macOS, iOS PWA)
            if (typeof window.Notification !== "undefined" && window.Notification.permission === "granted") {
                try {
                    if ("serviceWorker" in navigator) {
                        const reg = await navigator.serviceWorker.getRegistration();
                        if (reg && typeof reg.showNotification === "function") {
                            await reg.showNotification(title, {
                                body,
                                icon: "/icon.png",
                                badge: "/icon.png",
                                tag,
                                renotify: true,
                                vibrate: [150, 70, 150]
                            });
                            return true;
                        }
                    }
                    new window.Notification(title, { body, icon: "/icon.png", tag });
                    return true;
                } catch (_) {}
            }
            return false;
        }
    };

})();
