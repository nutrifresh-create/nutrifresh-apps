import 'package:flutter/material.dart';
import 'package:nf_core/nf_core.dart';
import '../services/pos_print_service.dart';
import '../state/pos_controller.dart';

Future<bool?> showOpenShiftGlassModal({
  required BuildContext context,
  required PosController controller,
}) {
  return showNfGlassModal<bool>(
    context: context,
    style: controller.uiStyle,
    title: 'Buka Kasir (Shift Baru)',
    subtitle: 'Kasir bertugas: ${controller.session?.name ?? '-'}',
    icon: Icons.lock_open_rounded,
    headerGradient: const [Color(0xFF558B2F), Color(0xFF7CB342)],
    builder: (_) => _OpenShiftContent(controller: controller),
  );
}

class _OpenShiftContent extends StatefulWidget {
  final PosController controller;
  const _OpenShiftContent({required this.controller});

  @override
  State<_OpenShiftContent> createState() => _OpenShiftContentState();
}

class _OpenShiftContentState extends State<_OpenShiftContent> {
  final _cashCtrl = TextEditingController(text: '200000');
  bool _busy = false;

  @override
  void dispose() {
    _cashCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _cashCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          decoration: const InputDecoration(
            labelText: 'Modal Awal Laci Kasir (Rp)',
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                child: const Text('Batal'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
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
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Buka Kasir Sekarang'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Future<bool?> showCloseShiftGlassModal({
  required BuildContext context,
  required PosController controller,
}) {
  return showNfGlassModal<bool>(
    context: context,
    style: controller.uiStyle,
    title: 'Tutup Shift Kasir',
    subtitle: 'Hitung fisik uang laci & sinkron ke Buku Kas Office',
    icon: Icons.lock_rounded,
    headerGradient: const [Color(0xFFB91C1C), Color(0xFFEF4444)],
    builder: (_) => _CloseShiftContent(controller: controller),
  );
}

class _CloseShiftContent extends StatefulWidget {
  final PosController controller;
  const _CloseShiftContent({required this.controller});

  @override
  State<_CloseShiftContent> createState() => _CloseShiftContentState();
}

class _CloseShiftContentState extends State<_CloseShiftContent> {
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NfColors.lightBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: NfColors.green.withAlpha(90)),
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
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          decoration: const InputDecoration(labelText: 'Uang Fisik Riil di Laci (Rp) *'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _noteCtrl,
          decoration: const InputDecoration(labelText: 'Catatan Tutup Shift (Opsional)'),
        ),
        const SizedBox(height: 6),
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
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                child: const Text('Batal'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
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
                icon: const Icon(Icons.lock_rounded),
                label: const Text('Tutup Shift'),
              ),
            ),
          ],
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
          Text(v, style: TextStyle(fontSize: bold ? 15.5 : 12, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
