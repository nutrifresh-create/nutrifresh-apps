import 'package:flutter/material.dart';
import 'package:nf_core/nf_core.dart';
import '../state/pos_controller.dart';

class PaymentDialog extends StatefulWidget {
  final PosController controller;
  const PaymentDialog({super.key, required this.controller});

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
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

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Pembayaran Transaksi', style: TextStyle(fontWeight: FontWeight.w900)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: NfColors.lightBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: NfColors.green.withAlpha(100)),
                ),
                child: Column(
                  children: [
                    const Text('TOTAL TAGIHAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: NfColors.greenDark)),
                    const SizedBox(height: 4),
                    Text(
                      NfFormatters.rupiah(total),
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: NfColors.brown),
                    ),
                    Text('${c.customerName} • ${c.cart.length} item', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text('Metode Pembayaran', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['Tunai', 'QRIS', 'Transfer', 'Debit'].map((m) {
                  final sel = _method == m;
                  return ChoiceChip(
                    label: Text(m, style: TextStyle(fontWeight: FontWeight.w800, color: sel ? Colors.white : const Color(0xFF334155))),
                    selected: sel,
                    selectedColor: NfColors.green,
                    onSelected: (_) {
                      setState(() {
                        _method = m;
                        if (m == 'Tunai') _cashCtrl.text = total.toString();
                      });
                    },
                  );
                }).toList(),
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
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  decoration: const InputDecoration(labelText: 'Uang Diterima (Rp)'),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _pay(),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [total, 20000, 50000, 100000].toSet().map((amt) {
                    return ActionChip(
                      label: Text(amt == total ? 'Uang Pas' : NfFormatters.rupiah(amt),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                      onPressed: () => setState(() => _cashCtrl.text = amt.toString()),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Kembalian:', style: TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                      change >= 0 ? NfFormatters.rupiah(change) : 'Kurang ${NfFormatters.rupiah(change.abs())}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: change >= 0 ? NfColors.greenDark : NfColors.danger,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _refCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Catatan / Referensi Transfer / QRIS (Opsional)',
                    hintText: 'Misal: BCA a.n Ibu Sari / QRIS Lunas',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _pay,
          icon: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_rounded),
          label: Text(_submitting ? 'Memproses...' : 'Bayar & Cetak Struk'),
        ),
      ],
    );
  }
}
