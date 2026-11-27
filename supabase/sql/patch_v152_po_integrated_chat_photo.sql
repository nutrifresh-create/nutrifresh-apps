-- =========================================================================
-- NUTRIFRESH v152:
-- 1. PO PARSEL TERINTEGRASI PENUH KE PESANAN ONLINE, CHAT 2 ARAH & KURIR
-- 2. CORET ALAMAT OTOMATIS OLEH KURIR (ANTI SALAH PENCET MANUAL)
-- 3. DUKUNGAN FOTO DI CHAT 2 ARAH + FOTO TIMBANGAN / PARSEL JADI
-- 4. PEMBERSIHAN OTOMATIS FOTO SEMENTARA (> 30 HARI) AGAR STORAGE GRATIS AMAN
-- =========================================================================

-- A. Pastikan izin akses & kolom media tersedia di nf_parcel_orders & nf_online_orders
REVOKE ALL ON TABLE public.nf_parcel_orders FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.nf_parcel_orders TO authenticated;

CREATE UNIQUE INDEX IF NOT EXISTS uq_nf_parcel_orders_tenant_id
    ON public.nf_parcel_orders (tenant_id, id);

ALTER TABLE public.nf_online_orders ADD COLUMN IF NOT EXISTS weigh_photo_url text DEFAULT '';
ALTER TABLE public.nf_online_orders ADD COLUMN IF NOT EXISTS payment_proof_url text DEFAULT '';
ALTER TABLE public.nf_online_orders ADD COLUMN IF NOT EXISTS delivery_proof_url text DEFAULT '';
ALTER TABLE public.nf_online_orders ADD COLUMN IF NOT EXISTS cashier_note text DEFAULT '';
ALTER TABLE public.nf_online_orders ADD COLUMN IF NOT EXISTS courier_name text DEFAULT '';
ALTER TABLE public.nf_online_orders ADD COLUMN IF NOT EXISTS shipping_fee numeric DEFAULT 0;
ALTER TABLE public.nf_online_orders ADD COLUMN IF NOT EXISTS order_chat jsonb DEFAULT '[]'::jsonb;

CREATE OR REPLACE FUNCTION public.nf_po_is_staff(p_tenant_id text DEFAULT 'nutrifresh')
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.nf_employees
        WHERE tenant_id = p_tenant_id
          AND lower(COALESCE(email, data->>'email', '')) = lower(COALESCE(auth.jwt()->>'email', ''))
          AND COALESCE(status, data->>'status', 'Aktif') <> 'Non-Aktif'
    )
    OR EXISTS (
        SELECT 1 FROM public.nf_staff_roles
        WHERE tenant_id = p_tenant_id
          AND lower(COALESCE(email, data->>'email', '')) = lower(COALESCE(auth.jwt()->>'email', ''))
          AND COALESCE(active, true) = true
    )
    OR EXISTS (
        SELECT 1 FROM public.nf_settings
        WHERE id IN ('security_config', 'store_settings')
          AND lower(COALESCE(data->>'ownerEmail', '')) = lower(COALESCE(auth.jwt()->>'email', ''))
    );
$$;
GRANT EXECUTE ON FUNCTION public.nf_po_is_staff(text) TO authenticated;

-- B. Helper untuk meratakan daftar tujuan (destinations) & item tampilan untuk nf_online_orders
CREATE OR REPLACE FUNCTION public.nf_build_po_online_mirror(
    p_code text,
    p_token text,
    p_name text,
    p_phone text,
    p_institution text,
    p_member_id text,
    p_payment_plan text,
    p_first_date text,
    p_first_time text,
    p_total numeric,
    p_items jsonb,
    p_branch_id text,
    p_order_status text DEFAULT 'PO Menunggu Konfirmasi',
    p_payment_status text DEFAULT 'Belum Bayar',
    p_dp_amount numeric DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_dests jsonb := '[]'::jsonb;
    v_display_items jsonb := '[]'::jsonb;
    v_item jsonb;
    v_d jsonb;
    v_i int := 0;
    v_j int := 0;
    v_has_delivery boolean := false;
    v_addr_parts text[] := ARRAY[]::text[];
    v_pm text;
    v_deliv_mode text;
    v_qty int;
    v_uprice numeric;
    v_sub numeric;
    v_ptype text;
BEGIN
    IF p_items IS NOT NULL AND jsonb_typeof(p_items) = 'array' THEN
        FOR v_i IN 0 .. jsonb_array_length(p_items) - 1 LOOP
            v_item := p_items -> v_i;
            v_qty := GREATEST(1, COALESCE((v_item->>'qty')::int, 1));
            v_uprice := GREATEST(0, COALESCE((v_item->>'unitPrice')::numeric, 0));
            v_sub := COALESCE((v_item->>'subtotal')::numeric, v_qty * v_uprice);
            v_ptype := COALESCE(NULLIF(trim(v_item->>'parcelType'), ''), 'Parcel Custom');

            v_display_items := v_display_items || jsonb_build_array(jsonb_build_object(
                'id', 'POITEM-' || p_code || '-' || v_i::text,
                'name', v_ptype,
                'qty', v_qty,
                'requestedQty', v_qty,
                'unit', 'Pcs',
                'price', v_uprice,
                'subtotal', v_sub,
                'itemNote', COALESCE(v_item->>'note', ''),
                'deliveryDate', COALESCE(v_item->>'deliveryDate', p_first_date),
                'deliveryTime', COALESCE(v_item->>'deliveryTime', p_first_time),
                'deliveryMode', COALESCE(v_item->>'deliveryMode', 'Diantar')
            ));

            IF COALESCE(v_item->>'deliveryMode', 'Diantar') <> 'Diambil' THEN
                v_has_delivery := true;
                IF v_item ? 'destinations' AND jsonb_typeof(v_item->'destinations') = 'array' AND jsonb_array_length(v_item->'destinations') > 0 THEN
                    FOR v_j IN 0 .. jsonb_array_length(v_item->'destinations') - 1 LOOP
                        v_d := v_item->'destinations' -> v_j;
                        v_dests := v_dests || jsonb_build_array(jsonb_build_object(
                            'itemIdx', v_i,
                            'destIdx', v_j,
                            'parcelType', v_ptype,
                            'deliveryDate', COALESCE(v_item->>'deliveryDate', p_first_date),
                            'deliveryTime', COALESCE(v_item->>'deliveryTime', p_first_time),
                            'address', COALESCE(v_d->>'address', '-'),
                            'qty', GREATEST(1, COALESCE((v_d->>'qty')::int, v_qty)),
                            'delivered', COALESCE((v_d->>'delivered')::boolean, false),
                            'deliveredAt', v_d->>'deliveredAt',
                            'deliveredBy', COALESCE(v_d->>'deliveredBy', ''),
                            'deliveryProofUrl', COALESCE(v_d->>'deliveryProofUrl', '')
                        ));
                        v_addr_parts := array_append(v_addr_parts, GREATEST(1, COALESCE((v_d->>'qty')::int, v_qty))::text || 'x ' || COALESCE(v_d->>'address', '-'));
                    END LOOP;
                END IF;
            END IF;
        END LOOP;
    END IF;

    v_deliv_mode := CASE WHEN v_has_delivery THEN 'Kirim ke Rumah' ELSE 'Ambil di Toko' END;
    IF lower(COALESCE(p_payment_plan, '')) LIKE '%ambil%' OR lower(COALESCE(p_payment_plan, '')) LIKE '%cod%' OR lower(COALESCE(p_payment_plan, '')) LIKE '%tunai%' OR lower(COALESCE(p_payment_plan, '')) LIKE '%cash%' THEN
        v_pm := 'Cash / Tunai (COD)';
    ELSIF lower(COALESCE(p_payment_plan, '')) LIKE '%transfer%' OR lower(COALESCE(p_payment_plan, '')) LIKE '%qris%' THEN
        v_pm := 'QRIS / Transfer';
    ELSE
        v_pm := COALESCE(NULLIF(trim(p_payment_plan), ''), 'Konfirmasi via WA');
    END IF;

    RETURN jsonb_build_object(
        'id', p_code,
        'orderCode', p_code,
        'receiptToken', p_token,
        'branchId', COALESCE(NULLIF(trim(p_branch_id), ''), 'cabang-1'),
        'isParcelOrder', true,
        'parcelOrderId', p_code,
        'customerName', p_name,
        'customerPhone', p_phone,
        'institution', COALESCE(p_institution, ''),
        'memberId', p_member_id,
        'deliveryMode', v_deliv_mode,
        'address', CASE WHEN array_length(v_addr_parts, 1) > 0 THEN array_to_string(v_addr_parts, ' | ') ELSE 'Diambil di Toko NutriFresh' END,
        'deliveryDate', p_first_date,
        'deliveryTime', p_first_time,
        'paymentMethod', v_pm,
        'paymentPlan', COALESCE(p_payment_plan, ''),
        'paymentStatus', COALESCE(p_payment_status, 'Belum Bayar'),
        'dpAmount', COALESCE(p_dp_amount, 0),
        'estimatedTotal', p_total,
        'finalTotal', GREATEST(0, p_total - COALESCE(p_dp_amount, 0)),
        'shippingFee', 0,
        'orderStatus', p_order_status,
        'items', v_display_items,
        'parcelItems', COALESCE(p_items, '[]'::jsonb),
        'destinations', v_dests,
        'orderChat', '[]'::jsonb,
        'createdAt', now()
    );
END;
$$;

-- C. Upgrade nf_submit_parcel_order agar otomatis masuk ke nf_parcel_orders + mirror ke nf_online_orders
CREATE OR REPLACE FUNCTION public.nf_submit_parcel_order(
    p_customer_name text,
    p_customer_phone text,
    p_items jsonb,
    p_institution text DEFAULT '',
    p_note text DEFAULT '',
    p_payment_plan text DEFAULT 'Konfirmasi WA',
    p_branch_id text DEFAULT 'cabang-1',
    p_tenant_id text DEFAULT 'nutrifresh'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_name text := trim(COALESCE(p_customer_name, ''));
    v_phone text := regexp_replace(COALESCE(p_customer_phone, ''), '\D', '', 'g');
    v_id text;
    v_code text;
    v_token text;
    v_total numeric := 0;
    v_first_date text := to_char(now() AT TIME ZONE 'Asia/Jakarta', 'YYYY-MM-DD');
    v_first_time text := '08:00';
    v_member_id text := NULL;
    v_member_name text := NULL;
    v_payload jsonb;
    v_mirror jsonb;
BEGIN
    IF length(v_name) < 2 THEN
        RAISE EXCEPTION 'INVALID_NAME: Nama pemesan wajib diisi.';
    END IF;
    IF v_phone LIKE '0%' THEN
        v_phone := '62' || substr(v_phone, 2);
    ELSIF v_phone LIKE '8%' THEN
        v_phone := '62' || v_phone;
    END IF;
    IF length(v_phone) < 10 THEN
        RAISE EXCEPTION 'INVALID_PHONE: Nomor WhatsApp aktif wajib diisi (minimal 10 digit).';
    END IF;
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'EMPTY_ITEMS: Minimal harus ada 1 item parsel.';
    END IF;

    SELECT
        COALESCE(SUM(GREATEST(0, COALESCE((elem->>'qty')::numeric, 1)) * GREATEST(0, COALESCE((elem->>'unitPrice')::numeric, 0))), 0),
        COALESCE(MIN(NULLIF(trim(elem->>'deliveryDate'), '')), v_first_date),
        COALESCE(MIN(NULLIF(trim(elem->>'deliveryTime'), '')), v_first_time)
    INTO v_total, v_first_date, v_first_time
    FROM jsonb_array_elements(p_items) AS elem;

    SELECT id, name INTO v_member_id, v_member_name
    FROM public.nf_members
    WHERE tenant_id = p_tenant_id AND phone = v_phone
    LIMIT 1;

    v_code := 'PO-' || to_char(now() AT TIME ZONE 'Asia/Jakarta', 'YYMMDD') || '-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 4));
    v_token := upper(substr(md5(random()::text || v_code || clock_timestamp()::text), 1, 6));
    v_id := v_code;

    v_payload := jsonb_build_object(
        'id', v_id,
        'orderCode', v_code,
        'receiptToken', v_token,
        'branchId', COALESCE(NULLIF(trim(p_branch_id), ''), 'cabang-1'),
        'customerName', v_name,
        'customerPhone', v_phone,
        'institution', trim(COALESCE(p_institution, '')),
        'memberId', v_member_id,
        'memberName', v_member_name,
        'source', 'web',
        'deliveryDate', v_first_date,
        'deliveryTime', v_first_time,
        'totalAmount', v_total,
        'dpAmount', 0,
        'paymentPlan', COALESCE(NULLIF(trim(p_payment_plan), ''), 'Konfirmasi WA'),
        'paymentStatus', 'Belum Bayar',
        'orderStatus', 'Menunggu Konfirmasi',
        'note', trim(COALESCE(p_note, '')),
        'items', p_items,
        'createdAt', now()
    );

    INSERT INTO public.nf_parcel_orders (
        id, tenant_id, branch_id, order_code, customer_name, customer_phone,
        institution, member_id, source, delivery_date, delivery_time,
        total_amount, dp_amount, payment_status, order_status, items, data
    ) VALUES (
        v_id, p_tenant_id, COALESCE(NULLIF(trim(p_branch_id), ''), 'cabang-1'),
        v_code, v_name, v_phone, trim(COALESCE(p_institution, '')), v_member_id,
        'web', v_first_date, v_first_time, v_total, 0,
        'Belum Bayar', 'Menunggu Konfirmasi', p_items, v_payload
    );

    -- Buat mirror terintegrasi di nf_online_orders agar langsung muncul di Pesanan Saya, Chat 2 Arah & Kurir Staff
    v_mirror := public.nf_build_po_online_mirror(
        v_code, v_token, v_name, v_phone, trim(COALESCE(p_institution, '')), v_member_id,
        p_payment_plan, v_first_date, v_first_time, v_total, p_items, p_branch_id,
        'PO Menunggu Konfirmasi', 'Belum Bayar', 0
    );

    INSERT INTO public.nf_online_orders (
        id, tenant_id, branch_id, order_code, receipt_token,
        customer_name, customer_phone, delivery_mode, address,
        payment_method, member_id, estimated_total, final_total,
        shipping_fee, order_status, items, order_chat, data
    ) VALUES (
        v_id, p_tenant_id, COALESCE(NULLIF(trim(p_branch_id), ''), 'cabang-1'),
        v_code, v_token, v_name, v_phone,
        v_mirror->>'deliveryMode', v_mirror->>'address',
        v_mirror->>'paymentMethod', v_member_id, v_total, v_total,
        0, 'PO Menunggu Konfirmasi', v_mirror->'items', '[]'::jsonb, v_mirror
    )
    ON CONFLICT (id) DO NOTHING;

    RETURN jsonb_build_object(
        'ok', true,
        'id', v_id,
        'orderCode', v_code,
        'receiptToken', v_token,
        'totalAmount', v_total,
        'isMember', (v_member_id IS NOT NULL)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.nf_submit_parcel_order(text, text, jsonb, text, text, text, text, text) TO anon, authenticated;

-- D. Backfill PO Parsel yang sudah ada (seperti PO-261127-6865) ke nf_online_orders agar langsung tampil di Pesanan Saya
DO $$
DECLARE
    r RECORD;
    v_tok text;
    v_st text;
    v_mirror jsonb;
BEGIN
    FOR r IN
        SELECT p.* FROM public.nf_parcel_orders p
        WHERE NOT EXISTS (SELECT 1 FROM public.nf_online_orders o WHERE o.id = p.id)
    LOOP
        v_tok := COALESCE(NULLIF(r.data->>'receiptToken', ''), upper(substr(md5(r.id || 'nf152'), 1, 6)));
        v_st := CASE r.order_status
            WHEN 'Menunggu Konfirmasi' THEN 'PO Menunggu Konfirmasi'
            WHEN 'Dikonfirmasi' THEN 'PO Dikonfirmasi'
            WHEN 'Sedang Dirakit' THEN 'PO Sedang Dirakit'
            WHEN 'Selesai Dirakit' THEN 'PO Selesai Dirakit'
            WHEN 'Siap Ambil/Kirim' THEN 'Siap Diambil Kurir'
            ELSE COALESCE(r.order_status, 'PO Menunggu Konfirmasi')
        END;
        v_mirror := public.nf_build_po_online_mirror(
            r.order_code, v_tok, r.customer_name, r.customer_phone,
            COALESCE(r.institution, ''), r.member_id,
            COALESCE(r.data->>'paymentPlan', 'Konfirmasi WA'),
            r.delivery_date, r.delivery_time, r.total_amount,
            COALESCE(r.items, '[]'::jsonb), r.branch_id,
            v_st, COALESCE(r.payment_status, 'Belum Bayar'), COALESCE(r.dp_amount, 0)
        );
        UPDATE public.nf_parcel_orders
        SET data = jsonb_set(COALESCE(data, '{}'::jsonb), '{receiptToken}', to_jsonb(v_tok), true)
        WHERE id = r.id;

        INSERT INTO public.nf_online_orders (
            id, tenant_id, branch_id, order_code, receipt_token,
            customer_name, customer_phone, delivery_mode, address,
            payment_method, member_id, estimated_total, final_total,
            shipping_fee, order_status, items, order_chat, data, created_at
        ) VALUES (
            r.id, r.tenant_id, r.branch_id, r.order_code, v_tok,
            r.customer_name, r.customer_phone,
            v_mirror->>'deliveryMode', v_mirror->>'address',
            v_mirror->>'paymentMethod', r.member_id, r.total_amount,
            GREATEST(0, COALESCE(r.total_amount, 0) - COALESCE(r.dp_amount, 0)),
            0, v_st, v_mirror->'items', '[]'::jsonb, v_mirror, r.created_at
        )
        ON CONFLICT (id) DO NOTHING;
    END LOOP;
END $$;

-- E. Upgrade Chat 2 Arah (Pelanggan & Staff/Kasir/Kurir) dengan Dukungan Foto Opsional (p_image_url)
DROP FUNCTION IF EXISTS public.nf_customer_send_order_chat(text, text, text, text, text);
CREATE OR REPLACE FUNCTION public.nf_customer_send_order_chat(
    p_order_id text,
    p_token text,
    p_message text,
    p_sender_name text DEFAULT '',
    p_tenant_id text DEFAULT 'nutrifresh',
    p_image_url text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ord RECORD;
    v_msg text := trim(COALESCE(p_message, ''));
    v_img text := trim(COALESCE(p_image_url, ''));
    v_name text;
    v_chat jsonb;
    v_entry jsonb;
    v_new_data jsonb;
BEGIN
    IF v_msg = '' AND v_img = '' THEN
        RAISE EXCEPTION 'EMPTY_MESSAGE: Pesan atau foto wajib diisi.';
    END IF;

    SELECT * INTO v_ord
    FROM public.nf_online_orders
    WHERE tenant_id = p_tenant_id
      AND (id = p_order_id OR order_code = p_order_id)
      AND upper(COALESCE(receipt_token, data->>'receiptToken', '')) = upper(trim(COALESCE(p_token, '')))
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: Pesanan atau token keamanan tidak cocok.';
    END IF;

    v_name := COALESCE(NULLIF(trim(p_sender_name), ''), v_ord.customer_name, 'Pelanggan');
    v_chat := COALESCE(v_ord.order_chat, v_ord.data->'orderChat', '[]'::jsonb);
    IF jsonb_typeof(v_chat) <> 'array' THEN v_chat := '[]'::jsonb; END IF;

    v_entry := jsonb_build_object(
        'id', 'MSG-' || floor(extract(epoch FROM clock_timestamp()) * 1000)::bigint::text,
        'sender', 'customer',
        'name', v_name,
        'text', CASE WHEN v_msg <> '' THEN v_msg ELSE '📷 Mengirim foto' END,
        'imageUrl', v_img,
        'at', now()
    );
    v_chat := v_chat || jsonb_build_array(v_entry);
    v_new_data := jsonb_set(COALESCE(v_ord.data, '{}'::jsonb), '{orderChat}', v_chat, true);

    UPDATE public.nf_online_orders
    SET order_chat = v_chat, data = v_new_data, updated_at = now()
    WHERE id = v_ord.id;

    RETURN jsonb_build_object('ok', true, 'orderId', v_ord.id, 'orderChat', v_chat);
END;
$$;
GRANT EXECUTE ON FUNCTION public.nf_customer_send_order_chat(text, text, text, text, text, text) TO anon, authenticated;

DROP FUNCTION IF EXISTS public.nf_staff_send_order_chat(text, text, text, text, text);
CREATE OR REPLACE FUNCTION public.nf_staff_send_order_chat(
    p_order_id text,
    p_message text,
    p_sender_name text DEFAULT 'Kasir Toko',
    p_sender_role text DEFAULT 'store',
    p_tenant_id text DEFAULT 'nutrifresh',
    p_image_url text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ord RECORD;
    v_msg text := trim(COALESCE(p_message, ''));
    v_img text := trim(COALESCE(p_image_url, ''));
    v_role text := CASE WHEN lower(COALESCE(p_sender_role, '')) = 'courier' THEN 'courier' ELSE 'store' END;
    v_name text := COALESCE(NULLIF(trim(p_sender_name), ''), CASE WHEN v_role = 'courier' THEN 'Kurir NutriFresh' ELSE 'Kasir Toko' END);
    v_chat jsonb;
    v_entry jsonb;
    v_new_data jsonb;
BEGIN
    IF v_msg = '' AND v_img = '' THEN
        RAISE EXCEPTION 'EMPTY_MESSAGE: Pesan atau foto wajib diisi.';
    END IF;
    IF NOT public.nf_po_is_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'FORBIDDEN: Hanya staf atau owner aktif yang diizinkan.';
    END IF;

    SELECT * INTO v_ord
    FROM public.nf_online_orders
    WHERE tenant_id = p_tenant_id AND (id = p_order_id OR order_code = p_order_id)
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: Pesanan tidak ditemukan.';
    END IF;

    v_chat := COALESCE(v_ord.order_chat, v_ord.data->'orderChat', '[]'::jsonb);
    IF jsonb_typeof(v_chat) <> 'array' THEN v_chat := '[]'::jsonb; END IF;

    v_entry := jsonb_build_object(
        'id', 'MSG-' || floor(extract(epoch FROM clock_timestamp()) * 1000)::bigint::text,
        'sender', v_role,
        'name', v_name,
        'text', CASE WHEN v_msg <> '' THEN v_msg ELSE '📷 Mengirim foto' END,
        'imageUrl', v_img,
        'at', now()
    );
    v_chat := v_chat || jsonb_build_array(v_entry);
    v_new_data := jsonb_set(COALESCE(v_ord.data, '{}'::jsonb), '{orderChat}', v_chat, true);

    UPDATE public.nf_online_orders
    SET order_chat = v_chat, data = v_new_data, updated_at = now()
    WHERE id = v_ord.id;

    RETURN jsonb_build_object('ok', true, 'orderId', v_ord.id, 'orderChat', v_chat);
END;
$$;
GRANT EXECUTE ON FUNCTION public.nf_staff_send_order_chat(text, text, text, text, text, text) TO authenticated;

-- F. Upgrade nf_courier_update_delivery: CORET ALAMAT OTOMATIS OLEH KURIR (MULTI-ALAMAT & SINGLE-ALAMAT)
DROP FUNCTION IF EXISTS public.nf_courier_update_delivery(text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION public.nf_courier_update_delivery(
    p_order_id text,
    p_new_status text,
    p_courier_name text DEFAULT 'Kurir NutriFresh',
    p_proof_url text DEFAULT '',
    p_note text DEFAULT '',
    p_tenant_id text DEFAULT 'nutrifresh',
    p_dest_index integer DEFAULT -1
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ord RECORD;
    v_po RECORD;
    v_cname text := COALESCE(NULLIF(trim(p_courier_name), ''), 'Kurir NutriFresh');
    v_proof text := trim(COALESCE(p_proof_url, ''));
    v_data jsonb;
    v_dests jsonb;
    v_new_dests jsonb := '[]'::jsonb;
    v_d jsonb;
    v_i int;
    v_all_delivered boolean := true;
    v_delivered_cnt int := 0;
    v_total_dests int := 0;
    v_final_status text := trim(COALESCE(p_new_status, ''));
    v_chat jsonb;
    v_chat_msg text := '';
    v_po_items jsonb;
    v_new_po_items jsonb := '[]'::jsonb;
    v_pit jsonb;
    v_pdests jsonb;
    v_new_pdests jsonb;
    v_pd jsonb;
    v_pi int;
    v_pj int;
    v_target_item_idx int := -1;
    v_target_dest_idx int := -1;
    v_target_addr text := '';
BEGIN
    IF NOT public.nf_po_is_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'FORBIDDEN: Hanya kurir/staf aktif yang diizinkan.';
    END IF;

    SELECT * INTO v_ord
    FROM public.nf_online_orders
    WHERE tenant_id = p_tenant_id AND (id = p_order_id OR order_code = p_order_id)
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: Pesanan tidak ditemukan.';
    END IF;

    v_data := COALESCE(v_ord.data, '{}'::jsonb);
    v_dests := CASE WHEN jsonb_typeof(v_data->'destinations') = 'array' THEN v_data->'destinations' ELSE '[]'::jsonb END;
    v_total_dests := jsonb_array_length(v_dests);

    -- Mode 1: Kurir menandai 1 titik alamat spesifik selesai dikirim (otomatis tercoret!)
    IF p_dest_index >= 0 AND v_total_dests > 0 AND p_dest_index < v_total_dests THEN
        FOR v_i IN 0 .. v_total_dests - 1 LOOP
            v_d := v_dests -> v_i;
            IF v_i = p_dest_index THEN
                v_target_item_idx := COALESCE((v_d->>'itemIdx')::int, -1);
                v_target_dest_idx := COALESCE((v_d->>'destIdx')::int, -1);
                v_target_addr := COALESCE(v_d->>'address', '');
                v_d := v_d || jsonb_build_object(
                    'delivered', true,
                    'deliveredAt', now(),
                    'deliveredBy', v_cname,
                    'deliveryProofUrl', CASE WHEN v_proof <> '' THEN v_proof ELSE COALESCE(v_d->>'deliveryProofUrl', '') END
                );
            END IF;
            IF COALESCE((v_d->>'delivered')::boolean, false) THEN
                v_delivered_cnt := v_delivered_cnt + 1;
            ELSE
                v_all_delivered := false;
            END IF;
            v_new_dests := v_new_dests || jsonb_build_array(v_d);
        END LOOP;
        v_data := jsonb_set(v_data, '{destinations}', v_new_dests, true);
        IF v_all_delivered THEN
            v_final_status := CASE
                WHEN lower(COALESCE(v_ord.payment_method, '')) ~ '(cash|tunai|cod)'
                     AND COALESCE(v_data->>'paymentStatus', '') <> 'Lunas'
                THEN 'Terkirim • Tunggu Setor COD'
                ELSE 'Terkirim • Lunas'
            END;
            v_chat_msg := '📦 Semua titik alamat (' || v_total_dests::text || '/' || v_total_dests::text || ') telah selesai diantar oleh ' || v_cname || '.';
        ELSE
            v_final_status := 'Diantar Kurir';
            v_chat_msg := '✅ Titik alamat terkirim (' || v_delivered_cnt::text || '/' || v_total_dests::text || '): ' || v_target_addr || ' oleh ' || v_cname || '.';
        END IF;

    -- Mode 2: Pengiriman selesai menyeluruh (single-alamat atau selesai semua) -> coret otomatis semua titik alamat!
    ELSIF v_final_status LIKE 'Terkirim%' AND v_total_dests > 0 THEN
        FOR v_i IN 0 .. v_total_dests - 1 LOOP
            v_d := v_dests -> v_i;
            IF NOT COALESCE((v_d->>'delivered')::boolean, false) THEN
                v_d := v_d || jsonb_build_object(
                    'delivered', true,
                    'deliveredAt', now(),
                    'deliveredBy', v_cname,
                    'deliveryProofUrl', CASE WHEN v_proof <> '' THEN v_proof ELSE COALESCE(v_d->>'deliveryProofUrl', '') END
                );
            END IF;
            v_new_dests := v_new_dests || jsonb_build_array(v_d);
        END LOOP;
        v_data := jsonb_set(v_data, '{destinations}', v_new_dests, true);
        v_all_delivered := true;
    END IF;

    -- Simpan update di nf_online_orders
    v_data := v_data || jsonb_build_object(
        'orderStatus', v_final_status,
        'courierName', v_cname
    );
    IF v_proof <> '' THEN
        v_data := jsonb_set(v_data, '{deliveryProofUrl}', to_jsonb(v_proof), true);
    END IF;

    v_chat := COALESCE(v_ord.order_chat, v_data->'orderChat', '[]'::jsonb);
    IF jsonb_typeof(v_chat) <> 'array' THEN v_chat := '[]'::jsonb; END IF;
    IF v_chat_msg <> '' THEN
        v_chat := v_chat || jsonb_build_array(jsonb_build_object(
            'id', 'MSG-' || floor(extract(epoch FROM clock_timestamp()) * 1000)::bigint::text,
            'sender', 'courier',
            'name', v_cname,
            'text', v_chat_msg,
            'imageUrl', v_proof,
            'at', now()
        ));
        v_data := jsonb_set(v_data, '{orderChat}', v_chat, true);
    END IF;

    UPDATE public.nf_online_orders
    SET order_status = v_final_status,
        courier_name = v_cname,
        delivery_proof_url = CASE WHEN v_proof <> '' THEN v_proof ELSE delivery_proof_url END,
        order_chat = v_chat,
        data = v_data,
        updated_at = now()
    WHERE id = v_ord.id;

    -- Sinkronkan status & coretan alamat otomatis ke nf_parcel_orders jika ini PO Parsel!
    SELECT * INTO v_po FROM public.nf_parcel_orders WHERE id = v_ord.id LIMIT 1;
    IF FOUND THEN
        v_po_items := COALESCE(v_po.items, v_po.data->'items', '[]'::jsonb);
        IF jsonb_typeof(v_po_items) = 'array' AND jsonb_array_length(v_po_items) > 0 THEN
            FOR v_pi IN 0 .. jsonb_array_length(v_po_items) - 1 LOOP
                v_pit := v_po_items -> v_pi;
                IF v_pit ? 'destinations' AND jsonb_typeof(v_pit->'destinations') = 'array' THEN
                    v_pdests := v_pit->'destinations';
                    v_new_pdests := '[]'::jsonb;
                    FOR v_pj IN 0 .. jsonb_array_length(v_pdests) - 1 LOOP
                        v_pd := v_pdests -> v_pj;
                        IF (p_dest_index >= 0 AND v_pi = v_target_item_idx AND v_pj = v_target_dest_idx)
                           OR (p_dest_index < 0 AND v_final_status LIKE 'Terkirim%') THEN
                            v_pd := v_pd || jsonb_build_object(
                                'delivered', true,
                                'deliveredAt', now(),
                                'deliveredBy', v_cname,
                                'deliveryProofUrl', CASE WHEN v_proof <> '' THEN v_proof ELSE COALESCE(v_pd->>'deliveryProofUrl', '') END
                            );
                        END IF;
                        v_new_pdests := v_new_pdests || jsonb_build_array(v_pd);
                    END LOOP;
                    v_pit := jsonb_set(v_pit, '{destinations}', v_new_pdests, true);
                END IF;
                v_new_po_items := v_new_po_items || jsonb_build_array(v_pit);
            END LOOP;
        ELSE
            v_new_po_items := v_po_items;
        END IF;

        UPDATE public.nf_parcel_orders
        SET order_status = CASE
                WHEN v_final_status = 'Diantar Kurir' THEN 'Diantar Kurir'
                WHEN v_final_status LIKE 'Terkirim%' THEN v_final_status
                ELSE order_status
            END,
            items = v_new_po_items,
            data = COALESCE(data, '{}'::jsonb) || jsonb_build_object(
                'orderStatus', CASE WHEN v_final_status = 'Diantar Kurir' THEN 'Diantar Kurir' WHEN v_final_status LIKE 'Terkirim%' THEN v_final_status ELSE order_status END,
                'courierName', v_cname,
                'items', v_new_po_items
            ),
            updated_at = now()
        WHERE id = v_po.id;
    END IF;

    RETURN jsonb_build_object(
        'ok', true,
        'orderId', v_ord.id,
        'orderStatus', v_final_status,
        'allDelivered', v_all_delivered,
        'destinations', CASE WHEN jsonb_array_length(v_new_dests) > 0 THEN v_new_dests ELSE v_dests END
    );
END;
$$;
GRANT EXECUTE ON FUNCTION public.nf_courier_update_delivery(text, text, text, text, text, text, integer) TO authenticated;

-- G. RPC Pembersih Otomatis Foto Sementara Pesanan (Timbangan, Parsel, Bukti Bayar, Foto Chat) > N Hari
-- Hanya menghapus foto pesanan yang sudah SELESAI / DIBATALKAN agar nota, omset & foto produk katalog 100% AMAN!
CREATE OR REPLACE FUNCTION public.nf_cleanup_old_order_media(
    p_days integer DEFAULT 30,
    p_tenant_id text DEFAULT 'nutrifresh'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cutoff timestamptz := now() - make_interval(days => GREATEST(7, COALESCE(p_days, 30)));
    v_ord RECORD;
    v_urls text[] := ARRAY[]::text[];
    v_chat jsonb;
    v_new_chat jsonb;
    v_msg jsonb;
    v_data jsonb;
    v_cleaned_orders int := 0;
    v_i int;
    v_u text;
    v_d jsonb;
    v_new_dests jsonb;
BEGIN
    FOR v_ord IN
        SELECT * FROM public.nf_online_orders
        WHERE tenant_id = p_tenant_id
          AND order_status IN ('Selesai', 'Dibatalkan')
          AND COALESCE(updated_at, created_at) < v_cutoff
    LOOP
        v_data := COALESCE(v_ord.data, '{}'::jsonb);
        v_i := 0;

        -- 1. Kumpulkan URL foto timbangan, bukti bayar, bukti antar, foto parsel
        FOREACH v_u IN ARRAY ARRAY[
            COALESCE(v_ord.weigh_photo_url, ''),
            COALESCE(v_ord.payment_proof_url, ''),
            COALESCE(v_ord.delivery_proof_url, ''),
            COALESCE(v_data->>'weighPhotoUrl', ''),
            COALESCE(v_data->>'paymentProofUrl', ''),
            COALESCE(v_data->>'deliveryProofUrl', ''),
            COALESCE(v_data->>'parcelPhotoUrl', '')
        ] LOOP
            IF v_u LIKE 'http%' AND v_u LIKE '%/nutrifresh-media/%' THEN
                v_urls := array_append(v_urls, v_u);
            END IF;
        END LOOP;

        -- 2. Kumpulkan & bersihkan URL foto di dalam chat
        v_chat := COALESCE(v_ord.order_chat, v_data->'orderChat', '[]'::jsonb);
        v_new_chat := '[]'::jsonb;
        IF jsonb_typeof(v_chat) = 'array' AND jsonb_array_length(v_chat) > 0 THEN
            FOR v_i IN 0 .. jsonb_array_length(v_chat) - 1 LOOP
                v_msg := v_chat -> v_i;
                v_u := COALESCE(v_msg->>'imageUrl', '');
                IF v_u <> '' THEN
                    IF v_u LIKE 'http%' AND v_u LIKE '%/nutrifresh-media/%' THEN
                        v_urls := array_append(v_urls, v_u);
                    END IF;
                    v_msg := v_msg || jsonb_build_object('imageUrl', '', 'imageExpired', true);
                END IF;
                v_new_chat := v_new_chat || jsonb_build_array(v_msg);
            END LOOP;
        ELSE
            v_new_chat := v_chat;
        END IF;

        -- 3. Bersihkan URL bukti antar per titik alamat
        IF jsonb_typeof(v_data->'destinations') = 'array' AND jsonb_array_length(v_data->'destinations') > 0 THEN
            v_new_dests := '[]'::jsonb;
            FOR v_i IN 0 .. jsonb_array_length(v_data->'destinations') - 1 LOOP
                v_d := v_data->'destinations' -> v_i;
                v_u := COALESCE(v_d->>'deliveryProofUrl', '');
                IF v_u <> '' THEN
                    IF v_u LIKE 'http%' AND v_u LIKE '%/nutrifresh-media/%' THEN
                        v_urls := array_append(v_urls, v_u);
                    END IF;
                    v_d := jsonb_set(v_d, '{deliveryProofUrl}', '""'::jsonb, true);
                END IF;
                v_new_dests := v_new_dests || jsonb_build_array(v_d);
            END LOOP;
            v_data := jsonb_set(v_data, '{destinations}', v_new_dests, true);
        END IF;

        IF COALESCE(v_ord.weigh_photo_url, '') <> ''
           OR COALESCE(v_ord.payment_proof_url, '') <> ''
           OR COALESCE(v_ord.delivery_proof_url, '') <> ''
           OR COALESCE(v_data->>'weighPhotoUrl', '') <> ''
           OR COALESCE(v_data->>'paymentProofUrl', '') <> ''
           OR COALESCE(v_data->>'deliveryProofUrl', '') <> ''
           OR COALESCE(v_data->>'parcelPhotoUrl', '') <> ''
           OR v_new_chat IS DISTINCT FROM v_chat THEN

            v_data := v_data || jsonb_build_object(
                'weighPhotoUrl', '',
                'paymentProofUrl', '',
                'deliveryProofUrl', '',
                'parcelPhotoUrl', '',
                'orderChat', v_new_chat,
                'mediaCleanedAt', now()
            );

            UPDATE public.nf_online_orders
            SET weigh_photo_url = '',
                payment_proof_url = '',
                delivery_proof_url = '',
                order_chat = v_new_chat,
                data = v_data
            WHERE id = v_ord.id;

            UPDATE public.nf_parcel_orders
            SET data = COALESCE(data, '{}'::jsonb) || jsonb_build_object('parcelPhotoUrl', '', 'mediaCleanedAt', now())
            WHERE id = v_ord.id;

            v_cleaned_orders := v_cleaned_orders + 1;
        END IF;
    END LOOP;

    -- Ekstrak path objek relatif di dalam bucket nutrifresh-media (deduplikasi)
    RETURN jsonb_build_object(
        'ok', true,
        'days', GREATEST(7, COALESCE(p_days, 30)),
        'cleanedOrders', v_cleaned_orders,
        'storagePaths', COALESCE((
            SELECT jsonb_agg(DISTINCT split_part(u, '/nutrifresh-media/', 2))
            FROM unnest(v_urls) AS u
            WHERE u LIKE '%/nutrifresh-media/%'
              AND split_part(u, '/nutrifresh-media/', 2) <> ''
        ), '[]'::jsonb)
    );
END;
$$;
GRANT EXECUTE ON FUNCTION public.nf_cleanup_old_order_media(integer, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
