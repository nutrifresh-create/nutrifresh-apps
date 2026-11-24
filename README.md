# NutriFresh Native Ecosystem — Tahap 1: NutriFresh POS (PC `.exe` & Tablet `.apk`)

Proyek monorepo Flutter resmi untuk aplikasi native NutriFresh yang terhubung real-time ke **Supabase PostgreSQL** (`dsidhlpgdanmgndrbksx.supabase.co`), 100% sinkron dengan website `nutrifresh.my.id`.

## Struktur Monorepo
- `packages/nf_core/` — Fondasi bersama (koneksi Supabase, model data, format Rupiah/Gram, disk-cache foto hemat Egress, tema Natural/Glass & Dark Office).
- `apps/nutrifresh_pos/` — Aplikasi **NutriFresh POS** (1 basis kode untuk **Windows `.exe`** dan **Tablet Android `.apk`**).
- `.github/workflows/build_pos.yml` — Alur **GitHub Actions Auto-Build** (gratis) untuk mengompilasi `.exe` dan `.apk` otomatis di cloud.

---

## Langkah 1 — Tambahkan 2 Redirect URL Login Google di Supabase (Cukup 1x Saja)
Agar tombol **Masuk dengan Akun Google** berjalan di aplikasi Windows `.exe` maupun Tablet Android `.apk`:
1. Buka **Supabase Dashboard** → menu **Authentication** → **URL Configuration**.
2. Di bagian **Redirect URLs**, klik **Add URL** dan tambahkan 2 baris ini:
   - `http://localhost:43821/auth-callback`
   - `id.my.nutrifresh.pos://login-callback`
3. Klik **Save**.

---

## Langkah 2 — Upload Proyek Ini ke Repository GitHub Anda
1. Login ke [github.com](https://github.com) → klik **New repository** (nama misal: `nutrifresh-apps`, pilih **Private** agar kode internal aman).
2. Ekstrak file ZIP ini di komputer Anda.
3. Unggah seluruh isi folder `nutrifresh_apps/` (termasuk folder `.github`, `packages`, `apps`, `scripts`, dan `README.md`) ke branch **`main`** repository tersebut (bisa lewat **GitHub Desktop** agar folder tersembunyi `.github` pasti ikut terunggah).

---

## Langkah 3 — Unduh File `.exe` (Windows) dan `.apk` (Tablet Android)
1. Buka tab **Actions** di halaman repository GitHub Anda.
2. Klik workflow **Build NutriFresh POS (.exe & .apk)** yang sedang berjalan (atau klik **Run workflow**).
3. Tunggu ±5–8 menit hingga kedua job (**Build Windows PC (.exe)** & **Build Android Tablet (.apk)**) bertanda centang hijau.
4. Gulir ke bagian **Artifacts** di halaman workflow tersebut, lalu unduh:
   - **`NutriFresh_POS_Windows_EXE`** → ekstrak ZIP di PC kasir, lalu jalankan **`nutrifresh_pos.exe`**.
   - **`NutriFresh_POS_Tablet_APK`** → salin & instal **`NutriFresh_POS_Tablet.apk`** di Tablet Android toko.
