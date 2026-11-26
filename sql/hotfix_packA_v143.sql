-- ============================================================================
-- NUTRIFRESH HOTFIX PAKET A (v143):
-- 1. Fix Resi Digital Pelanggan ("Resi tidak ditemukan / tautan keamanan tidak cocok")
--    agar TRX hasil pembayaran order online selalu cocok dengan token order pelanggan
--    (termasuk memperbaiki order yang sudah terlanjur selesai sebelumnya!).
-- 2. Kunci tombol Ambil Kurir di server agar kurir baru bisa mengambil setelah kasir
--    menekan "Serahkan ke Kurir" (status 'Siap Diambil Kurir').
-- Aman dijalankan berulang kali (CREATE OR REPLACE).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.nf_get_public_receipt(
    p_ref_id text,
    p_token text,
    p_tenant_id text DEFAULT 'nutrifresh'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ref text := trim(coalesce(p_ref_id, ''));
    v_tok text := upper(trim(coalesce(p_token, '')));
    v_tx public.nf_transactions%ROWTYPE;
    v_ord public.nf_online_orders%ROWTYPE;
    v_store jsonb := '{}'::jsonb;
    v_tx_tok text;
    v_ord_tok text;
    v_linked_ok boolean := false;
BEGIN
    IF v_ref = '' OR v_tok = '' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'Parameter resi tidak lengkap.');
    END IF;

    SELECT coalesce(s.data, '{}'::jsonb) INTO v_store
    FROM public.nf_settings s
    WHERE s.tenant_id = p_tenant_id AND s.id = 'store_settings'
    LIMIT 1;

    -- 1. Cek di tabel Transaksi Resmi (nf_transactions)
    SELECT * INTO v_tx
    FROM public.nf_transactions t
    WHERE t.tenant_id = p_tenant_id AND t.id = v_ref
    LIMIT 1;

    IF FOUND THEN
        v_tx_tok := upper(trim(coalesce(v_tx.data ->> 'receiptToken', '')));
        IF v_tx_tok = v_tok THEN
            v_linked_ok := true;
        ELSE
            -- Juga cocokkan jika token berasal dari nf_online_orders yang tertaut ke TRX ini
            SELECT EXISTS (
                SELECT 1 FROM public.nf_online_orders o
                WHERE o.tenant_id = p_tenant_id
                  AND o.linked_tx_id = v_ref
                  AND upper(trim(coalesce(o.receipt_token, o.data ->> 'receiptToken', ''))) = v_tok
            ) INTO v_linked_ok;
        END IF;

        IF v_linked_ok THEN
            RETURN jsonb_build_object(
                'ok', true,
                'kind', 'transaction',
                'receipt', jsonb_build_object(
                    'id', v_tx.id,
                    'date', coalesce(v_tx.tx_date, v_tx.updated_at, now()),
                    'cashier', coalesce(v_tx.cashier, v_tx.data ->> 'cashier', 'Kasir'),
                    'customerName', coalesce(v_tx.customer_name, v_tx.data ->> 'customerName', 'Pelanggan'),
                    'paymentMethod', coalesce(v_tx.payment_method, v_tx.data ->> 'paymentMethod', 'Tunai'),
                    'status', coalesce(v_tx.status, 'success'),
                    'items', coalesce(v_tx.data -> 'items', '[]'::jsonb),
                    'total', coalesce(v_tx.total, (v_tx.data ->> 'total')::numeric, 0),
                    'totalDiscount', coalesce((v_tx.data ->> 'totalDiscount')::numeric, 0),
                    'cash', coalesce((v_tx.data ->> 'cash')::numeric, v_tx.total, 0),
                    'change', coalesce((v_tx.data ->> 'change')::numeric, 0),
                    'pointsEarned', coalesce((v_tx.data ->> 'pointsEarned')::numeric, 0),
                    'pointsAfter', coalesce((v_tx.data ->> 'pointsAfter')::numeric, 0)
                ),
                'store', jsonb_build_object(
                    'shopAddress', coalesce(v_store ->> 'shopAddress', ''),
                    'waNumber', coalesce(v_store ->> 'waNumber', '6289508011241'),
                    'receiptHeaderSub', coalesce(v_store ->> 'receiptHeaderSub', 'Fresh & Premium Fruits'),
                    'receiptFooterText', coalesce(v_store ->> 'receiptFooterText', 'Terima kasih telah berbelanja di NutriFresh!')
                )
            );
        END IF;
    END IF;

    -- 2. Cek di tabel Order Online (nf_online_orders)
    SELECT * INTO v_ord
    FROM public.nf_online_orders o
    WHERE o.tenant_id = p_tenant_id AND (o.id = v_ref OR o.order_code = v_ref)
    LIMIT 1;

    IF FOUND THEN
        v_ord_tok := upper(trim(coalesce(v_ord.receipt_token, v_ord.data ->> 'receiptToken', '')));
        IF v_ord_tok = v_tok THEN
            -- Jika sudah punya transaksi resmi (linked_tx_id), tampilkan nota resmi transaksinya!
            IF coalesce(v_ord.linked_tx_id, '') <> '' THEN
                SELECT * INTO v_tx
                FROM public.nf_transactions t
                WHERE t.tenant_id = p_tenant_id AND t.id = v_ord.linked_tx_id
                LIMIT 1;
                IF FOUND THEN
                    RETURN jsonb_build_object(
                        'ok', true,
                        'kind', 'transaction',
                        'receipt', jsonb_build_object(
                            'id', v_tx.id,
                            'date', coalesce(v_tx.tx_date, v_tx.updated_at, now()),
                            'cashier', coalesce(v_tx.cashier, v_tx.data ->> 'cashier', 'Kasir'),
                            'customerName', coalesce(v_tx.customer_name, v_ord.customer_name, 'Pelanggan'),
                            'paymentMethod', coalesce(v_tx.payment_method, v_ord.payment_method, 'Tunai'),
                            'deliveryMode', coalesce(v_ord.delivery_mode, 'Kirim ke Rumah'),
                            'status', coalesce(v_tx.status, 'success'),
                            'items', coalesce(v_tx.data -> 'items', v_ord.items, '[]'::jsonb),
                            'total', coalesce(v_tx.total, v_ord.final_total, 0),
                            'totalDiscount', coalesce((v_tx.data ->> 'totalDiscount')::numeric, 0),
                            'cash', coalesce((v_tx.data ->> 'cash')::numeric, v_tx.total, 0),
                            'change', coalesce((v_tx.data ->> 'change')::numeric, 0),
                            'pointsEarned', coalesce((v_tx.data ->> 'pointsEarned')::numeric, 0),
                            'pointsAfter', coalesce((v_tx.data ->> 'pointsAfter')::numeric, 0)
                        ),
                        'store', jsonb_build_object(
                            'shopAddress', coalesce(v_store ->> 'shopAddress', ''),
                            'waNumber', coalesce(v_store ->> 'waNumber', '6289508011241'),
                            'receiptHeaderSub', coalesce(v_store ->> 'receiptHeaderSub', 'Fresh & Premium Fruits'),
                            'receiptFooterText', coalesce(v_store ->> 'receiptFooterText', 'Terima kasih telah berbelanja di NutriFresh!')
                        )
                    );
                END IF;
            END IF;

            RETURN jsonb_build_object(
                'ok', true,
                'kind', 'online_order',
                'receipt', jsonb_build_object(
                    'id', coalesce(nullif(v_ord.order_code, ''), v_ord.id),
                    'date', coalesce(v_ord.created_at, now()),
                    'customerName', coalesce(v_ord.customer_name, 'Pelanggan'),
                    'paymentMethod', coalesce(v_ord.payment_method, 'QRIS'),
                    'deliveryMode', coalesce(v_ord.delivery_mode, 'Kirim ke Rumah'),
                    'orderStatus', coalesce(v_ord.order_status, 'Menunggu Timbang'),
                    'items', coalesce(v_ord.data -> 'weighedItems', v_ord.items, '[]'::jsonb),
                    'estimatedTotal', coalesce(v_ord.estimated_total, 0),
                    'finalTotal', coalesce(v_ord.final_total, v_ord.estimated_total, 0)
                ),
                'store', jsonb_build_object(
                    'shopAddress', coalesce(v_store ->> 'shopAddress', ''),
                    'waNumber', coalesce(v_store ->> 'waNumber', '6289508011241'),
                    'receiptHeaderSub', coalesce(v_store ->> 'receiptHeaderSub', 'Fresh & Premium Fruits'),
                    'receiptFooterText', coalesce(v_store ->> 'receiptFooterText', 'Terima kasih telah berbelanja di NutriFresh!')
                )
            );
        END IF;
    END IF;

    RETURN jsonb_build_object('ok', false, 'reason', 'Resi tidak ditemukan atau tautan keamanan tidak cocok.');
END;
$$;

GRANT EXECUTE ON FUNCTION public.nf_get_public_receipt(text, text, text) TO anon, authenticated;

-- 2. Pastikan kurir baru boleh menekan "Ambil & Mulai Antar" setelah kasir melepas order ('Siap Diambil Kurir')
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

    IF v_status = 'Diantar Kurir' AND v_row.order_status NOT IN ('Siap Diambil Kurir', 'Siap Kirim') THEN
        RAISE EXCEPTION 'Barang belum diserahkan kasir ke kurir (status saat ini: %). Tunggu kasir menekan "Serahkan ke Kurir".', v_row.order_status;
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
