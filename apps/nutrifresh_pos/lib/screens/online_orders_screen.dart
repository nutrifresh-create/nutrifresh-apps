import 'package:flutter/material.dart';
import 'package:nf_core/nf_core.dart';
import 'package:url_launcher/url_launcher.dart';
import '../state/pos_controller.dart';

class OnlineOrdersScreen extends StatefulWidget {
  final PosController controller;
  final VoidCallback onLoadedToCashier;

  const OnlineOrdersScreen({
    super.key,
    required this.controller,
    required this.onLoadedToCashier,
  });

  @override
  State<OnlineOrdersScreen> createState() => _OnlineOrdersScreenState();
}

class _OnlineOrdersScreenState extends State<OnlineOrdersScreen> {
  bool _showClosed = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final list = c.onlineOrders.where((o) => _showClosed ? o.isClosed : !o.isClosed).toList();

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
                    Text('Antrean Order Katalog (Skema A)', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                    Text('Timbang riil di Kasir → Kirim Tagihan ke Aplikasi Pelanggan → Bayar', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  ],
                ),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Aktif')),
                  ButtonSegment(value: true, label: Text('Selesai')),
                ],
                selected: {_showClosed},
                onSelectionChanged: (s) => setState(() => _showClosed = s.first),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('Belum ada pesanan online pada tab ini.', style: TextStyle(color: Color(0xFF64748B))))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, idx) {
                    final ord = list[idx];
                    final items = ord.weighedItems.isNotEmpty ? ord.weighedItems : ord.items;
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
                                decoration: BoxDecoration(
                                  color: NfColors.lightBg,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(ord.orderCode, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: ord.orderStatus == 'Menunggu Pembayaran'
                                      ? const Color(0xFFDBEAFE)
                                      : const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(ord.orderStatus, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
                              ),
                              const Spacer(),
                              Text(
                                NfFormatters.rupiah(ord.finalTotal > 0 ? ord.finalTotal : ord.estimatedTotal),
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: NfColors.brown),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${ord.customerName}  •  ${NfFormatters.localWaDisplay(ord.customerPhone)}  •  ${ord.deliveryMode} (${ord.paymentMethod})',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                          if (ord.address.isNotEmpty)
                            Text('📍 ${ord.address}', style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                          const Divider(height: 18),
                          ...items.map((it) {
                            final qty = (it['qty'] as num?) ?? 0;
                            final unit = (it['unit'] ?? 'Gram').toString();
                            final sub = (it['subtotal'] as num?) ?? 0;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(child: Text('• ${NfFormatters.stockDisplay(qty, unit)}  ${it['name']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                                  Text(NfFormatters.rupiah(sub), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (!ord.isClosed)
                                FilledButton.icon(
                                  onPressed: () {
                                    final missing = c.loadOnlineOrderToCart(ord);
                                    widget.onLoadedToCashier();
                                    if (missing.isNotEmpty && context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Item stok habis/tidak ditemukan dilewati: ${missing.join(', ')}')),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.scale_rounded, size: 18),
                                  label: const Text('Timbang & Muat ke Kasir'),
                                ),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final ph = NfFormatters.normalizeWaPhone(ord.customerPhone);
                                  if (ph.length < 10) return;
                                  final msg = 'Halo Kak ${ord.customerName}, kami dari NutriFresh mengonfirmasi Order ${ord.orderCode}.';
                                  await launchUrl(
                                    Uri.parse('https://wa.me/$ph?text=${Uri.encodeComponent(msg)}'),
                                    mode: LaunchMode.externalApplication,
                                  );
                                },
                                icon: const Icon(Icons.chat_rounded, size: 16, color: Color(0xFF16A34A)),
                                label: const Text('Chat WA'),
                              ),
                              if (!ord.isClosed)
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(foregroundColor: NfColors.danger),
                                  onPressed: () async {
                                    await NfSupabaseService.instance.updateOnlineOrder(ord, status: 'Dibatalkan');
                                    await c.syncAllData();
                                  },
                                  child: const Text('Batalkan'),
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
