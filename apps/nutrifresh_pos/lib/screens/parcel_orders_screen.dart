import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nf_core/nf_core.dart';
import '../services/pos_print_service.dart';
import '../state/pos_controller.dart';

class ParcelOrdersScreen extends StatefulWidget {
  final PosController controller;
  final VoidCallback onLoadedToCashier;

  const ParcelOrdersScreen({
    super.key,
    required this.controller,
    required this.onLoadedToCashier,
  });

  @override
  State<ParcelOrdersScreen> createState() => _ParcelOrdersScreenState();
}

class _ParcelOrdersScreenState extends State<ParcelOrdersScreen> {
  bool _showDone = false;

  Future<void> _openCreateManualPoModal() async {
    final c = widget.controller;
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final instCtrl = TextEditingController();
    final dateCtrl = TextEditingController(
      text: NfFormatters.ymd(DateTime.now().add(const Duration(days: 1))),
    );
    final timeCtrl = TextEditingController(text: '09:00');
    final addrCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: '100000');
    final qtyCtrl = TextEditingController(text: '1');
    final noteCtrl = TextEditingController();
    final dpCtrl = TextEditingController(text: '0');

    String selectedType = 'Parcel Keranjang';
    String deliveryMode = 'Diantar';
    String payStatus = 'Belum Bayar';

    final types = [
      'Parcel Keranjang',
      'Parcel Piringan',
      'Parcel Box',
      'Buket Buah',
      'Paket Buah Acara',
      'Custom',
    ];

    final ok = await showNfGlassModal<bool>(
      context: context,
      style: c.uiStyle,
      title: 'Input PO Parsel Manual',
      subtitle: 'Langsung masuk jadwal & siap cetak stiker thermal',
      icon: Icons.card_giftcard_rounded,
      headerGradient: const [Color(0xFF558B2F), Color(0xFFD97706)],
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) {
          final qty = int.tryParse(qtyCtrl.text.trim()) ?? 1;
          final price = double.tryParse(priceCtrl.text.trim()) ?? 0;
          final estTot = qty * price;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama Pemesan *'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'No. WA *'))),
                ],
              ),
              const SizedBox(height: 10),
              TextField(controller: instCtrl, decoration: const InputDecoration(labelText: 'Instansi / Acara (Opsional)')),
              const SizedBox(height: 12),
              const Text('Bentuk / Jenis Paket:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: types.map((t) {
                  final act = selectedType == t;
                  return InkWell(
                    onTap: () => setM(() => selectedType = t),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: act ? NfColors.green : Colors.white,
                        border: Border.all(color: act ? NfColors.greenDark : const Color(0xFFD5E0D9)),
                      ),
                      child: Text(
                        t,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: act ? Colors.white : const Color(0xFF334155)),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [15000, 30000, 50000, 100000, 150000, 250000].map((bp) {
                  return InkWell(
                    onTap: () => setM(() => priceCtrl.text = bp.toString()),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFFCD34D)),
                      ),
                      child: Text('${bp ~/ 1000}rb', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF92400E))),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Budget / Satuan (Rp)'),
                      onChanged: (_) => setM(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Qty'),
                      onChanged: (_) => setM(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: TextField(controller: dateCtrl, decoration: const InputDecoration(labelText: 'Tanggal (YYYY-MM-DD)'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: timeCtrl, decoration: const InputDecoration(labelText: 'Jam'))),
                ],
              ),
              const SizedBox(height: 10),
              NfSlidingSegmented<String>(
                style: c.uiStyle,
                greenActive: true,
                selected: deliveryMode,
                onChanged: (v) => setM(() => deliveryMode = v),
                items: const [
                  ('Diantar', 'Diantar Kurir', Icons.local_shipping_rounded),
                  ('Diambil', 'Diambil di Toko', Icons.store_rounded),
                ],
              ),
              if (deliveryMode == 'Diantar') ...[
                const SizedBox(height: 10),
                TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: 'Alamat Tujuan Pengantaran')),
              ],
              const SizedBox(height: 10),
              TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Request Isi Buah / Pita / Kartu Ucapan')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: payStatus,
                      decoration: const InputDecoration(labelText: 'Status Bayar'),
                      items: const [
                        DropdownMenuItem(value: 'Belum Bayar', child: Text('Belum Bayar')),
                        DropdownMenuItem(value: 'DP', child: Text('Sudah DP')),
                        DropdownMenuItem(value: 'Lunas', child: Text('Lunas')),
                      ],
                      onChanged: (v) => setM(() => payStatus = v ?? 'Belum Bayar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: dpCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Nominal DP (Rp)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: NfColors.lightBg, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Estimasi PO:', style: TextStyle(fontWeight: FontWeight.w800)),
                    Text(NfFormatters.rupiah(estTot), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: NfColors.brown)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal'))),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Simpan PO Parsel'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      final qty = (int.tryParse(qtyCtrl.text.trim()) ?? 1).clamp(1, 999).toInt();
      final price = double.tryParse(priceCtrl.text.trim()) ?? 0;
      final tot = qty * price;
      final dp = payStatus == 'Lunas' ? tot : (double.tryParse(dpCtrl.text.trim()) ?? 0);
      final code = NfFormatters.generateId('PO');
      await NfSupabaseService.instance.createManualParcelOrder(
        id: code,
        orderCode: code,
        customerName: nameCtrl.text.trim(),
        customerPhone: NfFormatters.normalizeWaPhone(phoneCtrl.text.trim()),
        institution: instCtrl.text.trim(),
        deliveryDate: dateCtrl.text.trim().isEmpty ? NfFormatters.ymd(DateTime.now()) : dateCtrl.text.trim(),
        deliveryTime: timeCtrl.text.trim().isEmpty ? '09:00' : timeCtrl.text.trim(),
        totalAmount: tot,
        dpAmount: dp,
        paymentStatus: payStatus,
        orderStatus: 'Dikonfirmasi',
        items: [
          {
            'parcelType': selectedType,
            'qty': qty,
            'unitPrice': price,
            'subtotal': tot,
            'deliveryMode': deliveryMode,
            'deliveryDate': dateCtrl.text.trim(),
            'deliveryTime': timeCtrl.text.trim(),
            'note': noteCtrl.text.trim(),
            'destinations': [
              {
                'address': deliveryMode == 'Diambil' ? 'DIAMBIL DI TOKO' : addrCtrl.text.trim(),
                'qty': qty,
                'delivered': false,
              }
            ],
          }
        ],
      );
      await c.syncAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PO Parsel $code berhasil dicatat!')),
        );
      }
    }

    nameCtrl.dispose();
    phoneCtrl.dispose();
    instCtrl.dispose();
    dateCtrl.dispose();
    timeCtrl.dispose();
    addrCtrl.dispose();
    priceCtrl.dispose();
    qtyCtrl.dispose();
    noteCtrl.dispose();
    dpCtrl.dispose();
  }

  Future<void> _openUpdateDpModal(NfParcelOrder po) async {
    final dpCtrl = TextEditingController(text: po.dpAmount.round().toString());
    String status = po.paymentStatus;
    final ok = await showNfGlassModal<bool>(
      context: context,
      style: widget.controller.uiStyle,
      title: 'Catat DP / Pembayaran PO',
      subtitle: '${po.orderCode} • Total ${NfFormatters.rupiah(po.totalAmount)}',
      icon: Icons.payments_rounded,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: ['Belum Bayar', 'DP', 'Lunas'].contains(status) ? status : 'Belum Bayar',
              decoration: const InputDecoration(labelText: 'Status Bayar'),
              items: const [
                DropdownMenuItem(value: 'Belum Bayar', child: Text('Belum Bayar')),
                DropdownMenuItem(value: 'DP', child: Text('Sudah DP')),
                DropdownMenuItem(value: 'Lunas', child: Text('Lunas')),
              ],
              onChanged: (v) => setM(() {
                status = v ?? 'Belum Bayar';
                if (status == 'Lunas') dpCtrl.text = po.totalAmount.round().toString();
              }),
            ),
            const SizedBox(height: 10),
            TextField(controller: dpCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nominal DP / Masuk (Rp)')),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Simpan Pembayaran'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      final dp = double.tryParse(dpCtrl.text.trim()) ?? po.dpAmount;
      await NfSupabaseService.instance.updateParcelOrderStatus(po, paymentStatus: status, dpAmount: dp);
      await widget.controller.syncAllData();
    }
    dpCtrl.dispose();
  }

  void _copyTeamRecap(List<NfParcelOrder> activeList) {
    if (activeList.isEmpty) return;
    final buf = StringBuffer('📋 *REKAP JADWAL PO PARSEL NUTRIFRESH*\n\n');
    for (final po in activeList) {
      buf.writeln('🗓️ *${po.deliveryDate} (${po.deliveryTime})* — ${po.orderCode}');
      buf.writeln('👤 ${po.customerName}${po.institution.isNotEmpty ? ' (${po.institution})' : ''}');
      for (final it in po.items) {
        buf.writeln('  ▪️ ${it['qty'] ?? 1}x ${it['parcelType'] ?? 'Parcel'} @${NfFormatters.rupiah((it['unitPrice'] as num?) ?? 0)} [${it['deliveryMode'] ?? 'Diantar'}]${(it['note'] ?? '').toString().isNotEmpty ? ' — ${it['note']}' : ''}');
      }
      buf.writeln('  💰 ${po.paymentStatus} (Total ${NfFormatters.rupiah(po.totalAmount)})\n');
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rekap jadwal tim perakit disalin ke clipboard!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final list = c.parcelOrders.where((p) => _showDone ? p.isClosed : !p.isClosed).toList();
    final isWide = MediaQuery.of(context).size.width >= 760;

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
                  const Icon(Icons.card_giftcard_rounded, color: Color(0xFFD97706), size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Papan Jadwal PO Parsel', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900)),
                  ),
                  FilledButton.icon(
                    onPressed: _openCreateManualPoModal,
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: const Text('Input PO', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Cetak stiker PO langsung tanpa pop-up, catat DP, & selesaikan ke kasir',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              NfSlidingSegmented<bool>(
                style: c.uiStyle,
                greenActive: true,
                selected: _showDone,
                onChanged: (v) => setState(() => _showDone = v),
                items: const [
                  (false, 'Jadwal Aktif', Icons.event_note_rounded),
                  (true, 'Selesai / Batal', Icons.check_circle_outline_rounded),
                ],
              ),
              if (!_showDone && list.isNotEmpty) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _copyTeamRecap(list),
                  icon: const Icon(Icons.copy_all_rounded, size: 16),
                  label: const Text('Salin Rekap WA Tim Perakit', style: TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          NfGlassSurface(
            style: c.uiStyle,
            borderRadius: 24,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 38),
            child: Column(
              children: [
                const Icon(Icons.card_giftcard_outlined, size: 42, color: Color(0xFF94A3B8)),
                const SizedBox(height: 10),
                const Text('Belum ada pesanan PO Parsel.', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF475569))),
                const SizedBox(height: 4),
                const Text(
                  'PO dari pelanggan maupun input manual kasir (Parcel Keranjang, Piringan, Box, Buket) akan tampil di sini.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: _openCreateManualPoModal,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Catat PO Parsel Baru'),
                ),
              ],
            ),
          )
        else
          ...list.map((po) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: NfGlassSurface(
                style: c.uiStyle,
                borderRadius: 24,
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(999)),
                          child: Text('${po.deliveryDate} • ${po.deliveryTime}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Color(0xFF92400E))),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(po.orderCode, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF475569))),
                        ),
                        Text(NfFormatters.rupiah(po.totalAmount), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5, color: NfColors.brown)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${po.customerName}${po.institution.isNotEmpty ? ' (${po.institution})' : ''}  •  ${NfFormatters.localWaDisplay(po.customerPhone)}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    Text(
                      'Status: ${po.orderStatus}  •  Bayar: ${po.paymentStatus}${po.dpAmount > 0 ? ' (DP ${NfFormatters.rupiah(po.dpAmount)}, Sisa ${NfFormatters.rupiah(po.remainingAmount)})' : ''}',
                      style: const TextStyle(fontSize: 11.5, color: NfColors.greenDark, fontWeight: FontWeight.w700),
                    ),
                    const Divider(height: 16),
                    ...po.items.map((it) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          '• ${it['qty'] ?? 1}x ${it['parcelType'] ?? 'Parcel'} @${NfFormatters.rupiah((it['unitPrice'] as num?) ?? 0)} (${it['deliveryMode'] ?? 'Diantar'})${(it['note'] ?? '').toString().isNotEmpty ? ' — ${it['note']}' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () => PosPrintService.instance.printParcelStickers(po, c.settings),
                          icon: const Icon(Icons.print_rounded, size: 17),
                          label: const Text('Cetak Stiker'),
                        ),
                        if (!po.isClosed)
                          FilledButton.tonalIcon(
                            onPressed: () {
                              c.loadParcelOrderToCart(po);
                              widget.onLoadedToCashier();
                            },
                            icon: const Icon(Icons.point_of_sale_rounded, size: 17),
                            label: const Text('Ke Kasir'),
                          ),
                        if (!po.isClosed)
                          OutlinedButton(
                            onPressed: () => _openUpdateDpModal(po),
                            child: const Text('DP / Bayar'),
                          ),
                        if (!po.isClosed)
                          OutlinedButton(
                            onPressed: () async {
                              final next = po.orderStatus == 'Menunggu Konfirmasi'
                                  ? 'Dikonfirmasi'
                                  : (po.orderStatus == 'Dikonfirmasi' ? 'Dirakit' : 'Siap Antar');
                              await NfSupabaseService.instance.updateParcelOrderStatus(po, orderStatus: next);
                              await c.syncAllData();
                            },
                            child: Text(po.orderStatus == 'Dirakit' ? 'Siap Antar' : 'Lanjut Status'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
