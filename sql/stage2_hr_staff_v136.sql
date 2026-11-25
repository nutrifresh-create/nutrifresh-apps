-- ============================================================================
-- NUTRIFRESH TAHAP 2 (v136): HR+ OFFICE & APLIKASI NUTRIFRESH STAFF
-- Aman dijalankan berulang kali (IF NOT EXISTS / CREATE OR REPLACE).
-- Tidak menghapus atau mengubah data lama.
-- ============================================================================

-- 1. Helper otorisasi internal (mandiri agar tidak bergantung nama helper lama)
CREATE OR REPLACE FUNCTION public.nf_s2_current_email()
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT lower(trim(coalesce(auth.jwt() ->> 'email', '')));
$$;

CREATE OR REPLACE FUNCTION public.nf_s2_is_owner(p_tenant_id text DEFAULT 'nutrifresh')
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.nf_settings s
        WHERE s.tenant_id = p_tenant_id
          AND s.id IN ('security_config', 'store_settings')
          AND lower(trim(coalesce(s.data ->> 'ownerEmail', ''))) <> ''
          AND lower(trim(coalesce(s.data ->> 'ownerEmail', ''))) = public.nf_s2_current_email()
    );
$$;

CREATE OR REPLACE FUNCTION public.nf_s2_is_staff(p_tenant_id text DEFAULT 'nutrifresh')
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.nf_s2_is_owner(p_tenant_id)
        OR EXISTS (
            SELECT 1
            FROM public.nf_employees e
            WHERE e.tenant_id = p_tenant_id
              AND lower(trim(coalesce(e.email, e.data ->> 'email', ''))) = public.nf_s2_current_email()
              AND coalesce(e.status, e.data ->> 'status', 'Aktif') <> 'Non-Aktif'
        );
$$;

CREATE OR REPLACE FUNCTION public.nf_s2_is_hr_or_owner(p_tenant_id text DEFAULT 'nutrifresh')
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.nf_s2_is_owner(p_tenant_id)
        OR EXISTS (
            SELECT 1
            FROM public.nf_employees e
            WHERE e.tenant_id = p_tenant_id
              AND lower(trim(coalesce(e.email, e.data ->> 'email', ''))) = public.nf_s2_current_email()
              AND coalesce(e.status, e.data ->> 'status', 'Aktif') <> 'Non-Aktif'
              AND (
                  lower(coalesce(e.role, e.data ->> 'role', '')) LIKE '%hr%'
                  OR lower(coalesce(e.role, e.data ->> 'role', '')) LIKE '%sdm%'
                  OR lower(coalesce(e.role, e.data ->> 'role', '')) LIKE '%kepala toko%'
                  OR lower(coalesce(e.role, e.data ->> 'role', '')) LIKE '%owner%'
              )
        );
$$;

-- 2. Tambah kolom foto bukti absensi (masuk & pulang) di nf_attendance
ALTER TABLE IF EXISTS public.nf_attendance
    ADD COLUMN IF NOT EXISTS photo_in_url text,
    ADD COLUMN IF NOT EXISTS photo_out_url text;

-- RPC aman bagi karyawan untuk menempelkan URL foto terkompresi ke baris absensinya sendiri
CREATE OR REPLACE FUNCTION public.nf_attach_attendance_photo(
    p_attendance_id text,
    p_kind text,
    p_photo_url text,
    p_tenant_id text DEFAULT 'nutrifresh'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_row public.nf_attendance%ROWTYPE;
    v_new_data jsonb;
    v_clean_url text := trim(coalesce(p_photo_url, ''));
BEGIN
    IF NOT public.nf_s2_is_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Hanya karyawan aktif atau Owner yang dapat melampirkan foto absensi.';
    END IF;
    IF v_clean_url = '' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'URL foto kosong.');
    END IF;

    SELECT * INTO v_row
    FROM public.nf_attendance
    WHERE tenant_id = p_tenant_id AND id = p_attendance_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'Data absensi tidak ditemukan.');
    END IF;

    IF lower(coalesce(p_kind, 'in')) = 'out' THEN
        v_new_data := coalesce(v_row.data, '{}'::jsonb) || jsonb_build_object('photoOutUrl', v_clean_url);
        UPDATE public.nf_attendance
        SET photo_out_url = v_clean_url,
            data = v_new_data,
            updated_at = now()
        WHERE tenant_id = p_tenant_id AND id = p_attendance_id;
    ELSE
        v_new_data := coalesce(v_row.data, '{}'::jsonb) || jsonb_build_object('photoInUrl', v_clean_url);
        UPDATE public.nf_attendance
        SET photo_in_url = v_clean_url,
            data = v_new_data,
            updated_at = now()
        WHERE tenant_id = p_tenant_id AND id = p_attendance_id;
    END IF;

    RETURN jsonb_build_object('ok', true, 'id', p_attendance_id, 'kind', lower(coalesce(p_kind, 'in')), 'url', v_clean_url);
END;
$$;

GRANT EXECUTE ON FUNCTION public.nf_attach_attendance_photo(text, text, text, text) TO authenticated;

-- 3. Tabel Pengumuman Manajemen untuk Tim (NutriFresh Staff)
CREATE TABLE IF NOT EXISTS public.nf_hr_announcements (
    tenant_id text NOT NULL DEFAULT 'nutrifresh',
    branch_id text NOT NULL DEFAULT 'cabang-1',
    id text NOT NULL,
    title text NOT NULL DEFAULT '',
    body text NOT NULL DEFAULT '',
    priority text NOT NULL DEFAULT 'info',
    active boolean NOT NULL DEFAULT true,
    created_by text,
    created_at timestamptz NOT NULL DEFAULT now(),
    data jsonb NOT NULL DEFAULT '{}'::jsonb,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, id)
);

-- 4. Tabel Jadwal Shift Karyawan
CREATE TABLE IF NOT EXISTS public.nf_hr_schedules (
    tenant_id text NOT NULL DEFAULT 'nutrifresh',
    branch_id text NOT NULL DEFAULT 'cabang-1',
    id text NOT NULL,
    sched_date text NOT NULL DEFAULT '',
    employee_id text,
    employee_name text NOT NULL DEFAULT '',
    shift_name text NOT NULL DEFAULT 'Shift 1',
    note text DEFAULT '',
    data jsonb NOT NULL DEFAULT '{}'::jsonb,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, id)
);
CREATE INDEX IF NOT EXISTS idx_nf_hr_schedules_date ON public.nf_hr_schedules (tenant_id, sched_date DESC);

-- 5. Tabel Buku Pinjaman / Kasbon Cicilan Karyawan
CREATE TABLE IF NOT EXISTS public.nf_hr_loans (
    tenant_id text NOT NULL DEFAULT 'nutrifresh',
    branch_id text NOT NULL DEFAULT 'cabang-1',
    id text NOT NULL,
    employee_id text,
    employee_name text NOT NULL DEFAULT '',
    loan_date text NOT NULL DEFAULT '',
    total_amount numeric NOT NULL DEFAULT 0,
    paid_amount numeric NOT NULL DEFAULT 0,
    monthly_installment numeric NOT NULL DEFAULT 0,
    status text NOT NULL DEFAULT 'Aktif',
    note text DEFAULT '',
    data jsonb NOT NULL DEFAULT '{}'::jsonb,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, id)
);

-- 6. Tabel Jatah Cuti Tahunan per Karyawan
CREATE TABLE IF NOT EXISTS public.nf_hr_leave_quotas (
    tenant_id text NOT NULL DEFAULT 'nutrifresh',
    branch_id text NOT NULL DEFAULT 'cabang-1',
    id text NOT NULL,
    year integer NOT NULL DEFAULT 2026,
    employee_id text,
    employee_name text NOT NULL DEFAULT '',
    annual_quota integer NOT NULL DEFAULT 12,
    used_days integer NOT NULL DEFAULT 0,
    data jsonb NOT NULL DEFAULT '{}'::jsonb,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, id)
);

-- 7. Aktifkan RLS & Kebijakan Akses Aman
ALTER TABLE public.nf_hr_announcements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nf_hr_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nf_hr_loans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nf_hr_leave_quotas ENABLE ROW LEVEL SECURITY;

-- Announcements: semua staf aktif bisa baca; Owner/HR bisa tulis
DROP POLICY IF EXISTS nf_hr_ann_select ON public.nf_hr_announcements;
CREATE POLICY nf_hr_ann_select ON public.nf_hr_announcements
    FOR SELECT TO authenticated
    USING (public.nf_s2_is_staff(tenant_id));

DROP POLICY IF EXISTS nf_hr_ann_write ON public.nf_hr_announcements;
CREATE POLICY nf_hr_ann_write ON public.nf_hr_announcements
    FOR ALL TO authenticated
    USING (public.nf_s2_is_hr_or_owner(tenant_id))
    WITH CHECK (public.nf_s2_is_hr_or_owner(tenant_id));

-- Schedules: semua staf aktif bisa baca jadwal; Owner/HR bisa tulis
DROP POLICY IF EXISTS nf_hr_sched_select ON public.nf_hr_schedules;
CREATE POLICY nf_hr_sched_select ON public.nf_hr_schedules
    FOR SELECT TO authenticated
    USING (public.nf_s2_is_staff(tenant_id));

DROP POLICY IF EXISTS nf_hr_sched_write ON public.nf_hr_schedules;
CREATE POLICY nf_hr_sched_write ON public.nf_hr_schedules
    FOR ALL TO authenticated
    USING (public.nf_s2_is_hr_or_owner(tenant_id))
    WITH CHECK (public.nf_s2_is_hr_or_owner(tenant_id));

-- Loans: semua staf aktif bisa baca (difilter per akun di aplikasi); Owner/HR bisa tulis
DROP POLICY IF EXISTS nf_hr_loans_select ON public.nf_hr_loans;
CREATE POLICY nf_hr_loans_select ON public.nf_hr_loans
    FOR SELECT TO authenticated
    USING (public.nf_s2_is_staff(tenant_id));

DROP POLICY IF EXISTS nf_hr_loans_write ON public.nf_hr_loans;
CREATE POLICY nf_hr_loans_write ON public.nf_hr_loans
    FOR ALL TO authenticated
    USING (public.nf_s2_is_hr_or_owner(tenant_id))
    WITH CHECK (public.nf_s2_is_hr_or_owner(tenant_id));

-- Leave Quotas: semua staf aktif bisa baca; Owner/HR bisa tulis
DROP POLICY IF EXISTS nf_hr_quota_select ON public.nf_hr_leave_quotas;
CREATE POLICY nf_hr_quota_select ON public.nf_hr_leave_quotas
    FOR SELECT TO authenticated
    USING (public.nf_s2_is_staff(tenant_id));

DROP POLICY IF EXISTS nf_hr_quota_write ON public.nf_hr_leave_quotas;
CREATE POLICY nf_hr_quota_write ON public.nf_hr_leave_quotas
    FOR ALL TO authenticated
    USING (public.nf_s2_is_hr_or_owner(tenant_id))
    WITH CHECK (public.nf_s2_is_hr_or_owner(tenant_id));

-- 8. Daftarkan ke Realtime publication jika tersedia (abaikan jika sudah terdaftar)
DO $$
BEGIN
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.nf_hr_announcements; EXCEPTION WHEN others THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.nf_hr_schedules; EXCEPTION WHEN others THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.nf_hr_loans; EXCEPTION WHEN others THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.nf_hr_leave_quotas; EXCEPTION WHEN others THEN NULL; END;
END $$;
