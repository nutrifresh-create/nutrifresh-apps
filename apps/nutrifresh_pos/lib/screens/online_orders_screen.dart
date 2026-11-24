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
              const Row(
                children: [
                  Icon(Icons.shopping_bag_rounded, color: NfColors.greenDark, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Antrean Order Katalog (Skema A)',
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              const Text(
                'Timbang riil di Kasir → Kirim Tagihan ke Aplikasi Pelanggan → Bayar',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              NfSlidingSegmented<bool>(
                style: c.uiStyle,
                greenActive: true,
                selected: _showClosed,
                onChanged: (v) => setState(() => _showClosed = v),
                items: const [
                  (false, 'Antrean Aktif', Icons.hourglass_top_rounded),
                  (true, 'Selesai / Batal', Icons.check_circle_outline_rounded),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          NfGlassSurface(
            style: c.uiStyle,
            borderRadius: 24,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 38),
            child: const Column(
              children: [
                Icon(Icons.shopping_bag_outlined, size: 42, color: Color(0xFF94A3B8)),
                SizedBox(height: 10),
                Text(
                  'Belum ada pesanan online pada tab ini.',
                  style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF475569)),
                ),
                SizedBox(height: 4),
                Text(
                  'Order buah dari katalog nutrifresh.my.id akan langsung masuk ke sini secara real-time.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          )
        else
          ...list.map((ord) {
            final items = ord.weighedItems.isNotEmpty ? ord.weighedItems : ord.items;
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
                          decoration: BoxDecoration(
                            color: NfColors.lightBg,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(ord.orderCode, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: ord.orderStatus == 'Menunggu Pembayaran'
                                ? const Color(0xFFDBEAFE)
                                : const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(ord.orderStatus, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10.5)),
                        ),
                        const Spacer(),
                        Text(
                          NfFormatters.rupiah(ord.finalTotal > 0 ? ord.finalTotal : ord.estimatedTotal),
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5, color: NfColors.brown),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${ord.customerName}  •  ${NfFormatters.localWaDisplay(ord.customerPhone)}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    Text(
                      '${ord.deliveryMode} • Bayar: ${ord.paymentMethod}',
                      style: const TextStyle(fontSize: 11.5, color: NfColors.greenDark, fontWeight: FontWeight.w700),
                    ),
                    if (ord.address.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('📍 ${ord.address}', style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569))),
                      ),
                    const Divider(height: 16),
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
                                  SnackBar(content: Text('Item stok habis dilewati: ${missing.join(', ')}')),
                                );
                              }
                            },
                            icon: const Icon(Icons.scale_rounded, size: 17),
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
              ),
            );
          }),
      ],
    );
  }
}
