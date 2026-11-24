import 'package:flutter/material.dart';
import 'package:nf_core/nf_core.dart';

class WeightQtyResult {
  final int qty;
  final int? customNominal;
  final String note;
  const WeightQtyResult({required this.qty, this.customNominal, this.note = ''});
}

class WeightQtyDialog extends StatefulWidget {
  final NfProduct product;
  final String buyerMode;
  final int initialQty;
  final String initialNote;

  const WeightQtyDialog({
    super.key,
    required this.product,
    required this.buyerMode,
    required this.initialQty,
    this.initialNote = '',
  });

  @override
  State<WeightQtyDialog> createState() => _WeightQtyDialogState();
}

class _WeightQtyDialogState extends State<WeightQtyDialog> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _nomCtrl;
  late final TextEditingController _noteCtrl;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: widget.initialQty.toString());
    _nomCtrl = TextEditingController();
    _noteCtrl = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _nomCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  int get _qty => int.tryParse(_qtyCtrl.text.trim()) ?? 0;
  int? get _customNom {
    final v = int.tryParse(_nomCtrl.text.trim());
    return (v != null && v > 0) ? v : null;
  }

  void _setQty(int v) {
    final clamped = v < 1 ? 1 : (widget.product.stock > 0 && v > widget.product.stock ? widget.product.stock : v);
    setState(() {
      _qtyCtrl.text = clamped.toString();
      _nomCtrl.clear();
    });
  }

  void _submit() {
    final q = _qty;
    if (q <= 0) return;
    Navigator.of(context).pop(WeightQtyResult(
      qty: q,
      customNominal: _customNom,
      note: _noteCtrl.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final isGram = p.unit == 'Gram';
    final sub = p.calculateLineAmount(
      _qty,
      buyerMode: widget.buyerMode,
      customNominal: _customNom,
    );

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 2),
          Text(
            '${NfFormatters.rupiah(p.effectivePriceForMode(widget.buyerMode))} / ${NfFormatters.catalogPriceUnit(p.unit)}  •  Stok: ${NfFormatters.stockDisplay(p.stock, p.unit)}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isGram) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [250, 500, 750, 1000, 1500, 2000].map((g) {
                    return ActionChip(
                      label: Text(NfFormatters.stockDisplay(g, 'Gram'),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                      backgroundColor: NfColors.lightBg,
                      onPressed: () => _setQty(g),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => _setQty(_qty - (isGram ? 100 : 1)),
                    icon: const Icon(Icons.remove),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _qtyCtrl,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                      decoration: InputDecoration(
                        labelText: isGram ? 'Berat Riil (Gram)' : 'Jumlah (${p.unit})',
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () => _setQty(_qty + (isGram ? 100 : 1)),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nomCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Atau Nominal Custom Rp (Opsional)',
                  hintText: 'Kosongkan untuk hitung otomatis',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Catatan Item (Opsional)',
                  hintText: 'Misal: pilih yang manis / matang',
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: NfColors.lightBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: NfColors.green.withAlpha(90)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtotal:', style: TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                      NfFormatters.rupiah(sub),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: NfColors.brown,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: _qty > 0 ? _submit : null,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Simpan ke Keranjang'),
        ),
      ],
    );
  }
}
