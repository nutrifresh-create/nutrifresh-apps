import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final list = c.parcelOrders.where((p) => _showDone ? p.isClosed : !p.isClosed).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Papan Jadwal Pre-Order Parsel', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                    Text('Cetak stiker PO langsung ke printer thermal & selesaikan ke kasir', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  ],
                ),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Jadwal Aktif')),
                  ButtonSegment(value: true, label: Text('Selesai')),
                ],
                selected: {_showDone},
                onSelectionChanged: (s) => setState(() => _showDone = s.first),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('Belum ada pesanan PO Parsel.', style: TextStyle(color: Color(0xFF64748B))))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, idx) {
                    final po = list[idx];
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
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
                              Text(po.orderCode, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF475569))),
                              const Spacer(),
                              Text(NfFormatters.rupiah(po.totalAmount), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: NfColors.brown)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${po.customerName}${po.institution.isNotEmpty ? ' (${po.institution})' : ''}  •  ${NfFormatters.localWaDisplay(po.customerPhone)}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                          Text(
                            'Status: ${po.orderStatus}  •  Bayar: ${po.paymentStatus}${po.dpAmount > 0 ? ' (DP ${NfFormatters.rupiah(po.dpAmount)}, Sisa ${NfFormatters.rupiah(po.remainingAmount)})' : ''}',
                            style: const TextStyle(fontSize: 12, color: NfColors.greenDark, fontWeight: FontWeight.w700),
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
                                label: const Text('Cetak Stiker PO'),
                              ),
                              if (!po.isClosed)
                                FilledButton.tonalIcon(
                                  onPressed: () {
                                    c.loadParcelOrderToCart(po);
                                    widget.onLoadedToCashier();
                                  },
                                  icon: const Icon(Icons.point_of_sale_rounded, size: 17),
                                  label: const Text('Selesaikan ke Kasir'),
                                ),
                              if (!po.isClosed)
                                OutlinedButton(
                                  onPressed: () async {
                                    final next = po.orderStatus == 'Menunggu Konfirmasi' ? 'Dirakit' : 'Siap Antar';
                                    await NfSupabaseService.instance.updateParcelOrderStatus(po, orderStatus: next);
                                    await c.syncAllData();
                                  },
                                  child: Text(po.orderStatus == 'Menunggu Konfirmasi' ? 'Tandai Dirakit' : 'Tandai Siap Antar'),
                                ),
                            ],
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
}
