# NutriFresh Native Ecosystem (Opsi B — Tauri Desktop + Capacitor Android + Cloudflare Pages)

Sumber kode tunggal **NutriFresh v133** yang otomatis membangun:
1. **`NutriFresh_POS.exe`** (PC Kasir Windows — 1 file `.exe` mandiri ~6 MB, Direct Print Windows USB/BT tanpa pop-up, tanpa tab Absensi).
2. **`NutriFresh_Office.exe`** (PC Owner/HR Windows Dark — 1 file `.exe` mandiri ~6 MB terpisah dari kasir).
3. **`NutriFresh_POS_Tablet.apk`** (Tablet/HP Android — Direct Print Bluetooth ESC/POS & TSPL tanpa pop-up + Kamera Scanner Barcode PLU & QR Member).
4. **Website `nutrifresh.my.id`** (untuk pengguna **iPhone** & browser — cukup sambungkan folder `web/` ke Cloudflare Pages 1× saja).

---

## Cara Upload ke GitHub Desktop (Setelah Folder Dibersihkan)
1. Pastikan isi lama folder `nutrifresh-apps` sudah dihapus (**KECUALI folder tersembunyi `.git`**, jangan dihapus!).
2. Ekstrak **`NutriFresh_Hybrid_Stage1_POS_Office.zip`**, aktifkan *Hidden items* di Windows Explorer agar `.github` & `.gitignore` ikut terpilih, lalu salin semua isinya ke dalam folder `nutrifresh-apps`.
3. Di **GitHub Desktop**, isi Summary `Migrasi Opsi B - POS & Office Native v133`, klik **Commit to main**, lalu klik **Push origin**.
4. Buka tab **Actions** di web GitHub — akan jalan 2 workflow paralel (±3–5 menit):
   - **Build NutriFresh Desktop (.exe POS & Office)** → unduh **`NutriFresh_POS_Windows_EXE`** (`NutriFresh_POS.exe`) dan **`NutriFresh_Office_Windows_EXE`** (`NutriFresh_Office.exe`).
   - **Build NutriFresh POS Tablet (.apk)** → unduh **`NutriFresh_POS_Tablet_APK`** (`NutriFresh_POS_Tablet.apk`).

---

## Cara Sambungkan GitHub ke Cloudflare Pages (Cukup 1× — Tidak Perlu Upload Web Manual Lagi!)
1. Buka **Cloudflare Dashboard → Workers & Pages → Create → Pages → Connect to Git**.
2. Pilih repository GitHub **`nutrifresh-apps`**.
3. Isi pengaturan build seperti ini:
   - **Production branch:** `main`
   - **Framework preset:** `None`
   - **Build command:** *(kosongkan)*
   - **Build output directory:** `web`
4. Klik **Save and Deploy**, lalu sambungkan custom domain **`nutrifresh.my.id`**.
5. Selesai! Mulai saat itu, setiap kali Anda menekan **Push origin** di GitHub Desktop, website `nutrifresh.my.id` untuk pengguna iPhone & browser otomatis terbarui dalam ±30 detik bersamaan dengan build `.exe` dan `.apk`.
