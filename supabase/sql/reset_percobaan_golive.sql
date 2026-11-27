-- =========================================================================
-- NUTRIFRESH — SKRIP RESET DATA PERCOBAAN (SIAP GO-LIVE RESMI)
-- Jalankan HANYA KETIKA Anda siap menghapus seluruh data uji coba
-- dan memulai pembukuan toko resmi dari 0 (TANPA perlu update aplikasi!).
--
-- YANG TETAP AMAN & TIDAK DIHAPUS:
--   ✓ Master Produk & Foto Katalog (nf_inventory)
--   ✓ Data Karyawan & PIN (nf_employees, nf_staff_roles)
--   ✓ Pengaturan Toko, Banner, QRIS & Keamanan (nf_settings, nf_office_config)
--   ✓ Daftar Supplier & Hadiah Poin (nf_suppliers, nf_point_rewards)
--   ✓ Token Push Notifikasi HP (nf_push_devices)
-- =========================================================================

TRUNCATE TABLE
    public.nf_transactions,
    public.nf_online_orders,
    public.nf_parcel_orders,
    public.nf_shift_logs,
    public.nf_expenses,
    public.nf_purchases,
    public.nf_waste_logs,
    public.nf_supply_usages,
    public.nf_stock_movements,
    public.nf_attendance,
    public.nf_office_cashbook,
    public.nf_office_debts,
    public.nf_office_hr_requests,
    public.nf_office_payroll,
    public.nf_point_ledger,
    public.nf_member_vouchers,
    public.nf_audit_logs,
    public.nf_push_outbox,
    public.nf_error_logs
RESTART IDENTITY;

-- Reset saldo poin & total belanja member percobaan kembali ke 0
-- (Atau hapus baris DELETE di bawah ini jika ingin member uji coba ikut terhapus)
UPDATE public.nf_members
SET points = 0, visits = 0, total_spend = 0,
    data = COALESCE(data, '{}'::jsonb) || '{"points":0,"visits":0,"totalSpend":0}'::jsonb;

-- Bersihkan status shift kasir yang masih terbuka dari masa percobaan
DELETE FROM public.nf_settings WHERE id = 'active_shift_state';

NOTIFY pgrst, 'reload schema';
