-- ============================================================================
-- NUTRIFRESH TAHAP 3 (v138): ORDER APLIKASI LANGSUNG, LIVE TRACKING, BUKTI BAYAR & ONGKIR
-- Aman dijalankan berulang kali (IF NOT EXISTS / CREATE OR REPLACE).
-- Tidak menghapus atau mengubah data lama.
-- ============================================================================

-- 1. Tambah kolom pendukung pelacakan pesanan, ongkir, foto timbang & bukti transfer
ALTER TABLE IF EXISTS public.nf_online_orders
    ADD COLUMN IF NOT EXISTS shipping_fee numeric NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS weigh_photo_url text,
    ADD COLUMN IF NOT EXISTS payment_proof_url text,
    ADD COLUMN IF NOT EXISTS cashier_note text DEFAULT '',
    ADD COLUMN IF NOT EXISTS status_updated_at timestamptz NOT NULL DEFAULT now();

-- 2. RPC aman bagi pelanggan (Tamu maupun Member) untuk melacak status pesanan miliknya
--    Autentikasi dilakukan dengan mencocokkan (id + receipt_token) per pesanan
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
                        'cashierNote', coalesce(v_row.cashier_note, v_row.data ->> 'cashierNote', ''),
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

-- 3. RPC aman bagi pelanggan (Tamu/Member) untuk mengunggah bukti bayar QRIS/Transfer
--    Validasi ketat berdasarkan (order_id + receipt_token)
CREATE OR REPLACE FUNCTION public.nf_customer_upload_order_proof(
    p_order_id text,
    p_token text,
    p_proof_url text,
    p_payment_method text DEFAULT '',
    p_tenant_id text DEFAULT 'nutrifresh'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_row public.nf_online_orders%ROWTYPE;
    v_clean_proof text := trim(coalesce(p_proof_url, ''));
    v_pay_method text;
    v_new_data jsonb;
BEGIN
    IF v_clean_proof = '' THEN
        RAISE EXCEPTION 'Bukti pembayaran tidak boleh kosong.';
    END IF;
    IF length(v_clean_proof) > 250000 THEN
        RAISE EXCEPTION 'Ukuran bukti pembayaran terlalu besar. Ulangi foto agar otomatis terkompresi.';
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

    v_pay_method := coalesce(nullif(trim(p_payment_method), ''), v_row.payment_method, 'QRIS');
    v_new_data := coalesce(v_row.data, '{}'::jsonb) || jsonb_build_object(
        'paymentProofUrl', v_clean_proof,
        'paymentMethod', v_pay_method,
        'paymentProofUploadedAt', now(),
        'orderStatus', CASE WHEN v_row.order_status IN ('Menunggu Pembayaran', 'Menunggu Konfirmasi', 'Menunggu Timbang') THEN 'Menunggu Verifikasi Bayar' ELSE v_row.order_status END
    );

    UPDATE public.nf_online_orders
    SET payment_proof_url = v_clean_proof,
        payment_method = v_pay_method,
        order_status = CASE WHEN order_status IN ('Menunggu Pembayaran', 'Menunggu Konfirmasi', 'Menunggu Timbang') THEN 'Menunggu Verifikasi Bayar' ELSE order_status END,
        status_updated_at = now(),
        data = v_new_data,
        updated_at = now()
    WHERE tenant_id = p_tenant_id AND id = v_row.id;

    RETURN jsonb_build_object(
        'ok', true,
        'id', v_row.id,
        'orderStatus', CASE WHEN v_row.order_status IN ('Menunggu Pembayaran', 'Menunggu Konfirmasi', 'Menunggu Timbang') THEN 'Menunggu Verifikasi Bayar' ELSE v_row.order_status END
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.nf_customer_upload_order_proof(text, text, text, text, text) TO anon, authenticated;
