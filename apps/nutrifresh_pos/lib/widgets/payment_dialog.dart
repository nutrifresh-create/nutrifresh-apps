import 'package:flutter/material.dart';
import 'package:nf_core/nf_core.dart';
import '../state/pos_controller.dart';

Future<NfTransaction?> showPaymentGlassModal({
  required BuildContext context,
  required PosController controller,
}) {
  return showNfGlassModal<NfTransaction>(
    context: context,
    style: controller.uiStyle,
    title: 'Pembayaran Kasir',
    subtitle: '${controller.customerName} • ${controller.cart.length} item',
    icon: Icons.payments_rounded,
    headerGradient: const [Color(0xFF558B2F), Color(0xFF7CB342)],
    builder: (_) => _PaymentContent(controller: controller),
  );
}

class _PaymentContent extends StatefulWidget {
  final PosController controller;
  const _PaymentContent({required this.controller});

  @override
  State<_PaymentContent> createState() => _PaymentContentState();
}

class _PaymentContentState extends State<_PaymentContent> {
  String _method = 'Tunai';
  late final TextEditingController _cashCtrl;
  late final TextEditingController _discCtrl;
  late final TextEditingController _refCtrl;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _cashCtrl = TextEditingController(text: widget.controller.cartGrandTotal.toString());
    _discCtrl = TextEditingController(
      text: widget.controller.overallDiscountRp > 0
          ? widget.controller.overallDiscountRp.round().toString()
          : '',
    );
    _refCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    _discCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final c = widget.controller;
    final total = c.cartGrandTotal.toDouble();
    final cashVal = double.tryParse(_cashCtrl.text.trim()) ?? 0;
    if (_method == 'Tunai' && cashVal < total) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uang tunai kurang dari total belanja!')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final tx = await c.processPayment(
        paymentMethod: _method,
        cashReceived: _method == 'Tunai' ? cashVal : total,
        referenceNote: _refCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(tx);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memproses transaksi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final total = c.cartGrandTotal;
    final cashVal = int.tryParse(_cashCtrl.text.trim()) ?? 0;
    final change = _method == 'Tunai' ? (cashVal - total) : 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NfColors.lightBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: NfColors.green.withAlpha(110)),
          ),
          child: Column(
            children: [
              const Text('TOTAL TAGIHAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: NfColors.greenDark)),
              const SizedBox(height: 4),
              Text(
                NfFormatters.rupiah(total),
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: NfColors.brown),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        NfSlidingSegmented<String>(
          style: c.uiStyle,
          greenActive: true,
          selected: _method,
          onChanged: (m) {
            setState(() {
              _method = m;
              if (m == 'Tunai') _cashCtrl.text = total.toString();
            });
          },
          items: const [
            ('Tunai', 'Tunai', null),
            ('QRIS', 'QRIS', null),
            ('Transfer', 'Transfer', null),
            ('Debit', 'Debit', null),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _discCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Diskon Tambahan Nota (Rp)',
            hintText: '0',
          ),
          onChanged: (v) {
            c.overallDiscountRp = double.tryParse(v.trim()) ?? 0;
            setState(() {
              if (_method == 'Tunai') _cashCtrl.text = c.cartGrandTotal.toString();
            });
          },
        ),
        if (_method == 'Tunai') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _cashCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            decoration: const InputDecoration(labelText: 'Uang Diterima (Rp)'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _pay(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [total, 20000, 50000, 100000].toSet().map((amt) {
              return InkWell(
                onTap: () => setState(() => _cashCtrl.text = amt.toString()),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFD5E0D9)),
                  ),
                  child: Text(
                    amt == total ? 'Uang Pas' : NfFormatters.rupiah(amt),
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Kembalian:', style: TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  change >= 0 ? NfFormatters.rupiah(change) : 'Kurang ${NfFormatters.rupiah(change.abs())}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: change >= 0 ? NfColors.greenDark : NfColors.danger,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 12),
          TextField(
            controller: _refCtrl,
            decoration: const InputDecoration(
              labelText: 'Catatan / Referensi Transfer / QRIS',
              hintText: 'Misal: BCA a.n Ibu Sari / QRIS Lunas',
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                child: const Text('Batal'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _pay,
                icon: _submitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_rounded),
                label: Text(_submitting ? 'Memproses...' : 'Bayar & Cetak Struk'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
