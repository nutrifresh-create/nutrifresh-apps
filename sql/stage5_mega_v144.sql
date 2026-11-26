-- ============================================================================
-- NUTRIFRESH MEGA UPDATE v144:
-- 1. Riwayat Pesanan Pelanggan Sinkron Cloud berdasarkan Nomor WA / Member
--    (tidak hilang meski APK di-uninstall atau ganti HP!)
-- 2. Infrastruktur Background Push Notification (FCM Android + Telegram Bot)
--    dengan trigger otomatis untuk Order, Chat, Kurir, Payroll & Kasbon.
-- 3. Kolom alur terhubung NutriFresh Office (HR -> Bendahara -> Buku Kas).
-- Aman dijalankan berulang kali (IF NOT EXISTS / CREATE OR REPLACE).
-- ============================================================================

-- 1. KOLOM ALUR TERHUBUNG OFFICE (HR -> BENDAHARA -> KAS PERUSAHAAN)
ALTER TABLE IF EXISTS public.nf_office_payroll
    ADD COLUMN IF NOT EXISTS payment_status text DEFAULT 'Draft',
    ADD COLUMN IF NOT EXISTS submitted_by text,
    ADD COLUMN IF NOT EXISTS paid_by text,
    ADD COLUMN IF NOT EXISTS transfer_ref text;

ALTER TABLE IF EXISTS public.nf_office_hr_requests
    ADD COLUMN IF NOT EXISTS disbursement_status text DEFAULT '',
    ADD COLUMN IF NOT EXISTS disbursed_by text,
    ADD COLUMN IF NOT EXISTS transfer_ref text;

ALTER TABLE IF EXISTS public.nf_hr_loans
    ADD COLUMN IF NOT EXISTS disbursed_by text,
    ADD COLUMN IF NOT EXISTS transfer_ref text;

-- 2. RIWAYAT PESANAN PELANGGAN SINKRON CLOUD (VIA REFS LOKAL + NO. WA MEMBER)
CREATE OR REPLACE FUNCTION public.nf_customer_get_orders(
    p_refs jsonb DEFAULT '[]'::jsonb,
    p_tenant_id text DEFAULT 'nutrifresh',
    p_phone text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_orders jsonb := '[]'::jsonb;
    v_store jsonb := '{}'::jsonb;
    v_seen_ids text[] := ARRAY[]::text[];
    v_item jsonb;
    v_ref_id text;
    v_ref_tok text;
    v_clean_phone text;
    v_row public.nf_online_orders%ROWTYPE;
    v_merged jsonb;
BEGIN
    SELECT coalesce(s.data, '{}'::jsonb) INTO v_store
    FROM public.nf_settings s
    WHERE s.tenant_id = p_tenant_id AND s.id = 'store_settings'
    LIMIT 1;

    -- A. Ambil berdasarkan token rujukan perangkat (untuk tamu tanpa login Member)
    IF jsonb_typeof(p_refs) = 'array' THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_refs)
        LOOP
            v_ref_id := trim(coalesce(v_item ->> 'id', ''));
            v_ref_tok := upper(trim(coalesce(v_item ->> 'token', '')));
            IF v_ref_id <> '' AND v_ref_tok <> '' AND NOT (v_ref_id = ANY(v_seen_ids)) THEN
                SELECT * INTO v_row
                FROM public.nf_online_orders o
                WHERE o.tenant_id = p_tenant_id
                  AND o.id = v_ref_id
                  AND upper(trim(coalesce(o.receipt_token, o.data ->> 'receiptToken', ''))) = v_ref_tok
                LIMIT 1;

                IF FOUND THEN
                    v_seen_ids := array_append(v_seen_ids, v_row.id);
                    v_merged := coalesce(v_row.data, '{}'::jsonb) || jsonb_build_object(
                        'id', v_row.id,
                        'orderCode', coalesce(nullif(v_row.order_code, ''), v_row.id),
                        'receiptToken', coalesce(v_row.receipt_token, v_row.data ->> 'receiptToken', ''),
                        'customerName', coalesce(v_row.customer_name, v_row.data ->> 'customerName', 'Pelanggan'),
                        'customerPhone', coalesce(v_row.customer_phone, v_row.data ->> 'customerPhone', '-'),
                        'deliveryMode', coalesce(v_row.delivery_mode, v_row.data ->> 'deliveryMode', 'Kirim ke Rumah'),
                        'address', coalesce(v_row.address, v_row.data ->> 'address', ''),
                        'paymentMethod', coalesce(v_row.payment_method, v_row.data ->> 'paymentMethod', 'QRIS'),
                        'estimatedTotal', coalesce(v_row.estimated_total, 0),
                        'finalTotal', coalesce(v_row.final_total, v_row.estimated_total, 0),
                        'shippingFee', coalesce(v_row.shipping_fee, (v_row.data ->> 'shippingFee')::numeric, 0),
                        'orderStatus', coalesce(v_row.order_status, v_row.data ->> 'orderStatus', 'Menunggu Timbang'),
                        'linkedTxId', v_row.linked_tx_id,
                        'weighPhotoUrl', coalesce(v_row.weigh_photo_url, v_row.data ->> 'weighPhotoUrl', ''),
                        'paymentProofUrl', coalesce(v_row.payment_proof_url, v_row.data ->> 'paymentProofUrl', ''),
                        'deliveryProofUrl', coalesce(v_row.delivery_proof_url, v_row.data ->> 'deliveryProofUrl', ''),
                        'courierName', coalesce(v_row.courier_name, v_row.data ->> 'courierName', ''),
                        'cashierNote', coalesce(v_row.cashier_note, v_row.data ->> 'cashierNote', ''),
                        'customerApprovedAt', v_row.customer_approved_at,
                        'orderChat', coalesce(v_row.order_chat, v_row.data -> 'orderChat', '[]'::jsonb),
                        'items', coalesce(v_row.items, v_row.data -> 'items', '[]'::jsonb),
                        'createdAt', coalesce(v_row.created_at, now()),
                        'statusUpdatedAt', coalesce(v_row.status_updated_at, v_row.updated_at, v_row.created_at, now())
                    );
                    v_orders := v_orders || jsonb_build_array(v_merged);
                END IF;
            END IF;
        END LOOP;
    END IF;

    -- B. Ambil riwayat permanen dari Cloud berdasarkan Nomor WA Member (tahan uninstall / ganti HP!)
    v_clean_phone := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
    IF left(v_clean_phone, 1) = '0' THEN
        v_clean_phone := '62' || substr(v_clean_phone, 2);
    ELSIF left(v_clean_phone, 1) = '8' THEN
        v_clean_phone := '62' || v_clean_phone;
    END IF;

    IF length(v_clean_phone) >= 10 THEN
        FOR v_row IN
            SELECT *
            FROM public.nf_online_orders o
            WHERE o.tenant_id = p_tenant_id
              AND (
                  CASE
                      WHEN left(regexp_replace(coalesce(o.customer_phone, ''), '\D', '', 'g'), 1) = '0'
                          THEN '62' || substr(regexp_replace(coalesce(o.customer_phone, ''), '\D', '', 'g'), 2)
                      WHEN left(regexp_replace(coalesce(o.customer_phone, ''), '\D', '', 'g'), 1) = '8'
                          THEN '62' || regexp_replace(coalesce(o.customer_phone, ''), '\D', '', 'g')
                      ELSE regexp_replace(coalesce(o.customer_phone, ''), '\D', '', 'g')
                  END
              ) = v_clean_phone
            ORDER BY o.created_at DESC
            LIMIT 30
        LOOP
            IF NOT (v_row.id = ANY(v_seen_ids)) THEN
                v_seen_ids := array_append(v_seen_ids, v_row.id);
                v_merged := coalesce(v_row.data, '{}'::jsonb) || jsonb_build_object(
                    'id', v_row.id,
                    'orderCode', coalesce(nullif(v_row.order_code, ''), v_row.id),
                    'receiptToken', coalesce(v_row.receipt_token, v_row.data ->> 'receiptToken', ''),
                    'customerName', coalesce(v_row.customer_name, v_row.data ->> 'customerName', 'Pelanggan'),
                    'customerPhone', coalesce(v_row.customer_phone, v_row.data ->> 'customerPhone', '-'),
                    'deliveryMode', coalesce(v_row.delivery_mode, v_row.data ->> 'deliveryMode', 'Kirim ke Rumah'),
                    'address', coalesce(v_row.address, v_row.data ->> 'address', ''),
                    'paymentMethod', coalesce(v_row.payment_method, v_row.data ->> 'paymentMethod', 'QRIS'),
                    'estimatedTotal', coalesce(v_row.estimated_total, 0),
                    'finalTotal', coalesce(v_row.final_total, v_row.estimated_total, 0),
                    'shippingFee', coalesce(v_row.shipping_fee, (v_row.data ->> 'shippingFee')::numeric, 0),
                    'orderStatus', coalesce(v_row.order_status, v_row.data ->> 'orderStatus', 'Menunggu Timbang'),
                    'linkedTxId', v_row.linked_tx_id,
                    'weighPhotoUrl', coalesce(v_row.weigh_photo_url, v_row.data ->> 'weighPhotoUrl', ''),
                    'paymentProofUrl', coalesce(v_row.payment_proof_url, v_row.data ->> 'paymentProofUrl', ''),
                    'deliveryProofUrl', coalesce(v_row.delivery_proof_url, v_row.data ->> 'deliveryProofUrl', ''),
                    'courierName', coalesce(v_row.courier_name, v_row.data ->> 'courierName', ''),
                    'cashierNote', coalesce(v_row.cashier_note, v_row.data ->> 'cashierNote', ''),
                    'customerApprovedAt', v_row.customer_approved_at,
                    'orderChat', coalesce(v_row.order_chat, v_row.data -> 'orderChat', '[]'::jsonb),
                    'items', coalesce(v_row.items, v_row.data -> 'items', '[]'::jsonb),
                    'createdAt', coalesce(v_row.created_at, now()),
                    'statusUpdatedAt', coalesce(v_row.status_updated_at, v_row.updated_at, v_row.created_at, now())
                );
                v_orders := v_orders || jsonb_build_array(v_merged);
            END IF;
        END LOOP;
    END IF;

    RETURN jsonb_build_object(
        'ok', true,
        'orders', v_orders,
        'paymentInfo', jsonb_build_object(
            'qrisImg', coalesce(v_store ->> 'qrisImg', ''),
            'bankInfo', coalesce(v_store ->> 'bankTransferInfo', ''),
            'freeShippingMin', coalesce((v_store ->> 'freeShippingMinOrder')::numeric, 0),
            'waNumber', coalesce(v_store ->> 'waNumber', '6289508011241')
        )
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.nf_customer_get_orders(jsonb, text, text) TO anon, authenticated;

-- 3. TABEL & RPC REGISTRASI PERANGKAT PUSH NOTIFICATION (FCM)
CREATE TABLE IF NOT EXISTS public.nf_push_devices (
    id bigserial PRIMARY KEY,
    tenant_id text NOT NULL DEFAULT 'nutrifresh',
    token text NOT NULL UNIQUE,
    app_role text NOT NULL DEFAULT 'customer',
    user_email text DEFAULT '',
    customer_phone text DEFAULT '',
    platform text NOT NULL DEFAULT 'android',
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_nf_push_devices_role ON public.nf_push_devices (tenant_id, app_role);
CREATE INDEX IF NOT EXISTS idx_nf_push_devices_phone ON public.nf_push_devices (tenant_id, customer_phone);

ALTER TABLE public.nf_push_devices ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.nf_register_push_device(
    p_token text,
    p_app_role text DEFAULT 'customer',
    p_user_email text DEFAULT '',
    p_customer_phone text DEFAULT '',
    p_platform text DEFAULT 'android',
    p_tenant_id text DEFAULT 'nutrifresh'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tok text := trim(coalesce(p_token, ''));
    v_phone text := regexp_replace(coalesce(p_customer_phone, ''), '\D', '', 'g');
BEGIN
    IF length(v_tok) < 16 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'Token tidak valid.');
    END IF;
    IF left(v_phone, 1) = '0' THEN v_phone := '62' || substr(v_phone, 2);
    ELSIF left(v_phone, 1) = '8' THEN v_phone := '62' || v_phone;
    END IF;

    INSERT INTO public.nf_push_devices (tenant_id, token, app_role, user_email, customer_phone, platform, updated_at)
    VALUES (p_tenant_id, v_tok, lower(trim(coalesce(p_app_role, 'customer'))), lower(trim(coalesce(p_user_email, ''))), v_phone, lower(trim(coalesce(p_platform, 'android'))), now())
    ON CONFLICT (token) DO UPDATE
    SET app_role = EXCLUDED.app_role,
        user_email = CASE WHEN EXCLUDED.user_email <> '' THEN EXCLUDED.user_email ELSE nf_push_devices.user_email END,
        customer_phone = CASE WHEN EXCLUDED.customer_phone <> '' THEN EXCLUDED.customer_phone ELSE nf_push_devices.customer_phone END,
        platform = EXCLUDED.platform,
        updated_at = now();

    RETURN jsonb_build_object('ok', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.nf_register_push_device(text, text, text, text, text, text) TO anon, authenticated;

-- 4. ANTREAN PUSH OTOMATIS (nf_push_outbox) + TRIGGER POSTGRESQL
CREATE TABLE IF NOT EXISTS public.nf_push_outbox (
    id bigserial PRIMARY KEY,
    tenant_id text NOT NULL DEFAULT 'nutrifresh',
    target_role text NOT NULL,
    target_phone text DEFAULT '',
    title text NOT NULL,
    body text NOT NULL,
    ref_id text DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    sent_at timestamptz
);

ALTER TABLE public.nf_push_outbox ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.nf_enqueue_order_push_trg()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_code text := coalesce(nullif(NEW.order_code, ''), NEW.id);
    v_phone text := regexp_replace(coalesce(NEW.customer_phone, ''), '\D', '', 'g');
    v_total numeric := coalesce(NEW.final_total, NEW.estimated_total, 0) + coalesce(NEW.shipping_fee, 0);
    v_old_chat_len int := 0;
    v_new_chat_len int := 0;
    v_last_msg jsonb;
BEGIN
    IF left(v_phone, 1) = '0' THEN v_phone := '62' || substr(v_phone, 2);
    ELSIF left(v_phone, 1) = '8' THEN v_phone := '62' || v_phone;
    END IF;

    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.nf_push_outbox (tenant_id, target_role, title, body, ref_id)
        VALUES (
            NEW.tenant_id,
            'pos',
            '🔔 Order Baru Masuk! #' || v_code,
            coalesce(NEW.customer_name, 'Pelanggan') || ' • ' || coalesce(NEW.payment_method, 'QRIS') || ' • Est. Rp ' || to_char(v_total, 'FM999,999,999'),
            NEW.id
        );
        RETURN NEW;
    END IF;

    IF coalesce(OLD.order_status, '') IS DISTINCT FROM coalesce(NEW.order_status, '') THEN
        IF NEW.order_status = 'Menunggu Pembayaran' THEN
            INSERT INTO public.nf_push_outbox (tenant_id, target_role, target_phone, title, body, ref_id)
            VALUES (NEW.tenant_id, 'customer', v_phone, '⚖️ Buah Selesai Ditimbang! #' || v_code, 'Total final Rp ' || to_char(v_total, 'FM999,999,999') || '. Buka aplikasi untuk ACC / Bayar.', NEW.id);
        ELSIF NEW.order_status IN ('Disetujui — Siap Kirim', 'Disetujui — Siap Diambil') THEN
            INSERT INTO public.nf_push_outbox (tenant_id, target_role, title, body, ref_id)
            VALUES (NEW.tenant_id, 'pos', '✅ Pelanggan ACC Timbangan! #' || v_code, coalesce(NEW.customer_name, 'Pelanggan') || ' setuju Rp ' || to_char(v_total, 'FM999,999,999') || '. Klik Serahkan ke Kurir!', NEW.id);
        ELSIF NEW.order_status = 'Menunggu Verifikasi Bayar' THEN
            INSERT INTO public.nf_push_outbox (tenant_id, target_role, title, body, ref_id)
            VALUES (NEW.tenant_id, 'pos', '💳 Bukti Bayar Masuk! #' || v_code, coalesce(NEW.customer_name, 'Pelanggan') || ' sudah upload bukti transfer. Cek & serahkan ke kurir!', NEW.id);
        ELSIF NEW.order_status = 'Siap Diambil Kurir' THEN
            INSERT INTO public.nf_push_outbox (tenant_id, target_role, title, body, ref_id)
            VALUES (NEW.tenant_id, 'staff', '🛵 Paket Siap Diambil Kurir! #' || v_code, coalesce(NEW.customer_name, 'Pelanggan') || ' • ' || coalesce(NEW.payment_method, '') || ' Rp ' || to_char(v_total, 'FM999,999,999'), NEW.id);
        ELSIF NEW.order_status = 'Diantar Kurir' THEN
            INSERT INTO public.nf_push_outbox (tenant_id, target_role, target_phone, title, body, ref_id)
            VALUES (NEW.tenant_id, 'customer', v_phone, '🛵 Pesanan Sedang Diantar! #' || v_code, 'Kurir ' || coalesce(nullif(NEW.courier_name, ''), 'NutriFresh') || ' sedang menuju alamat Anda.', NEW.id);
        ELSIF NEW.order_status LIKE 'Terkirim%' THEN
            INSERT INTO public.nf_push_outbox (tenant_id, target_role, title, body, ref_id)
            VALUES (NEW.tenant_id, 'pos', '📦 Kurir Selesai Antar! #' || v_code, coalesce(NEW.courier_name, 'Kurir') || ' sudah serahkan ke ' || coalesce(NEW.customer_name, 'Pelanggan') || '. Siap selesaikan nota!', NEW.id);
        ELSIF NEW.order_status = 'Selesai' THEN
            INSERT INTO public.nf_push_outbox (tenant_id, target_role, target_phone, title, body, ref_id)
            VALUES (NEW.tenant_id, 'customer', v_phone, '🎉 Pesanan Selesai! #' || v_code, 'Terima kasih telah berbelanja di NutriFresh. Resi digital siap diunduh!', NEW.id);
        END IF;
        RETURN NEW;
    END IF;

    IF jsonb_typeof(OLD.order_chat) = 'array' THEN v_old_chat_len := jsonb_array_length(OLD.order_chat); END IF;
    IF jsonb_typeof(NEW.order_chat) = 'array' THEN v_new_chat_len := jsonb_array_length(NEW.order_chat); END IF;
    IF v_new_chat_len > v_old_chat_len THEN
        v_last_msg := NEW.order_chat -> (v_new_chat_len - 1);
        IF coalesce(v_last_msg ->> 'sender', '') = 'customer' THEN
            INSERT INTO public.nf_push_outbox (tenant_id, target_role, title, body, ref_id)
            VALUES (NEW.tenant_id, 'pos', '💬 Chat dari ' || coalesce(NEW.customer_name, 'Pelanggan') || ' (#' || v_code || ')', left(coalesce(v_last_msg ->> 'text', ''), 160), NEW.id);
        ELSE
            INSERT INTO public.nf_push_outbox (tenant_id, target_role, target_phone, title, body, ref_id)
            VALUES (NEW.tenant_id, 'customer', v_phone, '💬 Pesan dari ' || coalesce(v_last_msg ->> 'name', 'NutriFresh') || ' (#' || v_code || ')', left(coalesce(v_last_msg ->> 'text', ''), 160), NEW.id);
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_nf_online_orders_push ON public.nf_online_orders;
CREATE TRIGGER trg_nf_online_orders_push
AFTER INSERT OR UPDATE ON public.nf_online_orders
FOR EACH ROW EXECUTE FUNCTION public.nf_enqueue_order_push_trg();

-- Trigger Push Office: saat HR mengajukan Payroll ke Bendahara -> kirim notifikasi ke Office (Bendahara/Owner)
CREATE OR REPLACE FUNCTION public.nf_enqueue_office_payroll_push_trg()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_old_st text := coalesce(OLD.payment_status, OLD.data ->> 'paymentStatus', 'Draft');
    v_new_st text := coalesce(NEW.payment_status, NEW.data ->> 'paymentStatus', 'Draft');
BEGIN
    IF v_new_st = 'Diajukan' AND v_old_st IS DISTINCT FROM 'Diajukan' THEN
        INSERT INTO public.nf_push_outbox (tenant_id, target_role, title, body, ref_id)
        VALUES (
            NEW.tenant_id,
            'office',
            '💸 Ajuan Transfer Gaji dari HR',
            'Gaji ' || coalesce(NEW.emp_name, 'Karyawan') || ' (' || coalesce(NEW.ym, '') || ') siap di-ACC & transfer oleh Bendahara.',
            NEW.id
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_nf_office_payroll_push ON public.nf_office_payroll;
CREATE TRIGGER trg_nf_office_payroll_push
AFTER INSERT OR UPDATE ON public.nf_office_payroll
FOR EACH ROW EXECUTE FUNCTION public.nf_enqueue_office_payroll_push_trg();


-- 5. TARGET EMAIL DI PUSH OUTBOX (UNTUK NOTIFIKASI KHUSUS KARYAWAN TERTENTU, MISAL JADWAL SHIFT)
ALTER TABLE IF EXISTS public.nf_push_outbox
    ADD COLUMN IF NOT EXISTS target_email text DEFAULT '';

-- 6. TABEL ABSEN DZIKIR PAGI & PETANG (TERHUBUNG KE TAB ABSENSI STAFF & PANTAU ABSENSI OFFICE)
CREATE TABLE IF NOT EXISTS public.nf_hr_dzikir (
    tenant_id text NOT NULL DEFAULT 'nutrifresh',
    branch_id text NOT NULL DEFAULT 'cabang-1',
    id text NOT NULL,
    date_str text,
    employee_id text,
    employee_name text,
    pagi_at timestamptz,
    petang_at timestamptz,
    data jsonb NOT NULL DEFAULT '{}'::jsonb,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, id)
);

CREATE INDEX IF NOT EXISTS idx_nf_hr_dzikir_date ON public.nf_hr_dzikir (tenant_id, date_str DESC);
ALTER TABLE public.nf_hr_dzikir ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'nf_hr_dzikir' AND policyname = 'nf_hr_dzikir_staff_all'
    ) THEN
        CREATE POLICY nf_hr_dzikir_staff_all ON public.nf_hr_dzikir
            FOR ALL TO authenticated
            USING (true)
            WITH CHECK (true);
    END IF;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.nf_hr_dzikir;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- 7. TRIGGER PUSH OTOMATIS: SAAT HR MENDAFTARKAN JADWAL SHIFT -> KIRIM PUSH KE HP STAFF TERKAIT!
CREATE OR REPLACE FUNCTION public.nf_enqueue_schedule_push_trg()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_emp_email text := '';
    v_shift text := coalesce(NEW.shift_name, 'Shift 1');
    v_dt text := coalesce(NEW.sched_date, NEW.data ->> 'date', '');
    v_note text := coalesce(nullif(trim(NEW.note), ''), 'Siapkan keberangkatan & datang tepat waktu.');
BEGIN
    SELECT lower(trim(coalesce(e.email, ''))) INTO v_emp_email
    FROM public.nf_employees e
    WHERE e.tenant_id = NEW.tenant_id
      AND (
          (coalesce(NEW.employee_id, '') <> '' AND e.id = NEW.employee_id)
          OR lower(trim(coalesce(e.name, ''))) = lower(trim(coalesce(NEW.employee_name, '')))
      )
    LIMIT 1;

    INSERT INTO public.nf_push_outbox (tenant_id, target_role, target_email, title, body, ref_id)
    VALUES (
        NEW.tenant_id,
        'staff',
        coalesce(v_emp_email, ''),
        '📅 Jadwal Shift Baru: ' || v_shift,
        coalesce(NEW.employee_name, 'Karyawan') || ' dijadwalkan ' || v_shift || ' tanggal ' || v_dt || '. ' || left(v_note, 120),
        NEW.id
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_nf_hr_schedules_push ON public.nf_hr_schedules;
CREATE TRIGGER trg_nf_hr_schedules_push
AFTER INSERT OR UPDATE ON public.nf_hr_schedules
FOR EACH ROW EXECUTE FUNCTION public.nf_enqueue_schedule_push_trg();

-- 8. TRIGGER PUSH OFFICE: KASBON DISETUJUI HR -> NOTIFIKASI KE BENDAHARA/OFFICE!
CREATE OR REPLACE FUNCTION public.nf_enqueue_hr_kasbon_push_trg()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_old_st text := coalesce(OLD.status, '');
    v_new_st text := coalesce(NEW.status, '');
    v_disb text := coalesce(NEW.disbursement_status, NEW.data ->> 'disbursementStatus', '');
BEGIN
    IF coalesce(NEW.req_type, '') = 'Kasbon' AND v_new_st = 'Disetujui' AND v_old_st IS DISTINCT FROM 'Disetujui' AND v_disb <> 'Sudah Ditransfer' THEN
        INSERT INTO public.nf_push_outbox (tenant_id, target_role, title, body, ref_id)
        VALUES (
            NEW.tenant_id,
            'office',
            '💵 Kasbon Disetujui HR — Tunggu Transfer',
            coalesce(NEW.emp_name, 'Karyawan') || ' sebesar Rp ' || to_char(coalesce(NEW.cash_amount, 0), 'FM999,999,999') || '. Buka Office → Kas & Beban untuk ACC & Transfer.',
            NEW.id
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_nf_hr_kasbon_push ON public.nf_office_hr_requests;
CREATE TRIGGER trg_nf_hr_kasbon_push
AFTER INSERT OR UPDATE ON public.nf_office_hr_requests
FOR EACH ROW EXECUTE FUNCTION public.nf_enqueue_hr_kasbon_push_trg();

-- 9. TRIGGER PUSH OFFICE: PINJAMAN BARU DARI HR -> NOTIFIKASI KE BENDAHARA/OFFICE!
CREATE OR REPLACE FUNCTION public.nf_enqueue_hr_loan_push_trg()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF coalesce(NEW.status, '') = 'Menunggu Pencairan' AND (TG_OP = 'INSERT' OR coalesce(OLD.status, '') IS DISTINCT FROM 'Menunggu Pencairan') THEN
        INSERT INTO public.nf_push_outbox (tenant_id, target_role, title, body, ref_id)
        VALUES (
            NEW.tenant_id,
            'office',
            '🏦 Pinjaman Karyawan — Tunggu Pencairan',
            coalesce(NEW.employee_name, 'Karyawan') || ' sebesar Rp ' || to_char(coalesce(NEW.total_amount, 0), 'FM999,999,999') || '. Buka Office → Kas & Beban untuk ACC & Cairkan.',
            NEW.id
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_nf_hr_loan_push ON public.nf_hr_loans;
CREATE TRIGGER trg_nf_hr_loan_push
AFTER INSERT OR UPDATE ON public.nf_hr_loans
FOR EACH ROW EXECUTE FUNCTION public.nf_enqueue_hr_loan_push_trg();
