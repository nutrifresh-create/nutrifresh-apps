import 'package:flutter/material.dart';
import 'package:nf_core/nf_core.dart';
import '../services/pos_print_service.dart';
import '../state/pos_controller.dart';

class OpenShiftDialog extends StatefulWidget {
  final PosController controller;
  const OpenShiftDialog({super.key, required this.controller});

  @override
  State<OpenShiftDialog> createState() => _OpenShiftDialogState();
}

class _OpenShiftDialogState extends State<OpenShiftDialog> {
  final _cashCtrl = TextEditingController(text: '200000');
  bool _busy = false;

  @override
  void dispose() {
    _cashCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Buka Kasir (Shift Baru)', style: TextStyle(fontWeight: FontWeight.w900)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Kasir bertugas: ${widget.controller.session?.name ?? '-'}',
                style: const TextStyle(fontWeight: FontWeight.w700, color: NfColors.greenDark)),
            const SizedBox(height: 12),
            TextField(
              controller: _cashCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Modal Awal Laci Kasir (Rp)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Batal')),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    final amt = double.tryParse(_cashCtrl.text.trim()) ?? 0;
                    await widget.controller.openShift(amt);
                    if (context.mounted) Navigator.of(context).pop(true);
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: const Text('Buka Kasir Sekarang'),
        ),
      ],
    );
  }
}

class CloseShiftDialog extends StatefulWidget {
  final PosController controller;
  const CloseShiftDialog({super.key, required this.controller});

  @override
  State<CloseShiftDialog> createState() => _CloseShiftDialogState();
}

class _CloseShiftDialogState extends State<CloseShiftDialog> {
  final _actualCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _bridgeOffice = true;
  bool _printDirect = true;
  bool _busy = false;

  @override
  void dispose() {
    _actualCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final opened = c.activeShift.openedAt ?? DateTime.now().subtract(const Duration(hours: 8));
    final cashSales = c.transactions
        .where((t) => !t.isVoid && t.paymentMethod == 'Tunai' && t.date.isAfter(opened))
        .fold<double>(0, (s, t) => s + t.total);
    final expected = c.activeShift.initialCash + cashSales;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Tutup Shift Kasir', style: TextStyle(fontWeight: FontWeight.w900)),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: NfColors.lightBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _row('Modal Awal', NfFormatters.rupiah(c.activeShift.initialCash)),
                    _row('Penjualan Tunai Shift Ini', '+${NfFormatters.rupiah(cashSales)}'),
                    const Divider(),
                    _row('Target Uang di Laci', NfFormatters.rupiah(expected), bold: true),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _actualCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Uang Fisik Riil di Laci (Rp) *',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Catatan Tutup Shift (Opsional)',
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _bridgeOffice,
                onChanged: (v) => setState(() => _bridgeOffice = v ?? true),
                title: const Text('Setor otomatis ke Buku Kas NutriFresh Office', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _printDirect,
                onChanged: (v) => setState(() => _printDirect = v ?? true),
                title: const Text('Cetak Bukti Tutup Shift langsung ke Printer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Batal')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: NfColors.danger),
          onPressed: _busy
              ? null
              : () async {
                  final actual = double.tryParse(_actualCtrl.text.trim());
                  if (actual == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Masukkan nominal uang fisik riil di laci.')),
                    );
                    return;
                  }
                  setState(() => _busy = true);
                  try {
                    final rec = await c.closeShift(
                      actualCash: actual,
                      note: _noteCtrl.text.trim(),
                      bridgeDeposit: _bridgeOffice,
                    );
                    if (_printDirect) {
                      await PosPrintService.instance.printShiftReport(rec, c.settings);
                    }
                    if (context.mounted) Navigator.of(context).pop(true);
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: const Text('Tutup Shift'),
        ),
      ],
    );
  }

  Widget _row(String k, String v, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          Text(v, style: TextStyle(fontSize: bold ? 15 : 12, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
