import 'package:flutter/material.dart';
import 'package:nf_core/nf_core.dart';

class WeightQtyResult {
  final int qty;
  final int? customNominal;
  final String note;
  const WeightQtyResult({required this.qty, this.customNominal, this.note = ''});
}

Future<WeightQtyResult?> showWeightQtyGlassModal({
  required BuildContext context,
  required NfUiStyle style,
  required NfProduct product,
  required String buyerMode,
  required int initialQty,
  String initialNote = '',
}) {
  return showNfGlassModal<WeightQtyResult>(
    context: context,
    style: style,
    title: product.name,
    subtitle:
        '${NfFormatters.rupiah(product.effectivePriceForMode(buyerMode))} / ${NfFormatters.catalogPriceUnit(product.unit)}  •  Stok: ${NfFormatters.stockDisplay(product.stock, product.unit)}',
    icon: Icons.scale_rounded,
    headerGradient: const [Color(0xFF558B2F), Color(0xFF7CB342)],
    builder: (ctx) => _WeightQtyContent(
      product: product,
      buyerMode: buyerMode,
      initialQty: initialQty,
      initialNote: initialNote,
    ),
  );
}

class _WeightQtyContent extends StatefulWidget {
  final NfProduct product;
  final String buyerMode;
  final int initialQty;
  final String initialNote;

  const _WeightQtyContent({
    required this.product,
    required this.buyerMode,
    required this.initialQty,
    this.initialNote = '',
  });

  @override
  State<_WeightQtyContent> createState() => _WeightQtyContentState();
}

class _WeightQtyContentState extends State<_WeightQtyContent> {
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
    final maxS = widget.product.stock > 0 ? widget.product.stock : 999999;
    final clamped = v < 1 ? 1 : (v > maxS ? maxS : v);
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isGram) ...[
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [250, 500, 750, 1000, 1500, 2000].map((g) {
              final act = _qty == g && _customNom == null;
              return InkWell(
                onTap: () => _setQty(g),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: act ? NfColors.green : Colors.white,
                    border: Border.all(
                      color: act ? NfColors.greenDark : const Color(0xFFD5E0D9),
                    ),
                  ),
                  child: Text(
                    NfFormatters.stockDisplay(g, 'Gram'),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: act ? Colors.white : const Color(0xFF334155),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: () => _setQty(_qty - (isGram ? 100 : 1)),
              icon: const Icon(Icons.remove_rounded),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _qtyCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
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
              icon: const Icon(Icons.add_rounded),
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
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: NfColors.green.withAlpha(110)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Subtotal Item:', style: TextStyle(fontWeight: FontWeight.w800)),
              Text(
                NfFormatters.rupiah(sub),
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: NfColors.brown),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Batal'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _qty > 0 ? _submit : null,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Simpan ke Keranjang'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
