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
  String _subTab = 'sales'; // sales | expenses | purchases | waste

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

  DateTime _parseDate(dynamic v) => DateTime.tryParse((v ?? '').toString()) ?? DateTime.now();

  Future<void> _addExpenseDialog() async {
    final descCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    final ok = await showNfGlassModal<bool>(
      context: context,
      style: widget.controller.uiStyle,
      title: 'Catat Kas Keluar Toko',
      subtitle: 'Pengeluaran operasional harian dari laci kasir',
      icon: Icons.money_off_rounded,
      headerGradient: const [Color(0xFFB45309), Color(0xFFF59E0B)],
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Keperluan (misal: Es Batu / Plastik) *')),
          const SizedBox(height: 10),
          TextField(controller: amtCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nominal (Rp) *')),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal'))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Simpan Kas Keluar'))),
            ],
          ),
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
        await widget.controller.syncAllData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kas keluar tercatat di server.')));
        }
      }
    }
    descCtrl.dispose();
    amtCtrl.dispose();
  }

  Future<void> _openReturnDialog(NfTransaction tx) async {
    if (tx.items.isEmpty) return;
    final c = widget.controller;
    int selectedIdx = 0;
    final qtyCtrl = TextEditingController(text: '${tx.items.first['qty'] ?? 1}');
    final reasonCtrl = TextEditingController(text: 'Tukar / Retur Pelanggan');
    bool restoreStock = true;

    final ok = await showNfGlassModal<bool>(
      context: context,
      style: c.uiStyle,
      title: 'Retur Item Nota ${tx.id}',
      subtitle: 'Pelanggan: ${tx.customerName}',
      icon: Icons.assignment_return_rounded,
      headerGradient: const [Color(0xFFD97706), Color(0xFFF59E0B)],
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) {
          final item = tx.items[selectedIdx];
          final unit = (item['unit'] ?? 'Gram').toString();
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                value: selectedIdx,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Pilih Item yang Diretur'),
                items: List.generate(
                  tx.items.length,
                  (i) => DropdownMenuItem(
                    value: i,
                    child: Text('${tx.items[i]['name']} (${NfFormatters.stockDisplay((tx.items[i]['qty'] as num?) ?? 0, (tx.items[i]['unit'] ?? 'Gram').toString())})'),
                  ),
                ),
                onChanged: (v) {
                  if (v != null) {
                    setM(() {
                      selectedIdx = v;
                      qtyCtrl.text = '${tx.items[v]['qty'] ?? 1}';
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Jumlah Retur (${NfFormatters.displayUnit(unit)})'),
              ),
              const SizedBox(height: 10),
              TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Alasan Retur *')),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: restoreStock,
                onChanged: (v) => setM(() => restoreStock = v ?? true),
                title: const Text('Kembalikan ke stok jual (jika buah masih layak)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Simpan Retur'),
              ),
            ],
          );
        },
      ),
    );

    if (ok == true) {
      final item = tx.items[selectedIdx];
      final retQty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
      final origQty = ((item['qty'] as num?) ?? 1).round();
      if (retQty > 0 && retQty <= origQty) {
        final actor = c.session?.name ?? 'Kasir';
        final unit = (item['unit'] ?? 'Gram').toString();
        final price = ((item['price'] as num?) ?? 0).toDouble();
        final refundRp = NfFormatters.roundToThousand((retQty / NfFormatters.unitDivisor(unit)) * price);

        if (restoreStock && item['skipStockDeduction'] != true) {
          await NfSupabaseService.instance.adjustStockAtomic(
            productId: item['id'].toString(),
            deltaQty: retQty,
            reason: 'Retur ${tx.id}: ${reasonCtrl.text.trim()}',
            refId: tx.id,
            actor: actor,
          );
        }

        final nextRaw = Map<String, dynamic>.from(tx.raw);
        final prevReturns = (nextRaw['returns'] is List) ? List<dynamic>.from(nextRaw['returns'] as List) : <dynamic>[];
        prevReturns.add({
          'date': DateTime.now().toIso8601String(),
          'itemName': item['name'],
          'qty': retQty,
          'unit': unit,
          'refundRp': refundRp,
          'reason': reasonCtrl.text.trim(),
          'actor': actor,
        });
        nextRaw['returns'] = prevReturns;
        nextRaw['total'] = (tx.total - refundRp).clamp(0.0, double.infinity).toDouble();
        await NfSupabaseService.instance.saveTransaction(nextRaw);
        await NfSupabaseService.instance.logAuditEvent(
          action: 'RETURN_ITEM',
          entityType: 'transaction',
          entityId: tx.id,
          summary: 'Retur ${item['name']} (${NfFormatters.stockDisplay(retQty, unit)}) senilai ${NfFormatters.rupiah(refundRp)}',
          actorName: actor,
          reason: reasonCtrl.text.trim(),
        );
        await c.syncAllData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Retur tercatat (${NfFormatters.rupiah(refundRp)}).')));
        }
      }
    }
    qtyCtrl.dispose();
    reasonCtrl.dispose();
  }

  Future<void> _confirmVoid(NfTransaction tx) async {
    final reasonCtrl = TextEditingController();
    final ok = await showNfGlassModal<bool>(
      context: context,
      style: widget.controller.uiStyle,
      title: 'Batalkan (VOID) ${tx.id}?',
      subtitle: 'Stok akan dikembalikan otomatis & tercatat di Audit Trail',
      icon: Icons.block_rounded,
      headerGradient: const [Color(0xFFB91C1C), Color(0xFFEF4444)],
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: reasonCtrl, autofocus: true, decoration: const InputDecoration(labelText: 'Alasan Pembatalan *')),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal'))),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: NfColors.danger),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Ya, VOID Nota'),
                ),
              ),
            ],
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
    final isWide = MediaQuery.of(context).size.width >= 760;

    final filteredTx = c.transactions.where((t) => _matchPeriod(t.date)).toList();
    final activeTx = filteredTx.where((t) => !t.isVoid).toList();
    final omset = activeTx.fold<double>(0, (s, t) => s + t.total);
    final profit = activeTx.fold<double>(0, (s, t) => s + t.grossProfit);
    final tunai = activeTx.where((t) => t.paymentMethod == 'Tunai').fold<double>(0, (s, t) => s + t.total);
    final nonTunai = omset - tunai;

    final filteredExp = c.expenses.where((e) => _matchPeriod(_parseDate(e['date']))).toList();
    final filteredPur = c.purchases.where((p) => _matchPeriod(_parseDate(p['date']))).toList();
    final filteredWst = c.wasteLogs.where((w) => _matchPeriod(_parseDate(w['date']))).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(12, 6, 12, isWide ? 20 : 94),
      children: [
        NfGlassSurface(
          style: c.uiStyle,
          borderRadius: 24,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.bar_chart_rounded, color: Color(0xFF2563EB), size: 20),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Laporan Operasional Toko', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900))),
                  FilledButton.tonalIcon(
                    onPressed: _addExpenseDialog,
                    icon: const Icon(Icons.money_off_rounded, size: 16),
                    label: const Text('Kas Keluar', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              NfSlidingSegmented<String>(
                style: c.uiStyle,
                greenActive: true,
                selected: _period,
                onChanged: (v) => setState(() => _period = v),
                items: const [
                  ('today', 'Hari Ini', null),
                  ('week', '7 Hari', null),
                  ('all', 'Terbaru', null),
                ],
              ),
              const SizedBox(height: 8),
              NfSlidingSegmented<String>(
                style: c.uiStyle,
                selected: _subTab,
                onChanged: (v) => setState(() => _subTab = v),
                items: const [
                  ('sales', 'Jual', null),
                  ('expenses', 'Kas Out', null),
                  ('purchases', 'Kulakan', null),
                  ('waste', 'Rusak', null),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (_subTab == 'sales') ...[
          GridView.count(
            crossAxisCount: isWide ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 9,
            crossAxisSpacing: 9,
            childAspectRatio: isWide ? 2.1 : 1.9,
            children: [
              _statCard(c.uiStyle, 'Omset (${activeTx.length} Nota)', NfFormatters.rupiah(omset), NfColors.greenDark),
              _statCard(c.uiStyle, 'Tunai Laci', NfFormatters.rupiah(tunai), const Color(0xFF0F766E)),
              _statCard(c.uiStyle, 'QRIS / Transfer', NfFormatters.rupiah(nonTunai), const Color(0xFF2563EB)),
              if (c.isOwnerUnlocked) _statCard(c.uiStyle, 'Laba Kotor', NfFormatters.rupiah(profit), NfColors.brown),
            ],
          ),
          const SizedBox(height: 12),
          if (filteredTx.isEmpty)
            _emptyCard(c.uiStyle, 'Belum ada transaksi pada periode ini.')
          else
            ...filteredTx.map((tx) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: NfGlassSurface(
                    style: c.uiStyle,
                    borderRadius: 20,
                    tintColor: tx.isVoid ? const Color(0xFFFEF2F2) : null,
                    padding: const EdgeInsets.all(13),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${tx.id} • ${tx.customerName}${tx.isVoid ? ' [VOID]' : ''}',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                              ),
                            ),
                            Text(NfFormatters.rupiah(tx.total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: NfColors.brown)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${NfFormatters.dateTimeShort(tx.date)} • ${tx.paymentMethod} • Kasir: ${tx.cashier}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => PosPrintService.instance.printReceipt(tx, c.settings),
                              icon: const Icon(Icons.print_rounded, size: 15, color: Color(0xFF2563EB)),
                              label: const Text('Cetak', style: TextStyle(fontSize: 11.5)),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => showDigitalReceiptGlassModal(
                                context: context,
                                style: c.uiStyle,
                                tx: tx,
                                settings: c.settings,
                              ),
                              icon: const Icon(Icons.receipt_long_rounded, size: 15, color: NfColors.greenDark),
                              label: const Text('Resi PNG/WA', style: TextStyle(fontSize: 11.5)),
                            ),
                            if (!tx.isVoid)
                              OutlinedButton.icon(
                                onPressed: () => _openReturnDialog(tx),
                                icon: const Icon(Icons.assignment_return_rounded, size: 15, color: Color(0xFFD97706)),
                                label: const Text('Retur', style: TextStyle(fontSize: 11.5)),
                              ),
                            if (!tx.isVoid && c.isOwnerUnlocked)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(foregroundColor: NfColors.danger),
                                onPressed: () => _confirmVoid(tx),
                                icon: const Icon(Icons.block_rounded, size: 15),
                                label: const Text('VOID', style: TextStyle(fontSize: 11.5)),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )),
        ] else if (_subTab == 'expenses') ...[
          _statCard(
            c.uiStyle,
            'Total Kas Keluar (${filteredExp.length})',
            NfFormatters.rupiah(filteredExp.fold<double>(0, (s, e) => s + ((e['amount'] as num?) ?? 0))),
            const Color(0xFFB45309),
          ),
          const SizedBox(height: 10),
          if (filteredExp.isEmpty)
            _emptyCard(c.uiStyle, 'Belum ada catatan kas keluar.')
          else
            ...filteredExp.map((e) => _simpleLogTile(
                  c.uiStyle,
                  title: (e['desc'] ?? '-').toString(),
                  sub: '${NfFormatters.dateTimeShort(_parseDate(e['date']))} • ${e['cashier'] ?? '-'}',
                  amount: '-${NfFormatters.rupiah((e['amount'] as num?) ?? 0)}',
                  color: NfColors.danger,
                )),
        ] else if (_subTab == 'purchases') ...[
          _statCard(
            c.uiStyle,
            'Total Kulakan (${filteredPur.length})',
            NfFormatters.rupiah(filteredPur.fold<double>(0, (s, p) => s + ((p['totalCost'] as num?) ?? 0))),
            const Color(0xFF0F766E),
          ),
          const SizedBox(height: 10),
          if (filteredPur.isEmpty)
            _emptyCard(c.uiStyle, 'Belum ada catatan kulakan pada periode ini.')
          else
            ...filteredPur.map((p) => _simpleLogTile(
                  c.uiStyle,
                  title: '${p['productName'] ?? '-'} (${NfFormatters.stockDisplay((p['qty'] as num?) ?? 0, (p['unit'] ?? 'Gram').toString())})',
                  sub: '${NfFormatters.dateTimeShort(_parseDate(p['date']))} • ${p['supplierName'] ?? '-'} • ${p['paymentStatus'] ?? 'Lunas'}',
                  amount: NfFormatters.rupiah((p['totalCost'] as num?) ?? 0),
                  color: const Color(0xFF0F766E),
                )),
        ] else ...[
          _statCard(
            c.uiStyle,
            'Total Nilai Buah Rusak / Susut (${filteredWst.length})',
            NfFormatters.rupiah(filteredWst.fold<double>(0, (s, w) => s + ((w['totalLoss'] as num?) ?? 0))),
            NfColors.danger,
          ),
          const SizedBox(height: 10),
          if (filteredWst.isEmpty)
            _emptyCard(c.uiStyle, 'Tidak ada catatan buah rusak pada periode ini.')
          else
            ...filteredWst.map((w) => _simpleLogTile(
                  c.uiStyle,
                  title: '${w['productName'] ?? '-'} (${NfFormatters.stockDisplay((w['qty'] as num?) ?? 0, (w['unit'] ?? 'Gram').toString())})',
                  sub: '${NfFormatters.dateTimeShort(_parseDate(w['date']))} • ${w['reason'] ?? '-'} • ${w['actor'] ?? '-'}',
                  amount: '-${NfFormatters.rupiah((w['totalLoss'] as num?) ?? 0)}',
                  color: NfColors.danger,
                )),
        ],
      ],
    );
  }

  Widget _emptyCard(NfUiStyle style, String msg) {
    return NfGlassSurface(
      style: style,
      borderRadius: 24,
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
      child: Center(child: Text(msg, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700))),
    );
  }

  Widget _simpleLogTile(NfUiStyle style, {required String title, required String sub, required String amount, required Color color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NfGlassSurface(
        style: style,
        borderRadius: 18,
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(sub, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ],
              ),
            ),
            Text(amount, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _statCard(NfUiStyle style, String label, String val, Color accent) {
    return NfGlassSurface(
      style: style,
      borderRadius: 20,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(val, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: accent)),
          ),
        ],
      ),
    );
  }
}
