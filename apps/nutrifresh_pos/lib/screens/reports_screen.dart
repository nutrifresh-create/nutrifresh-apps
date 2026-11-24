import 'package:flutter/material.dart';
import 'package:nf_core/nf_core.dart';
import '../services/pos_print_service.dart';
import '../state/pos_controller.dart';
import '../widgets/digital_receipt_dialog.dart';

class ReportsScreen extends StatefulWidget {
  final PosController controller;
  const ReportsScreen({super.key, required this.controller});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _period = 'today'; // today | week | all

  bool _matchPeriod(DateTime dt) {
    final now = DateTime.now();
    final local = dt.toLocal();
    if (_period == 'today') {
      return local.year == now.year && local.month == now.month && local.day == now.day;
    }
    if (_period == 'week') {
      return now.difference(local).inDays < 7;
    }
    return true;
  }

  Future<void> _addExpenseDialog() async {
    final descCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Catat Kas Keluar Toko', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Keperluan (misal: Es Batu / Plastik)')),
              const SizedBox(height: 10),
              TextField(controller: amtCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nominal (Rp)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Simpan')),
        ],
      ),
    );
    if (ok == true) {
      final amt = double.tryParse(amtCtrl.text.trim()) ?? 0;
      if (amt > 0 && descCtrl.text.trim().isNotEmpty) {
        await NfSupabaseService.instance.addExpense(
          id: NfFormatters.generateId('EXP'),
          cashier: widget.controller.session?.name ?? 'Kasir',
          desc: descCtrl.text.trim(),
          amount: amt,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kas keluar tercatat di server.')),
          );
        }
      }
    }
    descCtrl.dispose();
    amtCtrl.dispose();
  }

  Future<void> _confirmVoid(NfTransaction tx) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Batalkan (VOID) ${tx.id}?', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Alasan Pembatalan *'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NfColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ya, VOID & Kembalikan Stok'),
          ),
        ],
      ),
    );
    if (ok == true && reasonCtrl.text.trim().isNotEmpty) {
      await widget.controller.voidTransaction(tx, reasonCtrl.text.trim());
    }
    reasonCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final filtered = c.transactions.where((t) => _matchPeriod(t.date)).toList();
    final activeTx = filtered.where((t) => !t.isVoid).toList();
    final omset = activeTx.fold<double>(0, (s, t) => s + t.total);
    final profit = activeTx.fold<double>(0, (s, t) => s + t.grossProfit);
    final tunai = activeTx.where((t) => t.paymentMethod == 'Tunai').fold<double>(0, (s, t) => s + t.total);
    final nonTunai = omset - tunai;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'today', label: Text('Hari Ini')),
                  ButtonSegment(value: 'week', label: Text('7 Hari')),
                  ButtonSegment(value: 'all', label: Text('Terbaru')),
                ],
                selected: {_period},
                onSelectionChanged: (s) => setState(() => _period = s.first),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _addExpenseDialog,
                icon: const Icon(Icons.money_off_rounded, size: 18),
                label: const Text('Catat Kas Keluar'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _statCard('Omset (${activeTx.length} Nota)', NfFormatters.rupiah(omset), NfColors.greenDark),
              _statCard('Tunai Laci', NfFormatters.rupiah(tunai), const Color(0xFF0F766E)),
              _statCard('QRIS / Transfer', NfFormatters.rupiah(nonTunai), const Color(0xFF2563EB)),
              if (c.isOwnerUnlocked) _statCard('Laba Kotor', NfFormatters.rupiah(profit), NfColors.brown),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('Belum ada transaksi pada periode ini.', style: TextStyle(color: Color(0xFF64748B))))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, idx) {
                    final tx = filtered[idx];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: tx.isVoid ? const Color(0xFFFEF2F2) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${tx.id}  •  ${tx.customerName} (${tx.paymentMethod})${tx.isVoid ? '  [VOID]' : ''}',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                ),
                                Text(
                                  '${NfFormatters.dateTimeShort(tx.date)} • Kasir: ${tx.cashier} • ${tx.items.length} item',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            NfFormatters.rupiah(tx.total),
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: NfColors.brown),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: 'Cetak Struk',
                            icon: const Icon(Icons.print_rounded, color: Color(0xFF2563EB)),
                            onPressed: () => PosPrintService.instance.printReceipt(tx, c.settings),
                          ),
                          IconButton(
                            tooltip: 'Resi Digital PNG / WA',
                            icon: const Icon(Icons.receipt_long_rounded, color: NfColors.greenDark),
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) => DigitalReceiptDialog(tx: tx, settings: c.settings),
                            ),
                          ),
                          if (!tx.isVoid && c.isOwnerUnlocked)
                            IconButton(
                              tooltip: 'Batalkan (VOID)',
                              icon: const Icon(Icons.block_rounded, color: NfColors.danger),
                              onPressed: () => _confirmVoid(tx),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _statCard(String label, String val, Color accent) {
    return Container(
      width: 185,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
          const SizedBox(height: 4),
          Text(val, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: accent)),
        ],
      ),
    );
  }
}
