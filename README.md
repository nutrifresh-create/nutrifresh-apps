# NutriFresh POS v1.0 — Native PC Windows (.exe) & Tablet Android (.apk)

Aplikasi kasir & operasional toko buah NutriFresh berbasis **Flutter Native** dengan tampilan **True iOS 26 Liquid Glass & Natural**, font **Inter**, ikon & logo resmi tertanam lokal, cetak langsung **Windows Print Spooler & Bluetooth ESC/POS + TSPL**, serta sinkronisasi real-time ke **Supabase PostgreSQL** (`nutrifresh.my.id`).

## Fitur Lengkap v1.0
1. **Kasir Adaptif (PC & Tablet):** 2 kolom layar lebar + shortcut `F2` Bayar / `F4` Tahan Nota, scan barcode PLU, 4 mode pembeli (Reguler, Member + potong poin, Karyawan, Reseller), Buka/Tutup Shift (auto-setor ke Buku Kas Office).
2. **Antrean Order Online (Skema A):** Notifikasi real-time, 1 klik muat ke kasir, koreksi berat timbangan riil, dan kirim tagihan (+ ongkir) ke aplikasi pelanggan.
3. **Papan PO Parsel:** Input PO Parsel Manual (pilihan #1 *Parcel Keranjang*), catat DP/Lunas, salin rekap WA tim perakit, cetak stiker PO langsung, dan selesaikan pembayaran ke kasir.
4. **Stok & Dapur:** Tambah/edit produk, Kulakan (Lunas/Tempo), Timbang Ulang/Opname, Catat Buah Rusak, Pecah Grade/Obral, **Edit Harga Cepat Massal**, **Produksi Dapur (Jus/Parsel + HPP otomatis)**, Kartu Stok, Cetak Barcode Satuan/Massal, dan Unduh Label PNG.
5. **Laporan 4 Sub-Tab:** Penjualan (Cetak, Resi PNG/WA, Retur, VOID), Kas Keluar, Kulakan, dan Buah Rusak/Susut.
6. **Pengaturan Lengkap (PIN Owner):** Pilih Printer Bluetooth (ESC/POS & TSPL) / Printer Windows + Tes Cetak, Tema Liquid Glass vs Natural, Identitas Cabang (`cabang-1`), Master Supplier, Master Reseller, Promo Poin, dan Banner Katalog.

## Cara Update di GitHub Desktop (1× Upload)
1. Ekstrak **`NutriFresh_Flutter_POS_v1.0.zip`** → salin & timpa (**Replace all**) seluruh isinya ke folder repository `nutrifresh-apps` Anda (pastikan folder `.github` ikut tertimpa).
2. Di GitHub Desktop, ketik Summary **`Release NutriFresh POS v1.0`**, klik **Commit to main**, lalu klik **Push origin**.
3. Buka tab **Actions** di web GitHub → tunggu ±5–8 menit hingga centang hijau → unduh **`NutriFresh_POS_Windows_EXE`** dan **`NutriFresh_POS_Tablet_APK`** di bagian **Artifacts**.
