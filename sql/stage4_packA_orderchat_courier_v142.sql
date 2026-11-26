-- ============================================================================
-- NUTRIFRESH PAKET A (v142):
-- - Tombol ACC Timbangan Pelanggan (COD / Siap Kirim)
-- - Chat 2 Arah di Dalam Pesanan (Pelanggan <-> POS Kasir <-> Kurir)
-- - Portal Antaran Kurir di NutriFresh Staff + Bukti Serah Terima
-- Aman dijalankan berulang kali (IF NOT EXISTS / CREATE OR REPLACE).
-- ============================================================================

-- 1. Tambah kolom pendukung chat pesanan, kurir, foto serah terima & waktu ACC
ALTER TABLE IF EXISTS public.nf_online_orders
    ADD COLUMN IF NOT EXISTS order_chat jsonb NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS courier_name text DEFAULT '',
    ADD COLUMN IF NOT EXISTS delivery_proof_url text,
    ADD COLUMN IF NOT EXISTS customer_approved_at timestamptz;

-- 2. Perbarui RPC pelacakan pelanggan agar ikut mengembalikan orderChat, courierName, deliveryProofUrl & customerApprovedAt
CREATE OR REPLACE FUNCTION public.nf_customer_get_orders(
    p_refs jsonb DEFAULT '[]'::jsonb,
    p_tenant_id text DEFAULT 'nutrifresh'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_orders jsonb := '[]'::jsonb;
    v_store jsonb := '{}'::jsonb;
    v_item jsonb;
    v_ref_id text;
    v_ref_tok text;
    v_row public.nf_online_orders%ROWTYPE;
    v_merged jsonb;
BEGIN
    SELECT coalesce(s.data, '{}'::jsonb) INTO v_store
    FROM public.nf_settings s
    WHERE s.tenant_id = p_tenant_id AND s.id = 'store_settings'
    LIMIT 1;

    IF jsonb_typeof(p_refs) = 'array' THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_refs)
        LOOP
            v_ref_id := trim(coalesce(v_item ->> 'id', ''));
            v_ref_tok := upper(trim(coalesce(v_item ->> 'token', '')));
            IF v_ref_id <> '' AND v_ref_tok <> '' THEN
                SELECT * INTO v_row
                FROM public.nf_online_orders o
                WHERE o.tenant_id = p_tenant_id
                  AND o.id = v_ref_id
                  AND upper(trim(coalesce(o.receipt_token, o.data ->> 'receiptToken', ''))) = v_ref_tok
                LIMIT 1;

                IF FOUND THEN
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

GRANT EXECUTE ON FUNCTION public.nf_customer_get_orders(jsonb, text) TO anon, authenticated;

-- 3. RPC Pelanggan: ACC hasil timbangan & total final (khususnya COD agar langsung masuk antrean Kurir)
CREATE OR REPLACE FUNCTION public.nf_customer_approve_order(
    p_order_id text,
    p_token text,
    p_tenant_id text DEFAULT 'nutrifresh'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_row public.nf_online_orders%ROWTYPE;
    v_next_status text;
    v_chat jsonb;
    v_msg jsonb;
    v_new_data jsonb;
BEGIN
    SELECT * INTO v_row
    FROM public.nf_online_orders
    WHERE tenant_id = p_tenant_id
      AND id = trim(coalesce(p_order_id, ''))
      AND upper(trim(coalesce(receipt_token, data ->> 'receiptToken', ''))) = upper(trim(coalesce(p_token, '')))
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pesanan tidak ditemukan atau token keamanan tidak valid.';
    END IF;

    IF v_row.order_status IN ('Selesai', 'Dibatalkan') THEN
        RAISE EXCEPTION 'Pesanan sudah berstatus %.', v_row.order_status;
    END IF;

    v_next_status := CASE
        WHEN lower(coalesce(v_row.delivery_mode, '')) LIKE '%ambil%' THEN 'Disetujui — Siap Diambil'
        ELSE 'Disetujui — Siap Kirim'
    END;

    v_chat := coalesce(v_row.order_chat, v_row.data -> 'orderChat', '[]'::jsonb);
    IF jsonb_typeof(v_chat) <> 'array' THEN v_chat := '[]'::jsonb; END IF;

    v_msg := jsonb_build_object(
        'id', 'MSG-' || floor(extract(epoch from clock_timestamp()) * 1000)::text,
        'sender', 'customer',
        'name', coalesce(v_row.customer_name, 'Pelanggan'),
        'text', '✅ Saya setuju dengan hasil timbangan & total final. Silakan diproses!',
        'at', now()
    );
    v_chat := v_chat || jsonb_build_array(v_msg);

    v_new_data := coalesce(v_row.data, '{}'::jsonb) || jsonb_build_object(
        'orderStatus', v_next_status,
        'customerApprovedAt', now(),
        'orderChat', v_chat
    );

    UPDATE public.nf_online_orders
    SET order_status = v_next_status,
        customer_approved_at = now(),
        order_chat = v_chat,
        status_updated_at = now(),
        data = v_new_data,
        updated_at = now()
    WHERE tenant_id = p_tenant_id AND id = v_row.id;

    RETURN jsonb_build_object('ok', true, 'id', v_row.id, 'orderStatus', v_next_status);
END;
$$;

GRANT EXECUTE ON FUNCTION public.nf_customer_approve_order(text, text, text) TO anon, authenticated;

-- 4. RPC Pelanggan: Kirim pesan chat 2 arah di dalam pesanan
CREATE OR REPLACE FUNCTION public.nf_customer_send_order_chat(
    p_order_id text,
    p_token text,
    p_message text,
    p_sender_name text DEFAULT '',
    p_tenant_id text DEFAULT 'nutrifresh'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_row public.nf_online_orders%ROWTYPE;
    v_clean_msg text := left(trim(coalesce(p_message, '')), 500);
    v_chat jsonb;
    v_msg jsonb;
    v_new_data jsonb;
BEGIN
    IF v_clean_msg = '' THEN
        RAISE EXCEPTION 'Pesan tidak boleh kosong.';
    END IF;

    SELECT * INTO v_row
    FROM public.nf_online_orders
    WHERE tenant_id = p_tenant_id
      AND id = trim(coalesce(p_order_id, ''))
      AND upper(trim(coalesce(receipt_token, data ->> 'receiptToken', ''))) = upper(trim(coalesce(p_token, '')))
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pesanan tidak ditemukan atau token keamanan tidak valid.';
    END IF;

    v_chat := coalesce(v_row.order_chat, v_row.data -> 'orderChat', '[]'::jsonb);
    IF jsonb_typeof(v_chat) <> 'array' THEN v_chat := '[]'::jsonb; END IF;

    v_msg := jsonb_build_object(
        'id', 'MSG-' || floor(extract(epoch from clock_timestamp()) * 1000)::text,
        'sender', 'customer',
        'name', coalesce(nullif(trim(p_sender_name), ''), v_row.customer_name, 'Pelanggan'),
        'text', v_clean_msg,
        'at', now()
    );
    v_chat := v_chat || jsonb_build_array(v_msg);

    v_new_data := coalesce(v_row.data, '{}'::jsonb) || jsonb_build_object('orderChat', v_chat);

    UPDATE public.nf_online_orders
    SET order_chat = v_chat,
        status_updated_at = now(),
        data = v_new_data,
        updated_at = now()
    WHERE tenant_id = p_tenant_id AND id = v_row.id;

    RETURN jsonb_build_object('ok', true, 'message', v_msg, 'orderChat', v_chat);
END;
$$;

GRANT EXECUTE ON FUNCTION public.nf_customer_send_order_chat(text, text, text, text, text) TO anon, authenticated;

-- 5. RPC Staf/Kasir/Kurir: Kirim pesan chat 2 arah ke pelanggan
CREATE OR REPLACE FUNCTION public.nf_staff_send_order_chat(
    p_order_id text,
    p_message text,
    p_sender_name text DEFAULT 'Kasir Toko',
    p_sender_role text DEFAULT 'store',
    p_tenant_id text DEFAULT 'nutrifresh'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_row public.nf_online_orders%ROWTYPE;
    v_clean_msg text := left(trim(coalesce(p_message, '')), 500);
    v_chat jsonb;
    v_msg jsonb;
    v_new_data jsonb;
    v_sender text := CASE WHEN lower(coalesce(p_sender_role, '')) = 'courier' THEN 'courier' ELSE 'store' END;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Sesi staf belum terautentikasi.';
    END IF;
    IF v_clean_msg = '' THEN
        RAISE EXCEPTION 'Pesan tidak boleh kosong.';
    END IF;

    SELECT * INTO v_row
    FROM public.nf_online_orders
    WHERE tenant_id = p_tenant_id AND id = trim(coalesce(p_order_id, ''))
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pesanan tidak ditemukan.';
    END IF;

    v_chat := coalesce(v_row.order_chat, v_row.data -> 'orderChat', '[]'::jsonb);
    IF jsonb_typeof(v_chat) <> 'array' THEN v_chat := '[]'::jsonb; END IF;

    v_msg := jsonb_build_object(
        'id', 'MSG-' || floor(extract(epoch from clock_timestamp()) * 1000)::text,
        'sender', v_sender,
        'name', coalesce(nullif(trim(p_sender_name), ''), 'Toko NutriFresh'),
        'text', v_clean_msg,
        'at', now()
    );
    v_chat := v_chat || jsonb_build_array(v_msg);

    v_new_data := coalesce(v_row.data, '{}'::jsonb) || jsonb_build_object('orderChat', v_chat);

    UPDATE public.nf_online_orders
    SET order_chat = v_chat,
        status_updated_at = now(),
        data = v_new_data,
        updated_at = now()
    WHERE tenant_id = p_tenant_id AND id = v_row.id;

    RETURN jsonb_build_object('ok', true, 'message', v_msg, 'orderChat', v_chat);
END;
$$;

GRANT EXECUTE ON FUNCTION public.nf_staff_send_order_chat(text, text, text, text, text) TO authenticated;

-- 6. RPC Kurir (NutriFresh Staff): Update status pengantaran (Mulai Antar / Diterima Pembeli + Foto Bukti)
CREATE OR REPLACE FUNCTION public.nf_courier_update_delivery(
    p_order_id text,
    p_new_status text,
    p_courier_name text DEFAULT 'Kurir NutriFresh',
    p_proof_url text DEFAULT '',
    p_note text DEFAULT '',
    p_tenant_id text DEFAULT 'nutrifresh'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_row public.nf_online_orders%ROWTYPE;
    v_status text := trim(coalesce(p_new_status, ''));
    v_cname text := coalesce(nullif(trim(p_courier_name), ''), 'Kurir NutriFresh');
    v_proof text := trim(coalesce(p_proof_url, ''));
    v_chat jsonb;
    v_auto_txt text;
    v_msg jsonb;
    v_new_data jsonb;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Sesi kurir/staf belum terautentikasi.';
    END IF;

    IF v_status NOT IN ('Diantar Kurir', 'Terkirim • Tunggu Setor COD', 'Terkirim • Lunas') THEN
        RAISE EXCEPTION 'Status pengantaran tidak valid: %', v_status;
    END IF;

    SELECT * INTO v_row
    FROM public.nf_online_orders
    WHERE tenant_id = p_tenant_id AND id = trim(coalesce(p_order_id, ''))
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pesanan tidak ditemukan.';
    END IF;

    v_chat := coalesce(v_row.order_chat, v_row.data -> 'orderChat', '[]'::jsonb);
    IF jsonb_typeof(v_chat) <> 'array' THEN v_chat := '[]'::jsonb; END IF;

    v_auto_txt := CASE
        WHEN v_status = 'Diantar Kurir' THEN '🛵 Pesanan sedang diantar oleh Kurir ' || v_cname || '.'
        WHEN v_status = 'Terkirim • Tunggu Setor COD' THEN '📦 Pesanan sudah diterima pembeli (COD diterima oleh Kurir ' || v_cname || ').'
        ELSE '📦 Pesanan sudah diterima pembeli (diantar oleh Kurir ' || v_cname || ').'
    END;
    IF trim(coalesce(p_note, '')) <> '' THEN
        v_auto_txt := v_auto_txt || ' Catatan: ' || left(trim(p_note), 200);
    END IF;

    v_msg := jsonb_build_object(
        'id', 'MSG-' || floor(extract(epoch from clock_timestamp()) * 1000)::text,
        'sender', 'courier',
        'name', v_cname,
        'text', v_auto_txt,
        'at', now()
    );
    v_chat := v_chat || jsonb_build_array(v_msg);

    v_new_data := coalesce(v_row.data, '{}'::jsonb) || jsonb_build_object(
        'orderStatus', v_status,
        'courierName', v_cname,
        'orderChat', v_chat,
        'deliveryProofUrl', CASE WHEN v_proof <> '' THEN v_proof ELSE coalesce(v_row.delivery_proof_url, v_row.data ->> 'deliveryProofUrl', '') END
    );

    UPDATE public.nf_online_orders
    SET order_status = v_status,
        courier_name = v_cname,
        delivery_proof_url = CASE WHEN v_proof <> '' THEN v_proof ELSE delivery_proof_url END,
        order_chat = v_chat,
        status_updated_at = now(),
        data = v_new_data,
        updated_at = now()
    WHERE tenant_id = p_tenant_id AND id = v_row.id;

    RETURN jsonb_build_object('ok', true, 'id', v_row.id, 'orderStatus', v_status, 'courierName', v_cname);
END;
$$;

GRANT EXECUTE ON FUNCTION public.nf_courier_update_delivery(text, text, text, text, text, text) TO authenticated;
