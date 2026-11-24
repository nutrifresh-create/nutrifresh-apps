# NutriFresh POS v1.1 Pro — PC Windows (.exe) & Tablet Android (.apk)

Aplikasi kasir & operasional toko buah NutriFresh berbasis **Flutter Native** dengan tata letak padat & berwarna ala `pos.html`, animasi halus (*spring press*, transisi tab, *shimmer* foto, angka Rupiah bergulir), kamera scanner Barcode PLU & QR Member, cetak langsung **Windows & Bluetooth (ESC/POS + TSPL)**, serta sinkronisasi real-time ke **Supabase PostgreSQL**.

## Pembaruan Utama di v1.1 Pro
1. **Tata Letak Padat & Berwarna (Setara `pos.html`):** Grid etalase otomatis 3–4 kolom di PC/Tablet, sidebar warna khas per menu lengkap dengan kartu **Kas Laci + Kas Out + Tutup Shift**, 4 pil mode pembeli berwarna (*Reguler, Member, Staf, Reseller*), serta pilihan Kanal Penjualan & Nama Pelanggan di keranjang.
2. **Kamera Scanner Barcode PLU & QR Member (`mobile_scanner`):** Tombol biru **Scan** di Kasir, tombol scan QR di kolom pencarian Member, tombol scan di filter Stok, dan tombol scan barcode kemasan di form Tambah/Edit Produk (di PC Windows langsung mendukung *Barcode Scanner USB*).
3. **Animasi Halus:** Efek tekan membal (*press scale*), transisi perpindahan tab (*fade+slide*), animasi angka Rupiah bergulir, dan *shimmer* saat foto dimuat.
4. **Form Produk 100% Lengkap:** Unggah foto produk langsung dari **Kamera Tablet / Galeri / File PC** ke Supabase Storage (`nutrifresh-media`), tombol **Auto-Generate PLU**, **Stok Minimal**, **Promo Paket/Bundle**, sakelar **Tampil di Katalog**, dan penanda **Obral**.
5. **Produksi Dapur dengan Pencarian Bahan Instan:** Ketik 2–3 huruf nama buah atau kemasan untuk langsung mencari & menambahkan bahan lengkap dengan sisa stok dan kalkulasi HPP otomatis.
6. **Perbaikan Build Android GitHub Actions:** Workflow otomatis membersihkan ruang disk runner Ubuntu sebelum ekstrak Android NDK agar build `.apk` stabil.

## Cara Update di GitHub Desktop (1× Upload)
1. Ekstrak **`NutriFresh_Flutter_POS_v1.1_Pro.zip`** (pastikan *Hidden items* di Windows Explorer aktif agar folder `.github` ikut terpilih).
2. Salin & timpa (**Replace all**) seluruh isinya ke dalam folder repository `nutrifresh-apps`.
3. Buka **GitHub Desktop**, isi Summary `Upgrade NutriFresh POS v1.1 Pro`, klik **Commit to main**, lalu klik **Push origin**.
4. Buka tab **Actions** di web GitHub → tunggu ±5–8 menit hingga kedua job (`.exe` & `.apk`) centang hijau → unduh di bagian **Artifacts**.
