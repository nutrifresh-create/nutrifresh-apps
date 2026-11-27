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
        const docClose = document.getElementById("nfSafeDocClose");
        if (docClose) { docClose.click(); return true; }
        const camClose = document.getElementById("nfCamClose");
        if (camClose) { camClose.click(); return true; }
        const updModal = document.getElementById("nfAppUpdateModal");
        if (updModal) {
            if (updModal.dataset.locked === "1") return true;
            updModal.remove();
            return true;
        }
        const permModal = document.getElementById("nfPermChecklistModal");
        if (permModal) { permModal.remove(); return true; }
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
            if (isAndroidNative() && (typeof window.NfAndroidNative.requestNotificationPermissionSmart === "function" || typeof window.NfAndroidNative.requestNotificationPermission === "function")) {
                try {
                    if (typeof window.NfAndroidNative.requestNotificationPermissionSmart === "function") {
                        window.NfAndroidNative.requestNotificationPermissionSmart();
                    } else {
                        window.NfAndroidNative.requestNotificationPermission();
                    }
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
        async send({ title = "NutriFresh", body = "", tag = "nf-alert", sound = "order", onClick = null, forceOsBanner = false } = {}) {
            // Anti-duplikat 20 detik (mencegah 1 event memicu notifikasi berkali-kali saat polling/reconnect)
            if (!window.__nfRecentNotifMap) window.__nfRecentNotifMap = {};
            const dedupeKey = `${tag}|${title}|${body}`;
            const nowMs = Date.now();
            if (!forceOsBanner && window.__nfRecentNotifMap[dedupeKey] && (nowMs - window.__nfRecentNotifMap[dedupeKey]) < 20000) {
                return false;
            }
            window.__nfRecentNotifMap[dedupeKey] = nowMs;

            try { if (navigator.vibrate) navigator.vibrate([120, 60, 120]); } catch (_) {}
            playChime(sound);
            showInAppNotifyBanner(title, body, onClick);

            // 1. Android Native APK: Notifikasi status bar ditangani 1 pintu oleh FCM Native + Live Order ala Gojek!
            // Hanya tembak showLocalNotification jika memang tombol Tes Manual (forceOsBanner: true).
            if (isAndroidNative()) {
                if (forceOsBanner && typeof window.NfAndroidNative.showLocalNotification === "function") {
                    try {
                        window.NfAndroidNative.showLocalNotification(String(title), String(body));
                        return true;
                    } catch (_) {}
                }
                return true;
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


    // =========================================================================
    // BACKGROUND PUSH TOKEN SYNC (FCM ANDROID -> SUPABASE nf_push_devices v144)
    // =========================================================================
    window.__nfLastFcmToken = "";
    window.__nfSyncFcmToken = function(extraMeta) {
        try {
            var tok = window.__nfLastFcmToken || "";
            if (!tok && window.NfAndroidNative && typeof window.NfAndroidNative.getFcmToken === "function") {
                tok = String(window.NfAndroidNative.getFcmToken() || "").trim();
            }
            if (tok && tok.length >= 16) {
                window.__nfLastFcmToken = tok;
                if (typeof window.__nfRegisterPushToken === "function") {
                    window.__nfRegisterPushToken(tok, extraMeta || {});
                }
            }
        } catch (_) {}
    };
    window.__nfOnFcmToken = function(tok) {
        if (tok && String(tok).length >= 16) {
            window.__nfLastFcmToken = String(tok).trim();
            window.__nfSyncFcmToken({});
        }
    };
    setTimeout(function() { window.__nfSyncFcmToken({}); }, 2500);
    setTimeout(function() { window.__nfSyncFcmToken({}); }, 7000);

    // =========================================================================
    // UNIVERSAL SMART PERMISSION CHECKLIST ENGINE (ANDROID APK + iPHONE + WEB v145)
    // - Hybrid Strategy:
    //   * Staff / POS / Office: Auto-checks 1x after login if any required permission missing
    //   * Customer: Silent for browsing guests; auto-prompts after Member login or first checkout
    // - Android APK: 1-tap Battery Unrestricted + Smart Notif Settings if permanently denied
    // - iPhone / Web: Pre-prompt protection + clear 2-step recovery guide if denied
    // =========================================================================
    const PERM_ROLE_PRESETS = {
        customer: {
            title: "Aktifkan Notifikasi Pesanan",
            subtitle: "Agar HP langsung berbunyi saat buah selesai ditimbang, ada chat kasir/kurir, dan saat kurir berangkat.",
            accent: "#558b2f",
            items: ["notif", "battery"],
            dismissDays: 7
        },
        staff: {
            title: "Kelengkapan Izin NutriFresh Staff",
            subtitle: "Aktifkan izin berikut agar Absensi GPS, Foto Bukti, Alarm Shift/Dzikir & Antaran Kurir lancar tanpa delay.",
            accent: "#0f766e",
            items: ["notif", "battery", "location", "camera"],
            dismissDays: 1
        },
        pos: {
            title: "Kelengkapan Izin NutriFresh POS",
            subtitle: "Aktifkan agar bel order online berbunyi instan tanpa delay dan kamera scanner barcode lancar.",
            accent: "#558b2f",
            items: ["notif", "battery", "camera"],
            dismissDays: 1
        },
        office: {
            title: "Kelengkapan Izin NutriFresh Office",
            subtitle: "Aktifkan agar ajuan gaji, kasbon, pinjaman & pengajuan HR langsung berbunyi di HP Anda.",
            accent: "#0ea5e9",
            items: ["notif", "battery"],
            dismissDays: 1
        }
    };

    const PERM_ITEM_META = {
        notif: {
            icon: "fa-solid fa-bell",
            label: "Notifikasi Langsung",
            descByRole: {
                customer: "Kabar otomatis saat timbangan selesai, chat toko & kurir berangkat.",
                staff: "Pengingat jadwal shift, zikir pagi/petang, pengumuman & antaran kurir.",
                pos: "Bel instan saat pesanan online, ACC timbangan & bukti bayar masuk.",
                office: "Kabar instan saat HR ajukan transfer gaji, kasbon & pinjaman."
            }
        },
        battery: {
            icon: "fa-solid fa-bolt",
            label: "Jalan Lancar Tanpa Delay (Baterai)",
            descByRole: {
                customer: "Matikan pembatasan baterai agar notifikasi tetap masuk saat layar HP mati.",
                staff: "Wajib agar alarm shift, dzikir & push antaran tidak ditunda HP saat layar mati.",
                pos: "Agar bel order masuk tetap instan walau tablet sedang tidak dibuka.",
                office: "Agar notifikasi ajuan transfer HR tetap masuk tepat waktu saat layar mati."
            }
        },
        location: {
            icon: "fa-solid fa-location-dot",
            label: "Lokasi GPS (Absensi Toko)",
            descByRole: {
                staff: "Diperlukan untuk verifikasi radius toko saat Absen Masuk & Pulang."
            }
        },
        camera: {
            icon: "fa-solid fa-camera",
            label: "Kamera (Scan / Foto Bukti)",
            descByRole: {
                staff: "Untuk foto bukti kehadiran & foto serah terima antaran kurir.",
                pos: "Untuk scan barcode PLU timbangan, QR Kartu Member & foto bukti."
            }
        }
    };

    function isIosDevice() {
        const ua = navigator.userAgent || "";
        return /iPad|iPhone|iPod/.test(ua) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
    }

    function isStandaloneMode() {
        return (window.matchMedia && window.matchMedia("(display-mode: standalone)").matches) ||
            window.navigator.standalone === true ||
            document.referrer.includes("android-app://");
    }

    async function readPermissionStates(roleKey) {
        const preset = PERM_ROLE_PRESETS[roleKey] || PERM_ROLE_PRESETS.customer;
        const android = isAndroidNative();
        const ios = isIosDevice();
        const standalone = isStandaloneMode();
        const states = {
            platform: android ? "android_apk" : (ios ? "ios" : "web"),
            isIosSafariBrowser: ios && !standalone && !android,
            items: {}
        };

        // Read Android native snapshot if available
        let nativeObj = null;
        if (android) {
            try {
                if (typeof window.NfAndroidNative.getPermissionStatusJson === "function") {
                    nativeObj = JSON.parse(window.NfAndroidNative.getPermissionStatusJson() || "{}");
                }
            } catch (_) {}
        }

        for (const key of preset.items) {
            // Battery unrestricted is ONLY relevant & available on Android APK
            if (key === "battery") {
                if (!android) continue;
                const ok = nativeObj ? !!nativeObj.batteryUnrestricted : (
                    typeof window.NfAndroidNative.isIgnoringBatteryOptimizations === "function"
                        ? !!window.NfAndroidNative.isIgnoringBatteryOptimizations()
                        : false
                );
                states.items.battery = { status: ok ? "granted" : "prompt" };
                continue;
            }

            if (key === "notif") {
                if (android) {
                    const ok = nativeObj ? !!nativeObj.notif : (
                        typeof window.NfAndroidNative.hasNotificationPermission === "function"
                            ? !!window.NfAndroidNative.hasNotificationPermission()
                            : true
                    );
                    const forever = nativeObj ? !!nativeObj.notifDeniedForever : (
                        typeof window.NfAndroidNative.isNotificationPermanentlyDenied === "function"
                            ? !!window.NfAndroidNative.isNotificationPermanentlyDenied()
                            : false
                    );
                    states.items.notif = { status: ok ? "granted" : (forever ? "denied" : "prompt") };
                } else if (states.isIosSafariBrowser) {
                    states.items.notif = { status: "ios_need_pwa" };
                } else if (typeof window.Notification === "undefined") {
                    states.items.notif = { status: "unsupported" };
                } else {
                    const perm = window.Notification.permission || "default";
                    states.items.notif = { status: perm === "granted" ? "granted" : (perm === "denied" ? "denied" : "prompt") };
                }
                continue;
            }

            if (key === "location") {
                if (android) {
                    const ok = nativeObj ? !!nativeObj.location : (
                        typeof window.NfAndroidNative.hasLocationPermission === "function"
                            ? !!window.NfAndroidNative.hasLocationPermission()
                            : false
                    );
                    states.items.location = { status: ok ? "granted" : "prompt" };
                } else {
                    let st = "prompt";
                    try {
                        if (navigator.permissions && navigator.permissions.query) {
                            const res = await navigator.permissions.query({ name: "geolocation" });
                            st = res.state === "granted" ? "granted" : (res.state === "denied" ? "denied" : "prompt");
                        }
                    } catch (_) {}
                    states.items.location = { status: st };
                }
                continue;
            }

            if (key === "camera") {
                if (android) {
                    const ok = nativeObj ? !!nativeObj.camera : (
                        typeof window.NfAndroidNative.hasCameraPermission === "function"
                            ? !!window.NfAndroidNative.hasCameraPermission()
                            : false
                    );
                    states.items.camera = { status: ok ? "granted" : "prompt" };
                } else {
                    let st = "prompt";
                    try {
                        if (navigator.permissions && navigator.permissions.query) {
                            const res = await navigator.permissions.query({ name: "camera" });
                            st = res.state === "granted" ? "granted" : (res.state === "denied" ? "denied" : "prompt");
                        }
                    } catch (_) {}
                    states.items.camera = { status: st };
                }
            }
        }
        return states;
    }

    function getWebRecoveryGuideHtml(key) {
        const ios = isIosDevice();
        if (ios && !isStandaloneMode()) {
            return `<strong>Cara aktifkan di iPhone:</strong><br>1. Ketuk ikon <strong>Bagikan (Share)</strong> di bawah Safari → pilih <strong>Tambah ke Layar Utama</strong>.<br>2. Buka NutriFresh dari ikon di Layar Utama, lalu ketuk tombol <strong>Aktifkan</strong> di sini.`;
        }
        if (ios) {
            return `<strong>Izin sempat ditolak di iPhone:</strong><br>Buka <strong>Pengaturan iPhone → Pemberitahuan → NutriFresh</strong> (atau Safari) → geser ke <strong>Izinkan</strong>, lalu kembali ke aplikasi.`;
        }
        const labelMap = { notif: "Notifikasi", location: "Lokasi", camera: "Kamera" };
        const nm = labelMap[key] || "Izin";
        return `<strong>Izin ${nm} sempat ditolak browser:</strong><br>1. Ketuk ikon <strong>Pengaturan / Gembok</strong> di samping alamat website paling atas.<br>2. Pilih <strong>Izin (Permissions) → ${nm} → Izinkan</strong>, lalu muat ulang halaman.`;
    }

    let __activePermRole = null;
    let __activePermTimer = null;

    async function triggerSinglePermission(roleKey, itemKey) {
        const android = isAndroidNative();

        if (itemKey === "battery" && android) {
            if (typeof window.NfAndroidNative.requestIgnoreBatteryOptimizations === "function") {
                window.NfAndroidNative.requestIgnoreBatteryOptimizations();
            } else if (typeof window.NfAndroidNative.openAppInfoSettings === "function") {
                window.NfAndroidNative.openAppInfoSettings();
            }
            return;
        }

        if (itemKey === "notif") {
            if (android) {
                if (typeof window.NfAndroidNative.requestNotificationPermissionSmart === "function") {
                    window.NfAndroidNative.requestNotificationPermissionSmart();
                } else if (typeof window.NfAndroidNative.requestNotificationPermission === "function") {
                    window.NfAndroidNative.requestNotificationPermission();
                }
                setTimeout(() => {
                    if (window.__nfSyncFcmToken) window.__nfSyncFcmToken({});
                    refreshPermModalIfOpen();
                }, 900);
                return;
            }
            if (isIosDevice() && !isStandaloneMode()) {
                return;
            }
            if (typeof window.Notification !== "undefined" && window.Notification.permission !== "denied") {
                try {
                    const res = await window.Notification.requestPermission();
                    if (res === "granted" && window.nfPlayChime) window.nfPlayChime("status");
                } catch (_) {}
            }
            refreshPermModalIfOpen();
            return;
        }

        if (itemKey === "location") {
            if (android && typeof window.NfAndroidNative.requestLocationPermission === "function") {
                const before = typeof window.NfAndroidNative.hasLocationPermission === "function" && window.NfAndroidNative.hasLocationPermission();
                window.NfAndroidNative.requestLocationPermission();
                setTimeout(() => {
                    const after = typeof window.NfAndroidNative.hasLocationPermission === "function" && window.NfAndroidNative.hasLocationPermission();
                    if (!before && !after && typeof window.NfAndroidNative.openAppInfoSettings === "function") {
                        // Biarkan user tekan sekali lagi jika baru tampil dialog; bila sudah 2x ditolak bisa pakai tombol Info Aplikasi
                    }
                    refreshPermModalIfOpen();
                }, 900);
                return;
            }
            if (navigator.geolocation) {
                navigator.geolocation.getCurrentPosition(
                    () => refreshPermModalIfOpen(),
                    () => refreshPermModalIfOpen(),
                    { timeout: 8000 }
                );
            }
            return;
        }

        if (itemKey === "camera") {
            if (android && typeof window.NfAndroidNative.requestCameraPermission === "function") {
                window.NfAndroidNative.requestCameraPermission();
                setTimeout(() => refreshPermModalIfOpen(), 900);
                return;
            }
            if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
                try {
                    const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } });
                    stream.getTracks().forEach((t) => t.stop());
                } catch (_) {}
                refreshPermModalIfOpen();
            }
        }
    }

    async function renderPermChecklistModal(roleKey) {
        const preset = PERM_ROLE_PRESETS[roleKey] || PERM_ROLE_PRESETS.customer;
        const states = await readPermissionStates(roleKey);
        const keys = Object.keys(states.items);
        const android = isAndroidNative();
        const isDark = document.documentElement.getAttribute("data-theme") === "dark" ||
            document.body.classList.contains("nf-office-page");

        let modal = document.getElementById("nfPermChecklistModal");
        if (!modal) {
            modal = document.createElement("div");
            modal.id = "nfPermChecklistModal";
            modal.style.cssText = "position:fixed;inset:0;z-index:100030;background:rgba(15,23,42,.66);backdrop-filter:blur(8px);display:flex;align-items:flex-end;justify-content:center;padding:12px;font-family:Inter,system-ui,sans-serif;";
            if (window.innerWidth >= 640) modal.style.alignItems = "center";
            modal.addEventListener("click", (e) => {
                if (e.target === modal) closePermChecklistModal(roleKey, true);
            });
            document.body.appendChild(modal);
        }

        const totalCount = keys.length;
        const grantedCount = keys.filter((k) => states.items[k].status === "granted").length;
        const allGranted = totalCount > 0 && grantedCount === totalCount;

        if (allGranted) {
            try { localStorage.setItem(`nf_perm_all_ok_${roleKey}`, "1"); } catch (_) {}
            if (window.__nfSyncFcmToken) window.__nfSyncFcmToken({});
        }

        const cardBg = isDark ? "#111827" : "#ffffff";
        const cardBorder = isDark ? "rgba(255,255,255,.14)" : "#e2e8f0";
        const textMain = isDark ? "#f8fafc" : "#0f172a";
        const textSub = isDark ? "#94a3b8" : "#64748b";
        const rowBg = isDark ? "rgba(30,41,59,.78)" : "#f8fafc";
        const rowOkBg = isDark ? "rgba(16,185,129,.14)" : "#f0fdf4";
        const rowOkBorder = isDark ? "rgba(52,211,153,.35)" : "#bbf7d0";

        const rowsHtml = keys.map((k) => {
            const meta = PERM_ITEM_META[k];
            const st = states.items[k].status;
            const isOk = st === "granted";
            const isDenied = st === "denied";
            const isIosPwa = st === "ios_need_pwa";
            const desc = (meta.descByRole && (meta.descByRole[roleKey] || meta.descByRole.customer || meta.descByRole.staff)) || "";

            let btnHtml = "";
            if (isOk) {
                btnHtml = `<span style="padding:5px 11px;border-radius:999px;background:#16a34a;color:#fff;font-size:11px;font-weight:800;white-space:nowrap;">✓ Aktif</span>`;
            } else if (isIosPwa) {
                btnHtml = `<span style="padding:5px 10px;border-radius:999px;background:#fef3c7;color:#92400e;font-size:10.5px;font-weight:800;white-space:nowrap;">Pasang Dulu</span>`;
            } else if (isDenied && android) {
                btnHtml = `<button type="button" data-perm-act="${k}" style="padding:7px 12px;border-radius:999px;border:none;background:#ea580c;color:#fff;font-size:11px;font-weight:800;cursor:pointer;white-space:nowrap;">Buka Setelan</button>`;
            } else if (isDenied) {
                btnHtml = `<span style="padding:5px 10px;border-radius:999px;background:#fee2e2;color:#b91c1c;font-size:10.5px;font-weight:800;white-space:nowrap;">Ditolak</span>`;
            } else {
                btnHtml = `<button type="button" data-perm-act="${k}" style="padding:7px 14px;border-radius:999px;border:none;background:${preset.accent};color:#fff;font-size:11px;font-weight:800;cursor:pointer;white-space:nowrap;box-shadow:0 4px 10px -4px rgba(0,0,0,.35);">Aktifkan</button>`;
            }

            const recoveryHtml = (!isOk && ((isDenied && !android) || isIosPwa))
                ? `<div style="margin-top:8px;padding:8px 10px;border-radius:12px;background:${isDark ? 'rgba(245,158,11,.15)' : '#fffbeb'};border:1px solid ${isDark ? 'rgba(251,191,36,.35)' : '#fde68a'};color:${isDark ? '#fde68a' : '#78350f'};font-size:10.5px;line-height:1.45;">${getWebRecoveryGuideHtml(k)}</div>`
                : "";

            return `
                <div style="padding:11px 12px;border-radius:18px;border:1px solid ${isOk ? rowOkBorder : cardBorder};background:${isOk ? rowOkBg : rowBg};">
                    <div style="display:flex;align-items:center;justify-content:space-between;gap:10px;">
                        <div style="display:flex;align-items:flex-start;gap:10px;min-width:0;flex:1;">
                            <div style="width:34px;height:34px;border-radius:12px;background:${isOk ? '#16a34a' : preset.accent}20;color:${isOk ? '#16a34a' : preset.accent};display:flex;align-items:center;justify-content:center;flex-shrink:0;font-size:14px;">
                                <i class="${meta.icon}"></i>
                            </div>
                            <div style="min-width:0;">
                                <div style="font-size:12.5px;font-weight:800;color:${textMain};line-height:1.25;">${escapeHtml(meta.label)}</div>
                                <div style="font-size:11px;color:${textSub};margin-top:2px;line-height:1.35;">${escapeHtml(desc)}</div>
                            </div>
                        </div>
                        <div style="flex-shrink:0;">${btnHtml}</div>
                    </div>
                    ${recoveryHtml}
                </div>`;
        }).join("");

        let installedVerLabel = "";
        if (android && typeof window.NfAndroidNative.getAppVersionJson === "function") {
            try {
                const vi = JSON.parse(window.NfAndroidNative.getAppVersionJson() || "{}");
                if (vi.versionName) installedVerLabel = `v${vi.versionName}`;
            } catch (_) {}
        }
        const autostartTipHtml = android
            ? `<div style="margin-top:10px;padding:9px 11px;border-radius:14px;background:${isDark ? 'rgba(56,189,248,.12)' : '#eff6ff'};border:1px solid ${isDark ? 'rgba(56,189,248,.3)' : '#bfdbfe'};display:flex;align-items:center;justify-content:space-between;gap:8px;">
                   <span style="font-size:10.5px;color:${isDark ? '#bae6fd' : '#1e3a8a'};line-height:1.35;"><strong>HP Xiaomi / Oppo / Vivo / Realme?</strong> Aktifkan <em>Mulai Otomatis (Autostart)</em> agar notifikasi super cepat saat layar mati.</span>
                   <button type="button" id="nfPermOpenAppInfo" style="padding:6px 10px;border-radius:999px;border:1px solid ${isDark ? 'rgba(147,197,253,.4)' : '#93c5fd'};background:${isDark ? 'rgba(30,58,138,.5)' : '#fff'};color:${isDark ? '#dbeafe' : '#1d4ed8'};font-size:10.5px;font-weight:800;cursor:pointer;white-space:nowrap;flex-shrink:0;">Info App</button>
               </div>
               <div style="margin-top:6px;padding:8px 11px;border-radius:14px;background:${isDark ? 'rgba(132,204,22,.12)' : '#f4f9f1'};border:1px solid ${isDark ? 'rgba(163,230,53,.28)' : '#cde5be'};display:flex;align-items:center;justify-content:space-between;gap:8px;">
                   <span style="font-size:10.5px;color:${isDark ? '#d9f99d' : '#365314'};line-height:1.35;"><strong>Versi APK ${escapeHtml(installedVerLabel || 'Aktif')}</strong> • Update langsung dari dalam aplikasi.</span>
                   <button type="button" id="nfPermCheckApkUpd" style="padding:6px 10px;border-radius:999px;border:none;background:#558b2f;color:#fff;font-size:10.5px;font-weight:800;cursor:pointer;white-space:nowrap;flex-shrink:0;">Cek Update</button>
               </div>`
            : "";

        modal.innerHTML = `
            <div style="width:100%;max-width:430px;background:${cardBg};border:1px solid ${cardBorder};border-radius:26px;overflow:hidden;box-shadow:0 24px 60px rgba(0,0,0,.45);max-height:90vh;display:flex;flex-direction:column;">
                <div style="background:linear-gradient(135deg,${preset.accent},#1e293b);padding:16px 18px;color:#fff;display:flex;align-items:flex-start;justify-content:space-between;gap:10px;">
                    <div>
                        <div style="font-size:10px;font-weight:900;text-transform:uppercase;letter-spacing:.06em;opacity:.88;">${allGranted ? '✅ Semua Siap' : `Langkah Cepat (${grantedCount}/${totalCount} Aktif)`}</div>
                        <div style="font-size:15.5px;font-weight:900;margin-top:2px;line-height:1.25;">${escapeHtml(preset.title)}</div>
                        <div style="font-size:11px;opacity:.92;margin-top:4px;line-height:1.35;">${escapeHtml(preset.subtitle)}</div>
                    </div>
                    <button type="button" id="nfPermCloseX" aria-label="Tutup" style="width:30px;height:30px;border-radius:999px;border:none;background:rgba(255,255,255,.2);color:#fff;font-weight:900;cursor:pointer;flex-shrink:0;">✕</button>
                </div>
                <div style="padding:14px;overflow-y:auto;display:flex;flex-direction:column;gap:9px;">
                    ${rowsHtml}
                    ${autostartTipHtml}
                </div>
                <div style="padding:12px 14px 14px;border-top:1px solid ${cardBorder};display:flex;align-items:center;justify-content:space-between;gap:8px;">
                    <button type="button" id="nfPermRecheckBtn" style="padding:9px 13px;border-radius:999px;border:1px solid ${cardBorder};background:transparent;color:${textSub};font-size:11.5px;font-weight:800;cursor:pointer;"><i class="fa-solid fa-rotate" style="margin-right:5px;"></i>Cek Ulang</button>
                    <button type="button" id="nfPermDoneBtn" style="flex:1;padding:10px 16px;border-radius:999px;border:none;background:${allGranted ? '#16a34a' : (isDark ? '#334155' : '#e2e8f0')};color:${allGranted ? '#fff' : textMain};font-size:12px;font-weight:900;cursor:pointer;">${allGranted ? '✓ Selesai & Lanjutkan' : 'Nanti Saja'}</button>
                </div>
            </div>`;

        modal.querySelector("#nfPermCloseX").onclick = () => closePermChecklistModal(roleKey, !allGranted);
        modal.querySelector("#nfPermDoneBtn").onclick = () => closePermChecklistModal(roleKey, !allGranted);
        modal.querySelector("#nfPermRecheckBtn").onclick = () => renderPermChecklistModal(roleKey);
        const appInfoBtn = modal.querySelector("#nfPermOpenAppInfo");
        if (appInfoBtn) {
            appInfoBtn.onclick = () => {
                if (android && typeof window.NfAndroidNative.openAppInfoSettings === "function") {
                    window.NfAndroidNative.openAppInfoSettings();
                }
            };
        }
        const updCheckBtn = modal.querySelector("#nfPermCheckApkUpd");
        if (updCheckBtn) {
            updCheckBtn.onclick = () => {
                closePermChecklistModal(roleKey, false);
                if (window.nfUpdater) window.nfUpdater.check(true);
            };
        }
        modal.querySelectorAll("button[data-perm-act]").forEach((btn) => {
            btn.onclick = () => triggerSinglePermission(roleKey, btn.getAttribute("data-perm-act"));
        });
    }

    function closePermChecklistModal(roleKey, recordDismiss = false) {
        const el = document.getElementById("nfPermChecklistModal");
        if (el) el.remove();
        __activePermRole = null;
        if (recordDismiss && roleKey) {
            try {
                localStorage.setItem(`nf_perm_dismissed_at_${roleKey}`, String(Date.now()));
                sessionStorage.setItem(`nf_perm_session_done_${roleKey}`, "1");
            } catch (_) {}
        }
    }

    function refreshPermModalIfOpen() {
        if (__activePermRole && document.getElementById("nfPermChecklistModal")) {
            clearTimeout(__activePermTimer);
            __activePermTimer = setTimeout(() => {
                if (__activePermRole && document.getElementById("nfPermChecklistModal")) {
                    renderPermChecklistModal(__activePermRole);
                }
            }, 300);
        }
    }

    // Otomatis refresh status ceklis begitu user kembali dari pop-up Android / halaman Settings HP
    document.addEventListener("visibilitychange", () => {
        if (!document.hidden) refreshPermModalIfOpen();
    });
    window.addEventListener("focus", () => {
        refreshPermModalIfOpen();
    });

    window.nfPermissions = {
        getStates: readPermissionStates,
        async open(roleKey = "customer") {
            __activePermRole = roleKey;
            await renderPermChecklistModal(roleKey);
        },
        async maybePrompt(roleKey = "customer", opts = {}) {
            try {
                if (isTauri()) return false; // Laptop Windows .exe tidak perlu ceklis izin HP Android/iOS
                const preset = PERM_ROLE_PRESETS[roleKey] || PERM_ROLE_PRESETS.customer;
                const force = !!opts.force;
                const trigger = opts.trigger || "login";

                if (!force) {
                    // Jangan munculkan 2x dalam 1 sesi jika user sudah menekan "Nanti Saja"
                    if (sessionStorage.getItem(`nf_perm_session_done_${roleKey}`) === "1" && trigger !== "checkout") {
                        return false;
                    }
                    const lastDismiss = Number(localStorage.getItem(`nf_perm_dismissed_at_${roleKey}`) || "0");
                    const cooldownMs = (preset.dismissDays || 1) * 24 * 60 * 60 * 1000;
                    if (lastDismiss && (Date.now() - lastDismiss) < cooldownMs && trigger !== "checkout") {
                        return false;
                    }
                }

                const states = await readPermissionStates(roleKey);
                const keys = Object.keys(states.items);
                if (keys.length === 0) return false;
                const missing = keys.filter((k) => {
                    const s = states.items[k].status;
                    return s !== "granted" && s !== "unsupported";
                });
                if (missing.length === 0) {
                    if (window.__nfSyncFcmToken) window.__nfSyncFcmToken({});
                    return false;
                }

                __activePermRole = roleKey;
                await renderPermChecklistModal(roleKey);
                return true;
            } catch (_) {
                return false;
            }
        }
    };

    // =========================================================================
    // UNIVERSAL IN-APP APK SELF-UPDATER ENGINE (ANDROID APK v146)
    // - Auto-checks GitHub Releases (latest-apks/update-<role>.json) natively (Zero CORS!)
    // - Downloads signed APK inside the app with live progress bar & launches Android installer
    // - Auto-resumes installer right after user enables "Install unknown apps" permission
    // =========================================================================
    let __nfUpdateManualMode = false;
    let __nfUpdateRemoteData = null;
    let __nfUpdateAwaitingInstallPerm = false;
    let __nfUpdateDownloadingFlag = false;

    function getLocalApkVersionInfo() {
        if (!isAndroidNative() || typeof window.NfAndroidNative.getAppVersionJson !== "function") {
            return null;
        }
        try {
            return JSON.parse(window.NfAndroidNative.getAppVersionJson() || "{}");
        } catch (_) {
            return null;
        }
    }

    function showUpdateNoticeToast(msg) {
        if (typeof showNfBackToast === "function") {
            showNfBackToast(msg);
        } else {
            alert(msg);
        }
    }

    function renderAppUpdateModal(localInfo, remoteInfo) {
        __nfUpdateRemoteData = remoteInfo;
        __nfUpdateDownloadingFlag = false;
        __nfUpdateAwaitingInstallPerm = false;

        const isDark = document.documentElement.getAttribute("data-theme") === "dark" ||
            document.body.classList.contains("nf-office-page");
        const isForce = !!remoteInfo.force;

        document.getElementById("nfAppUpdateModal")?.remove();
        const modal = document.createElement("div");
        modal.id = "nfAppUpdateModal";
        modal.dataset.locked = isForce ? "1" : "0";
        modal.style.cssText = "position:fixed;inset:0;z-index:100040;background:rgba(15,23,42,.72);backdrop-filter:blur(8px);display:flex;align-items:center;justify-content:center;padding:16px;font-family:Inter,system-ui,sans-serif;";
        if (!isForce) {
            modal.addEventListener("click", (e) => {
                if (e.target === modal && !__nfUpdateDownloadingFlag) {
                    dismissAppUpdateModal(remoteInfo.versionCode);
                }
            });
        }

        const cardBg = isDark ? "#111827" : "#ffffff";
        const cardBorder = isDark ? "rgba(255,255,255,.16)" : "#e2e8f0";
        const textMain = isDark ? "#f8fafc" : "#0f172a";
        const textSub = isDark ? "#94a3b8" : "#475569";
        const noteBg = isDark ? "rgba(30,41,59,.85)" : "#f8fafc";

        modal.innerHTML = `
            <div style="width:100%;max-width:390px;background:${cardBg};border:1px solid ${cardBorder};border-radius:28px;overflow:hidden;box-shadow:0 26px 64px rgba(0,0,0,.48);">
                <div style="background:linear-gradient(135deg,#558b2f,#0f766e);padding:18px 20px;color:#fff;position:relative;">
                    <div style="display:flex;align-items:center;gap:12px;">
                        <div style="width:42px;height:42px;border-radius:14px;background:rgba(255,255,255,.2);display:flex;align-items:center;justify-content:center;font-size:19px;flex-shrink:0;">
                            <i class="fa-solid fa-cloud-arrow-down"></i>
                        </div>
                        <div style="min-width:0;">
                            <div style="font-size:10px;font-weight:900;text-transform:uppercase;letter-spacing:.06em;opacity:.9;">${isForce ? 'Pembaruan Wajib' : 'Pembaruan Tersedia'}</div>
                            <div style="font-size:16px;font-weight:900;line-height:1.25;margin-top:1px;">Versi Baru NutriFresh Siap!</div>
                        </div>
                    </div>
                    <div style="margin-top:12px;display:inline-flex;align-items:center;gap:8px;padding:5px 11px;border-radius:999px;background:rgba(0,0,0,.22);font-size:11px;font-weight:800;">
                        <span>v${escapeHtml(localInfo?.versionName || '1.0')}</span>
                        <i class="fa-solid fa-arrow-right" style="font-size:10px;opacity:.85;"></i>
                        <span style="color:#d9f99d;">v${escapeHtml(remoteInfo.versionName || '')}</span>
                    </div>
                </div>
                <div style="padding:16px 18px;space-y:12px;">
                    <div style="padding:11px 13px;border-radius:16px;background:${noteBg};border:1px solid ${cardBorder};">
                        <div style="font-size:10.5px;font-weight:900;color:#558b2f;text-transform:uppercase;letter-spacing:.04em;margin-bottom:4px;">Yang Baru di Versi Ini:</div>
                        <div style="font-size:12px;color:${textMain};line-height:1.45;white-space:pre-line;">${escapeHtml(remoteInfo.notes || 'Pembaruan fitur terbaru, notifikasi lebih cepat, dan perbaikan stabilitas.')}</div>
                    </div>
                    <div style="margin-top:10px;font-size:11px;color:${textSub};line-height:1.4;">
                        <i class="fa-solid fa-shield-halved" style="color:#16a34a;margin-right:4px;"></i>
                        Update langsung menimpa aplikasi — <strong>tidak perlu uninstall</strong>, akun &amp; data Anda tetap aman.
                    </div>
                    <div id="nfUpdProgressWrap" style="display:none;margin-top:13px;">
                        <div style="height:8px;border-radius:999px;background:${isDark ? '#1e293b' : '#e2e8f0'};overflow:hidden;">
                            <div id="nfUpdProgressBar" style="width:4%;height:100%;border-radius:999px;background:linear-gradient(90deg,#7cb342,#10b981);transition:width .25s ease;"></div>
                        </div>
                        <div id="nfUpdStatusText" style="margin-top:6px;font-size:11px;font-weight:800;color:${textMain};text-align:center;">Menyiapkan unduhan...</div>
                    </div>
                    <div id="nfUpdPermHint" style="display:none;margin-top:10px;padding:9px 11px;border-radius:14px;background:${isDark ? 'rgba(245,158,11,.16)' : '#fffbeb'};border:1px solid ${isDark ? 'rgba(251,191,36,.38)' : '#fde68a'};color:${isDark ? '#fde68a' : '#78350f'};font-size:11px;line-height:1.4;">
                        <strong>Izin 1 Kali Saja:</strong> Aktifkan saklar <em>"Izinkan dari sumber ini"</em> di layar pengaturan Android, lalu tekan tombol <strong>Kembali</strong> — pembaruan akan lanjut otomatis!
                    </div>
                </div>
                <div style="padding:0 18px 18px;display:flex;flex-direction:column;gap:8px;">
                    <button type="button" id="nfUpdPrimaryBtn" style="width:100%;padding:12px 16px;border-radius:999px;border:none;background:linear-gradient(135deg,#7cb342,#558b2f);color:#fff;font-size:13px;font-weight:900;cursor:pointer;box-shadow:0 8px 20px -6px rgba(85,139,47,.55);">
                        <i class="fa-solid fa-download" style="margin-right:6px;"></i> Perbarui Sekarang
                    </button>
                    <button type="button" id="nfUpdBrowserFallbackBtn" style="display:none;width:100%;padding:10px 14px;border-radius:999px;border:1px solid ${cardBorder};background:transparent;color:${textMain};font-size:11.5px;font-weight:800;cursor:pointer;">
                        <i class="fa-solid fa-arrow-up-right-from-square" style="margin-right:5px;"></i> Unduh lewat Browser
                    </button>
                    ${isForce ? '' : `<button type="button" id="nfUpdLaterBtn" style="width:100%;padding:9px 14px;border-radius:999px;border:none;background:transparent;color:${textSub};font-size:11.5px;font-weight:800;cursor:pointer;">Nanti Saja</button>`}
                </div>
            </div>`;

        document.body.appendChild(modal);

        const primaryBtn = modal.querySelector("#nfUpdPrimaryBtn");
        const laterBtn = modal.querySelector("#nfUpdLaterBtn");
        const browserBtn = modal.querySelector("#nfUpdBrowserFallbackBtn");

        primaryBtn.onclick = () => {
            if (__nfUpdateAwaitingInstallPerm) {
                if (typeof window.NfAndroidNative.openInstallUnknownAppsSettings === "function") {
                    window.NfAndroidNative.openInstallUnknownAppsSettings();
                }
                return;
            }
            if (__nfUpdateDownloadingFlag) return;
            __nfUpdateDownloadingFlag = true;
            modal.dataset.locked = "1";
            primaryBtn.disabled = true;
            primaryBtn.style.opacity = "0.65";
            primaryBtn.innerHTML = `<i class="fa-solid fa-spinner fa-spin" style="margin-right:6px;"></i> Mengunduh Pembaruan...`;
            if (laterBtn) laterBtn.style.display = "none";
            const progWrap = modal.querySelector("#nfUpdProgressWrap");
            if (progWrap) progWrap.style.display = "block";
            window.NfAndroidNative.downloadAndInstallUpdate(remoteInfo.apkUrl || "");
        };

        if (laterBtn) {
            laterBtn.onclick = () => dismissAppUpdateModal(remoteInfo.versionCode);
        }
        if (browserBtn) {
            browserBtn.onclick = () => openExternalNative(remoteInfo.apkUrl || "");
        }
    }

    function dismissAppUpdateModal(versionCode) {
        const el = document.getElementById("nfAppUpdateModal");
        if (el) el.remove();
        __nfUpdateDownloadingFlag = false;
        __nfUpdateAwaitingInstallPerm = false;
        if (versionCode) {
            try {
                localStorage.setItem("nf_upd_dismissed_ver", String(versionCode));
                localStorage.setItem("nf_upd_dismissed_at", String(Date.now()));
            } catch (_) {}
        }
    }

    window.__nfOnUpdateCheckResult = function (rawJsonStr) {
        const wasManual = __nfUpdateManualMode;
        __nfUpdateManualMode = false;
        try {
            const parsed = JSON.parse(rawJsonStr || "{}");
            if (!parsed.ok || !parsed.remote) {
                if (wasManual) {
                    showUpdateNoticeToast(parsed.error || "Belum ada rilis update terbaru.");
                }
                return;
            }
            const remote = parsed.remote;
            const local = getLocalApkVersionInfo() || { versionCode: 0, versionName: "1.0" };
            const remoteCode = Number(remote.versionCode) || 0;
            const localCode = Number(local.versionCode) || 0;

            if (remoteCode > localCode && remote.apkUrl) {
                if (!wasManual && !remote.force) {
                    const lastVer = Number(localStorage.getItem("nf_upd_dismissed_ver") || "0");
                    const lastAt = Number(localStorage.getItem("nf_upd_dismissed_at") || "0");
                    if (lastVer === remoteCode && lastAt && (Date.now() - lastAt) < 12 * 60 * 60 * 1000) {
                        return;
                    }
                }
                renderAppUpdateModal(local, remote);
            } else if (wasManual) {
                showUpdateNoticeToast(`Aplikasi sudah versi terbaru (v${local.versionName || '1.51'}) ✓`);
            }
        } catch (_) {
            if (wasManual) showUpdateNoticeToast("Gagal membaca info versi terbaru.");
        }
    };

    window.__nfOnUpdateProgress = function (percent, status, message) {
        const modal = document.getElementById("nfAppUpdateModal");
        if (!modal) return;
        const bar = modal.querySelector("#nfUpdProgressBar");
        const txt = modal.querySelector("#nfUpdStatusText");
        const primaryBtn = modal.querySelector("#nfUpdPrimaryBtn");
        const permHint = modal.querySelector("#nfUpdPermHint");
        const browserBtn = modal.querySelector("#nfUpdBrowserFallbackBtn");
        const laterBtn = modal.querySelector("#nfUpdLaterBtn");

        if (bar && typeof percent === "number") bar.style.width = Math.max(4, Math.min(100, percent)) + "%";
        if (txt && message) txt.textContent = message;

        if (status === "NEED_PERMISSION") {
            __nfUpdateDownloadingFlag = false;
            __nfUpdateAwaitingInstallPerm = true;
            if (permHint) permHint.style.display = "block";
            if (primaryBtn) {
                primaryBtn.disabled = false;
                primaryBtn.style.opacity = "1";
                primaryBtn.style.background = "linear-gradient(135deg,#f59e0b,#ea580c)";
                primaryBtn.innerHTML = `<i class="fa-solid fa-unlock-keyhole" style="margin-right:6px;"></i> Izinkan Pasang Aplikasi`;
            }
        } else if (status === "INSTALLING") {
            __nfUpdateDownloadingFlag = false;
            __nfUpdateAwaitingInstallPerm = false;
            if (permHint) permHint.style.display = "none";
            if (primaryBtn) {
                primaryBtn.disabled = false;
                primaryBtn.style.opacity = "1";
                primaryBtn.innerHTML = `<i class="fa-solid fa-rotate-right" style="margin-right:6px;"></i> Buka Pemasang Lagi`;
                primaryBtn.onclick = () => {
                    if (typeof window.NfAndroidNative.installDownloadedUpdate === "function") {
                        window.NfAndroidNative.installDownloadedUpdate();
                    }
                };
            }
            if (laterBtn && !(__nfUpdateRemoteData && __nfUpdateRemoteData.force)) {
                laterBtn.style.display = "block";
                modal.dataset.locked = "0";
            }
        } else if (status === "ERROR") {
            __nfUpdateDownloadingFlag = false;
            __nfUpdateAwaitingInstallPerm = false;
            modal.dataset.locked = (__nfUpdateRemoteData && __nfUpdateRemoteData.force) ? "1" : "0";
            if (primaryBtn) {
                primaryBtn.disabled = false;
                primaryBtn.style.opacity = "1";
                primaryBtn.innerHTML = `<i class="fa-solid fa-rotate-right" style="margin-right:6px;"></i> Coba Unduh Lagi`;
            }
            if (browserBtn) browserBtn.style.display = "block";
            if (laterBtn && !(__nfUpdateRemoteData && __nfUpdateRemoteData.force)) {
                laterBtn.style.display = "block";
            }
        }
    };

    function resumePendingApkInstallIfAllowed() {
        if (!__nfUpdateAwaitingInstallPerm || !isAndroidNative()) return;
        try {
            if (typeof window.NfAndroidNative.canInstallUnknownApps === "function" && window.NfAndroidNative.canInstallUnknownApps()) {
                __nfUpdateAwaitingInstallPerm = false;
                if (typeof window.NfAndroidNative.installDownloadedUpdate === "function") {
                    window.NfAndroidNative.installDownloadedUpdate();
                }
            }
        } catch (_) {}
    }

    document.addEventListener("visibilitychange", () => {
        if (!document.hidden) resumePendingApkInstallIfAllowed();
    });
    window.addEventListener("focus", () => {
        resumePendingApkInstallIfAllowed();
    });

    window.nfUpdater = {
        getLocalInfo: getLocalApkVersionInfo,
        check(manual = false) {
            if (!isAndroidNative() || typeof window.NfAndroidNative.checkAppUpdateAsync !== "function") {
                if (manual) showUpdateNoticeToast("Update otomatis APK khusus untuk aplikasi Android (.apk).");
                return false;
            }
            __nfUpdateManualMode = !!manual;
            if (manual) showUpdateNoticeToast("Memeriksa versi terbaru...");
            window.NfAndroidNative.checkAppUpdateAsync("");
            return true;
        }
    };

    // Tampilkan elemen tombol khusus Android APK (.nf-android-only) & jalankan cek update otomatis 4.5 detik setelah buka APK
    function revealAndroidOnlyElements() {
        if (!isAndroidNative()) return;
        document.querySelectorAll(".nf-android-only").forEach((el) => {
            el.classList.remove("hidden");
        });
    }
    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", revealAndroidOnlyElements);
    } else {
        revealAndroidOnlyElements();
    }
    if (isAndroidNative()) {
        setTimeout(() => {
            if (window.nfUpdater) window.nfUpdater.check(false);
        }, 4500);
    }

    // =========================================================================
    // SAFE NATIVE PRINT / SAVE-AS-PDF HELPER (ANTI-WHITE-SCREEN TRAP IN APK v148)
    // =========================================================================
    window.nfPrintHtmlSafe = function (jobName, htmlContent) {
        const safeName = String(jobName || "NutriFresh_Dokumen").trim();
        const html = String(htmlContent || "");

        // 1. Android APK v148+: Cetak/Simpan PDF via Native PrintManager (WebView tersembunyi — layar app 100% aman!)
        if (isAndroidNative()) {
            if (typeof window.NfAndroidNative.printHtmlDocument === "function") {
                try {
                    window.NfAndroidNative.printHtmlDocument(safeName, html);
                    return true;
                } catch (_) {}
            }
            // Fallback aman jika masih APK lama (< v148): JANGAN pernah panggil window.open('', '_blank')!
            document.getElementById("nfSafeDocPreviewModal")?.remove();
            const wrap = document.createElement("div");
            wrap.id = "nfSafeDocPreviewModal";
            wrap.style.cssText = "position:fixed;inset:0;z-index:100050;background:rgba(15,23,42,.78);backdrop-filter:blur(6px);display:flex;align-items:center;justify-content:center;padding:14px;font-family:Inter,system-ui,sans-serif;";
            wrap.innerHTML = `
                <div style="width:100%;max-width:440px;max-height:88vh;background:#fff;border-radius:24px;overflow:hidden;display:flex;flex-direction:column;box-shadow:0 24px 60px rgba(0,0,0,.45);">
                    <div style="padding:12px 16px;background:#0f172a;color:#fff;display:flex;align-items:center;justify-content:space-between;gap:8px;">
                        <span style="font-size:13px;font-weight:900;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${escapeHtml(safeName)}</span>
                        <button type="button" id="nfSafeDocClose" style="background:rgba(255,255,255,.2);border:none;color:#fff;padding:5px 12px;border-radius:999px;font-size:11.5px;font-weight:900;cursor:pointer;">Tutup ✕</button>
                    </div>
                    <iframe id="nfSafeDocFrame" style="flex:1;width:100%;min-height:420px;border:none;background:#fff;"></iframe>
                    <div style="padding:10px 14px;background:#f8fafc;border-top:1px solid #e2e8f0;font-size:11px;color:#475569;text-align:center;">
                        Untuk simpan langsung jadi PDF, perbarui aplikasi ke versi terbaru (<strong>v1.48+</strong>) lewat menu Cek Update APK.
                    </div>
                </div>`;
            document.body.appendChild(wrap);
            const fr = wrap.querySelector("#nfSafeDocFrame");
            if (fr) fr.srcdoc = html;
            wrap.querySelector("#nfSafeDocClose").onclick = () => wrap.remove();
            wrap.addEventListener("click", (e) => { if (e.target === wrap) wrap.remove(); });
            return true;
        }

        // 2. Browser Web / PC Desktop: Gunakan iframe tersembunyi agar tidak pernah diblokir pop-up
        try {
            const oldFrame = document.getElementById("nfHiddenPrintFrame");
            if (oldFrame) oldFrame.remove();
            const iframe = document.createElement("iframe");
            iframe.id = "nfHiddenPrintFrame";
            iframe.style.cssText = "position:fixed;right:0;bottom:0;width:0;height:0;border:0;visibility:hidden;";
            document.body.appendChild(iframe);
            const doc = iframe.contentWindow && iframe.contentWindow.document;
            if (doc) {
                doc.open();
                doc.write(html);
                doc.close();
                setTimeout(() => {
                    try {
                        iframe.contentWindow.focus();
                        iframe.contentWindow.print();
                    } catch (_) {}
                    setTimeout(() => { if (iframe.parentNode) iframe.remove(); }, 3000);
                }, 260);
                return true;
            }
        } catch (_) {}

        try { window.print(); } catch (_) {}
        return false;
    };

    // =========================================================================
    // NATIVE FCM FOREGROUND & RESUME BRIDGE (ZERO-DUPLICATE + INSTANT REFRESH v148)
    // =========================================================================
    window.__nfOnPushReceived = function (rawJsonStr) {
        try {
            const p = typeof rawJsonStr === "string" ? JSON.parse(rawJsonStr || "{}") : (rawJsonStr || {});
            const title = String(p.title || "NutriFresh");
            const body = String(p.body || "");
            const eventType = String(p.eventType || "general");
            const refId = String(p.refId || "");
            const realApp = getReadyApp();

            // 1. Langsung segarkan data di halaman aktif (< 1 detik tanpa tunggu polling!)
            if (document.getElementById("customerView") && realApp && typeof realApp.refreshCustomerOrders === "function") {
                realApp.refreshCustomerOrders(false, true);
            } else if (window.staffApp && typeof window.staffApp.loadAllData === "function") {
                window.staffApp.loadAllData();
            }


            // 2. Jika pelanggan sedang menatap layar Pesanan Saya, cukup bunyikan chime lembut tanpa banner menumpuk
            const custOrdModal = document.getElementById("customerOrdersModal");
            const isViewingCustOrders = !!(custOrdModal && !custOrdModal.classList.contains("hidden"));
            if (isViewingCustOrders && (eventType === "chat" || eventType === "order_status")) {
                playChime("status");
                return;
            }

            // 3. Tampilkan 1 banner in-app bersih (tag seragam dengan polling agar tidak pernah dobel!)
            const unifiedTag = eventType === "chat"
                ? `ord-chat-${refId || p.outboxId || "gen"}`
                : `ord-${refId || p.outboxId || "gen"}`;
            if (window.nfNotify) {
                window.nfNotify.send({
                    title,
                    body,
                    tag: unifiedTag,
                    sound: eventType === "order_status" ? "order" : "status",
                    onClick: () => {
                        if (window.__nfOpenOrderFromNotif) window.__nfOpenOrderFromNotif(refId);
                    }
                });
            }
        } catch (_) {}
    };

    window.__nfOnAppResume = function () {
        try {
            const realApp = getReadyApp();
            if (document.getElementById("customerView") && realApp && typeof realApp.refreshCustomerOrders === "function") {
                realApp.refreshCustomerOrders(false, true);
            } else if (window.staffApp && typeof window.staffApp.loadAllData === "function") {
                window.staffApp.loadAllData();
            }
        } catch (_) {}
    };

    window.__nfOpenOrderFromNotif = function (orderId) {
        try {
            const realApp = getReadyApp();
            if (document.getElementById("customerView") && realApp && typeof realApp.openCustomerOrdersModal === "function") {
                realApp.openCustomerOrdersModal("active");
                return;
            }
            if (document.getElementById("posSearch") && realApp && typeof realApp.openOnlineOrdersModal === "function") {
                realApp.openOnlineOrdersModal();
                return;
            }
            if (window.staffApp && typeof window.staffApp.switchTab === "function") {
                if (orderId && String(orderId).startsWith("ORD-")) {
                    window.staffApp.switchTab("antaran");
                } else {
                    window.staffApp.switchTab("absensi");
                }
            }
        } catch (_) {}
    };
})();
