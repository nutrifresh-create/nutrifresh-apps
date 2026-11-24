import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nf_core/nf_core.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/pos_print_service.dart';
import '../state/pos_controller.dart';
import '../widgets/digital_receipt_dialog.dart';
import '../widgets/payment_dialog.dart';
import '../widgets/shift_dialog.dart';
import '../widgets/weight_qty_dialog.dart';

class CashierScreen extends StatefulWidget {
  final PosController controller;
  final VoidCallback onOpenOnlineOrders;

  const CashierScreen({
    super.key,
    required this.controller,
    required this.onOpenOnlineOrders,
  });

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  final _searchCtrl = TextEditingController();
  final _memberSearchCtrl = TextEditingController();
  String _selectedCategory = 'Semua';

  @override
  void dispose() {
    _searchCtrl.dispose();
    _memberSearchCtrl.dispose();
    super.dispose();
  }

  List<String> _categories(List<NfProduct> inv) {
    final set = <String>{'Semua'};
    for (final p in inv) {
      if (p.category.isNotEmpty && p.category != '📦 Bahan & Perlengkapan') {
        set.add(p.category);
      }
    }
    return set.toList();
  }

  Future<void> _tapProduct(NfProduct p) async {
    final c = widget.controller;
    if (!c.activeShift.isOpen) {
      final opened = await showDialog<bool>(
        context: context,
        builder: (_) => OpenShiftDialog(controller: c),
      );
      if (opened != true) return;
    }
    if (p.stock <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stok "${p.name}" sedang habis.')),
      );
      return;
    }

    final existingIdx = c.cart.indexWhere((x) => x.product.id == p.id && x.linkedPoId == null);
    final initQty = existingIdx >= 0
        ? c.cart[existingIdx].qty
        : (p.unit == 'Gram' ? (p.stock >= 1000 ? 1000 : p.stock) : 1);
    final initNote = existingIdx >= 0 ? c.cart[existingIdx].itemNote : '';

    if (!mounted) return;
    final res = await showDialog<WeightQtyResult>(
      context: context,
      builder: (_) => WeightQtyDialog(
        product: p,
        buyerMode: c.buyerMode,
        initialQty: initQty,
        initialNote: initNote,
      ),
    );
    if (res != null) {
      c.addOrUpdateCartItem(p, res.qty, customNominal: res.customNominal, note: res.note);
    }
  }

  void _handleBarcodeOrSearchSubmit(String raw) {
    final q = raw.trim();
    if (q.isEmpty) return;
    final exact = widget.controller.inventory.where(
      (p) => p.active && p.barcode.isNotEmpty && p.barcode.toLowerCase() == q.toLowerCase(),
    );
    if (exact.isNotEmpty) {
      _searchCtrl.clear();
      setState(() {});
      _tapProduct(exact.first);
    }
  }

  Future<void> _openPayment() async {
    final c = widget.controller;
    if (c.cart.isEmpty) return;
    if (!c.activeShift.isOpen) {
      final opened = await showDialog<bool>(
        context: context,
        builder: (_) => OpenShiftDialog(controller: c),
      );
      if (opened != true) return;
    }
    if (!mounted) return;
    final tx = await showDialog<NfTransaction>(
      context: context,
      builder: (_) => PaymentDialog(controller: c),
    );
    if (tx != null && mounted) {
      // Cetak langsung jika printer default sudah terpasang
      if (PosPrintService.instance.defaultPrinterName != null) {
        PosPrintService.instance.printReceipt(tx, c.settings).catchError((_) {});
      }
      await showDialog<void>(
        context: context,
        builder: (_) => DigitalReceiptDialog(tx: tx, settings: c.settings, justPaid: true),
      );
    }
  }

  Future<void> _sendSkemaABillDialog() async {
    final c = widget.controller;
    final ord = c.linkedOnlineOrder;
    if (ord == null || c.cart.isEmpty) return;
    final shipCtrl = TextEditingController(
      text: ord.shippingFee > 0 ? ord.shippingFee.round().toString() : '0',
    );
    final sendAlsoWa = ValueNotifier<bool>(false);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Kirim Tagihan Timbang Riil (Skema A)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Order ${ord.orderCode} • ${ord.customerName}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Total Buah Hasil Timbang: ${NfFormatters.rupiah(c.cartGrandTotal)}', style: const TextStyle(color: NfColors.greenDark, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              TextField(
                controller: shipCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Ongkir Kurir Toko (Rp)',
                  hintText: '0 jika gratis / ambil di toko',
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<bool>(
                valueListenable: sendAlsoWa,
                builder: (_, val, __) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: val,
                  onChanged: (v) => sendAlsoWa.value = v ?? false,
                  title: const Text('Sekalian buka WhatsApp untuk info tambahan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.send_rounded),
            label: const Text('Kirim Tagihan ke Pelanggan'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final ship = double.tryParse(shipCtrl.text.trim()) ?? 0;
      await c.sendSkemaABillToCustomer(shippingFee: ship);
      if (sendAlsoWa.value) {
        final ph = NfFormatters.normalizeWaPhone(ord.customerPhone);
        if (ph.length >= 10) {
          final finalTot = c.cartGrandTotal + ship.round();
          final resiUrl = '${NfConfig.publicWebOrigin}/?resi=${Uri.encodeComponent(ord.orderCode)}&k=${Uri.encodeComponent(ord.receiptToken)}';
          final msg = 'Halo Kak *${ord.customerName}* 🍐\nPesanan *${ord.orderCode}* selesai kami pilih & timbang riil.\n'
              'Total Akhir: *${NfFormatters.rupiah(finalTot)}*${ship > 0 ? ' (termasuk ongkir ${NfFormatters.rupiah(ship)})' : ''}\n'
              'Pembayaran: *${ord.paymentMethod}*\n\n🧾 Rincian & Status:\n$resiUrl';
          await launchUrl(Uri.parse('https://wa.me/$ph?text=${Uri.encodeComponent(msg)}'), mode: LaunchMode.externalApplication);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tagihan ${ord.orderCode} terkirim (Status: Menunggu Pembayaran).')),
        );
      }
    }
    shipCtrl.dispose();
    sendAlsoWa.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = c.inventory.where((p) {
      if (!p.active || p.category == '📦 Bahan & Perlengkapan') return false;
      if (_selectedCategory != 'Semua' && p.category != _selectedCategory) return false;
      if (query.isNotEmpty) {
        return p.name.toLowerCase().contains(query) || p.barcode.toLowerCase().contains(query);
      }
      return true;
    }).toList();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): _openPayment,
        const SingleActivator(LogicalKeyboardKey.f4): () => c.holdCurrentBill(),
      },
      child: Focus(
        autofocus: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 820;
            final productPane = _buildProductPane(c, filtered, constraints.maxWidth);
            final cartPane = _buildCartPane(c);

            if (isWide) {
              return Row(
                children: [
                  Expanded(flex: 3, child: productPane),
                  const VerticalDivider(width: 1),
                  SizedBox(width: 390, child: cartPane),
                ],
              );
            }
            return DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Container(
                    color: Colors.white,
                    child: TabBar(
                      labelColor: NfColors.greenDark,
                      indicatorColor: NfColors.green,
                      tabs: [
                        const Tab(icon: Icon(Icons.grid_view_rounded, size: 18), text: 'Produk'),
                        Tab(
                          icon: const Icon(Icons.shopping_basket_rounded, size: 18),
                          text: 'Keranjang (${c.cart.length})',
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(children: [productPane, cartPane]),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProductPane(PosController c, List<NfProduct> filtered, double width) {
    final cats = _categories(c.inventory);
    final cols = width >= 1300 ? 4 : (width >= 960 ? 3 : 2);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Scan barcode PLU atau ketik nama buah... (Enter)',
                    prefixIcon: const Icon(Icons.qr_code_scanner_rounded, color: NfColors.greenDark),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: _handleBarcodeOrSearchSubmit,
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                onPressed: widget.onOpenOnlineOrders,
                icon: const Icon(Icons.shopping_bag_rounded, size: 18),
                label: Text(
                  c.pendingOnlineOrdersCount > 0
                      ? 'Order (${c.pendingOnlineOrdersCount})'
                      : 'Order Web',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: cats.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, idx) {
              final cat = cats[idx];
              final active = cat == _selectedCategory;
              return ChoiceChip(
                label: Text(
                  cat,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: active ? Colors.white : const Color(0xFF334155),
                  ),
                ),
                selected: active,
                selectedColor: NfColors.green,
                onSelected: (_) => setState(() => _selectedCategory = cat),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('Produk tidak ditemukan.', style: TextStyle(color: Color(0xFF64748B))))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.92,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, idx) {
                    final p = filtered[idx];
                    final outOfStock = p.stock <= 0;
                    return InkWell(
                      onTap: () => _tapProduct(p),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: outOfStock ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  NfCachedImage(
                                    url: p.img,
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
                                  ),
                                  Positioned(
                                    left: 8,
                                    bottom: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: outOfStock ? NfColors.danger : Colors.white.withAlpha(235),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        outOfStock ? 'HABIS' : NfFormatters.stockDisplay(p.stock, p.unit),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: outOfStock ? Colors.white : const Color(0xFF334155),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${NfFormatters.rupiah(p.effectivePriceForMode(c.buyerMode))}/${NfFormatters.catalogPriceUnit(p.unit)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      color: NfColors.brown,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCartPane(PosController c) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                const Text('Keranjang Kasir', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                const Spacer(),
                if (c.heldBills.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _showHeldBillsSheet(c),
                    icon: const Icon(Icons.restore_rounded, size: 16),
                    label: Text('Antrean (${c.heldBills.length})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                IconButton(
                  tooltip: 'Tahan Nota (F4)',
                  onPressed: c.cart.isEmpty ? null : () => c.holdCurrentBill(),
                  icon: const Icon(Icons.pause_circle_outline_rounded),
                ),
                IconButton(
                  tooltip: 'Kosongkan Keranjang',
                  onPressed: c.cart.isEmpty ? null : () => c.clearCart(),
                  icon: const Icon(Icons.delete_outline_rounded, color: NfColors.danger),
                ),
              ],
            ),
          ),
          // 4 Mode Pembeli
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 6,
              children: [
                ('reguler', 'Reguler'),
                ('member', 'Member'),
                ('karyawan', 'Karyawan'),
                ('reseller', 'Reseller'),
              ].map((pair) {
                final active = c.buyerMode == pair.$1;
                return ChoiceChip(
                  label: Text(pair.$2, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: active ? Colors.white : const Color(0xFF334155))),
                  selected: active,
                  selectedColor: NfColors.greenDark,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => c.setBuyerMode(pair.$1),
                );
              }).toList(),
            ),
          ),
          if (c.buyerMode == 'member')
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _memberSearchCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'No. WA / Kode Member (MEM-...)',
                      ),
                      onSubmitted: (v) async {
                        final ok = await c.lookupMember(v);
                        if (!ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Member tidak ditemukan.')),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: () async {
                      final ok = await c.lookupMember(_memberSearchCtrl.text);
                      if (!ok && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Member tidak ditemukan.')),
                        );
                      }
                    },
                    child: const Text('Cari'),
                  ),
                ],
              ),
            ),
          if (c.activeMemberDetails != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFCD34D)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '👑 ${c.customerName} (${c.activeMemberDetails!['points'] ?? 0} Poin)',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF92400E)),
                  ),
                  if (((c.activeMemberDetails!['points'] as num?) ?? 0) >= c.settings.redeemUnitPoints)
                    TextButton(
                      onPressed: () {
                        final avail = ((c.activeMemberDetails!['points'] as num?) ?? 0).round();
                        c.pointsToRedeem = c.pointsToRedeem > 0 ? 0 : (avail ~/ c.settings.redeemUnitPoints) * c.settings.redeemUnitPoints;
                        setState(() {});
                      },
                      child: Text(
                        c.pointsToRedeem > 0 ? 'Batal Potong' : 'Potong Poin',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                      ),
                    ),
                ],
              ),
            ),
          // Banner Linked Order Online (Skema A)
          if (c.linkedOnlineOrder != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: NfColors.lightBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: NfColors.green),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'ORDER ONLINE: ${c.linkedOnlineOrder!.orderCode} • ${c.linkedOnlineOrder!.customerName}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: NfColors.greenDark),
                  ),
                  const SizedBox(height: 6),
                  FilledButton.icon(
                    onPressed: _sendSkemaABillDialog,
                    icon: const Icon(Icons.notifications_active_rounded, size: 16),
                    label: const Text('Kirim Tagihan Hasil Timbang (Skema A)', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          const Divider(height: 16),
          Expanded(
            child: c.cart.isEmpty
                ? const Center(
                    child: Text(
                      'Belum ada item.\nKetuk produk atau scan barcode.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: c.cart.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, idx) {
                      final it = c.cart[idx];
                      final sub = it.subtotal(c.buyerMode);
                      return InkWell(
                        onTap: it.skipStockDeduction ? null : () => _tapProduct(it.product),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(it.product.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                                    Text(
                                      '${NfFormatters.stockDisplay(it.qty, it.product.unit)} × ${NfFormatters.rupiah(it.product.effectivePriceForMode(c.buyerMode))}',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                    ),
                                    if (it.itemNote.isNotEmpty)
                                      Text(it.itemNote, style: const TextStyle(fontSize: 10, color: NfColors.brown, fontStyle: FontStyle.italic)),
                                  ],
                                ),
                              ),
                              Text(NfFormatters.rupiah(sub), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16, color: NfColors.danger),
                                onPressed: () => c.removeCartItemAt(idx),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (c.pointsDiscountRp > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Potongan Poin (${c.pointsToRedeem} pts)', style: const TextStyle(fontSize: 12, color: NfColors.greenDark, fontWeight: FontWeight.w700)),
                      Text('-${NfFormatters.rupiah(c.pointsDiscountRp)}', style: const TextStyle(fontSize: 12, color: NfColors.greenDark, fontWeight: FontWeight.w800)),
                    ],
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                    Text(
                      NfFormatters.rupiah(c.cartGrandTotal),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: NfColors.brown),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: c.cart.isEmpty ? null : _openPayment,
                  icon: const Icon(Icons.payments_rounded),
                  label: const Text('BAYAR TRANSAKSI (F2)', style: TextStyle(fontSize: 14)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showHeldBillsSheet(PosController c) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: c.heldBills.length,
        itemBuilder: (ctx, idx) {
          final b = c.heldBills[idx];
          return ListTile(
            title: Text('${b['customerName']} — ${NfFormatters.rupiah((b['total'] as num?) ?? 0)}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${(b['items'] as List).length} item'),
            trailing: FilledButton(
              onPressed: () {
                c.restoreHeldBill(idx);
                Navigator.of(ctx).pop();
              },
              child: const Text('Muat'),
            ),
          );
        },
      ),
    );
  }
}
