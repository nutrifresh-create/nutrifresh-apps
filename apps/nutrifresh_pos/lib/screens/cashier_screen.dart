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
  int _mobileSubTab = 0; // 0 = Produk, 1 = Keranjang

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

  String _catLabel(String cat) {
    if (cat == 'Semua') return 'Semua';
    if (cat == 'Obral') return '🔥 Obral';
    if (cat == 'Buah Lokal') return '🥭 Buah Lokal';
    if (cat == 'Buah Impor') return '🍎 Buah Impor';
    if (cat == 'Buah Potong / Pack') return '🥗 Buah Potong';
    if (cat == 'Parsel & Gift') return '🎁 Parsel Gift';
    return cat;
  }

  Future<void> _tapProduct(NfProduct p) async {
    final c = widget.controller;
    if (!c.activeShift.isOpen) {
      final opened = await showOpenShiftGlassModal(
        context: context,
        controller: c,
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
    final res = await showWeightQtyGlassModal(
      context: context,
      style: c.uiStyle,
      product: p,
      buyerMode: c.buyerMode,
      initialQty: initQty,
      initialNote: initNote,
    );
    if (res != null) {
      c.addOrUpdateCartItem(p, res.qty, customNominal: res.customNominal, note: res.note);
    }
  }

  Future<void> _quickAddProduct(NfProduct p) async {
    final c = widget.controller;
    if (!c.activeShift.isOpen) {
      final opened = await showOpenShiftGlassModal(
        context: context,
        controller: c,
      );
      if (opened != true) return;
    }
    if (p.stock <= 0) return;
    final existingIdx = c.cart.indexWhere((x) => x.product.id == p.id && x.linkedPoId == null);
    final step = p.unit == 'Gram' ? 500 : 1;
    final nextQty = existingIdx >= 0
        ? (c.cart[existingIdx].qty + step).clamp(1, p.stock)
        : step.clamp(1, p.stock);
    c.addOrUpdateCartItem(p, nextQty);
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1100),
          behavior: SnackBarBehavior.floating,
          content: Text('${p.name} (${NfFormatters.stockDisplay(nextQty, p.unit)}) masuk keranjang'),
        ),
      );
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
      final opened = await showOpenShiftGlassModal(
        context: context,
        controller: c,
      );
      if (opened != true) return;
    }
    if (!mounted) return;
    final tx = await showPaymentGlassModal(
      context: context,
      controller: c,
    );
    if (tx != null && mounted) {
      if (PosPrintService.instance.hasDirectPrinter) {
        PosPrintService.instance.printReceipt(tx, c.settings).catchError((_) {});
      }
      await showDigitalReceiptGlassModal(
        context: context,
        style: c.uiStyle,
        tx: tx,
        settings: c.settings,
        justPaid: true,
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

    final ok = await showNfGlassModal<bool>(
      context: context,
      style: c.uiStyle,
      title: 'Kirim Tagihan Timbang (Skema A)',
      subtitle: 'Order ${ord.orderCode} • ${ord.customerName}',
      icon: Icons.notifications_active_rounded,
      headerGradient: const [Color(0xFF558B2F), Color(0xFF7CB342)],
      builder: (ctx) => Column(
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Hasil Timbang Buah:', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                Text(NfFormatters.rupiah(c.cartGrandTotal), style: const TextStyle(color: NfColors.brown, fontWeight: FontWeight.w900, fontSize: 17)),
              ],
            ),
          ),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal'))),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Kirim Tagihan'),
                ),
              ),
            ],
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
          SnackBar(content: Text('Tagihan ${ord.orderCode} terkirim (Menunggu Pembayaran).')),
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
            final productPane = _buildProductPane(c, filtered, constraints.maxWidth, isWide);
            final cartPane = _buildCartPane(c, isWide);

            if (isWide) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 12, 14),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: productPane),
                    const SizedBox(width: 12),
                    SizedBox(width: 390, child: cartPane),
                  ],
                ),
              );
            }

            return Stack(
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                      child: NfSlidingSegmented<int>(
                        style: c.uiStyle,
                        selected: _mobileSubTab,
                        onChanged: (v) => setState(() => _mobileSubTab = v),
                        items: [
                          (0, 'Etalase Buah', Icons.grid_view_rounded),
                          (1, 'Keranjang (${c.cart.length})', Icons.shopping_basket_rounded),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _mobileSubTab == 0 ? productPane : cartPane,
                    ),
                  ],
                ),
                // Pita Keranjang Mengambang (muncul di tab Produk jika sudah ada item)
                if (_mobileSubTab == 0 && c.cart.isNotEmpty)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 84,
                    child: InkWell(
                      onTap: () => setState(() => _mobileSubTab = 1),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF558B2F), Color(0xFF7CB342)],
                          ),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: NfColors.greenDark.withAlpha(90),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${c.cart.length}',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: NfColors.greenDark),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Lihat Keranjang & Bayar',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                              ),
                            ),
                            Text(
                              NfFormatters.rupiah(c.cartGrandTotal),
                              style: const TextStyle(color: Color(0xFFFDE047), fontWeight: FontWeight.w900, fontSize: 14),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildProductPane(PosController c, List<NfProduct> filtered, double width, bool isWide) {
    final cats = _categories(c.inventory);
    final cols = width >= 1320 ? 4 : (width >= 960 ? 3 : 2);
    final bottomPad = isWide ? 18.0 : (c.cart.isNotEmpty ? 150.0 : 94.0);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(isWide ? 4 : 12, 4, isWide ? 4 : 12, 8),
          child: Row(
            children: [
              Expanded(
                child: NfGlassSurface(
                  style: c.uiStyle,
                  borderRadius: 999,
                  elevated: false,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.qr_code_scanner_rounded, color: NfColors.greenDark, size: 19),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          decoration: const InputDecoration(
                            hintText: 'Cari buah / scan PLU...',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
                          ),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: _handleBarcodeOrSearchSubmit,
                        ),
                      ),
                      if (_searchCtrl.text.isNotEmpty)
                        InkWell(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                          child: const Icon(Icons.cancel_rounded, size: 18, color: Color(0xFF94A3B8)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: widget.onOpenOnlineOrders,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF7CB342), Color(0xFF558B2F)]),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: NfColors.greenDark.withAlpha(65),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shopping_bag_rounded, size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        c.pendingOnlineOrdersCount > 0
                            ? 'Order (${c.pendingOnlineOrdersCount})'
                            : 'Order',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Bilah Kategori Kapsul Bersih (TANPA centang Material 3!)
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isWide ? 4 : 12),
          child: NfGlassSurface(
            style: c.uiStyle,
            borderRadius: 999,
            elevated: false,
            padding: const EdgeInsets.all(4),
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: cats.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (_, idx) {
                  final cat = cats[idx];
                  final active = cat == _selectedCategory;
                  return InkWell(
                    onTap: () => setState(() => _selectedCategory = cat),
                    borderRadius: BorderRadius.circular(999),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: active
                            ? const LinearGradient(colors: [Color(0xFF8BC34A), Color(0xFF558B2F)])
                            : null,
                        color: active ? null : Colors.transparent,
                      ),
                      child: Text(
                        _catLabel(cat),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                          color: active ? Colors.white : const Color(0xFF334155),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text('Produk tidak ditemukan.', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
                )
              : GridView.builder(
                  padding: EdgeInsets.fromLTRB(isWide ? 4 : 12, 2, isWide ? 4 : 12, bottomPad),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: 11,
                    crossAxisSpacing: 11,
                    childAspectRatio: 0.84,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, idx) {
                    final p = filtered[idx];
                    final outOfStock = p.stock <= 0;
                    final inCart = c.cart.where((x) => x.product.id == p.id && x.linkedPoId == null).toList();
                    final cartQty = inCart.isNotEmpty ? inCart.first.qty : 0;

                    return InkWell(
                      onTap: () => _tapProduct(p),
                      borderRadius: BorderRadius.circular(24),
                      child: NfGlassSurface(
                        style: c.uiStyle,
                        borderRadius: 24,
                        padding: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  NfCachedImage(
                                    url: p.img,
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(23)),
                                  ),
                                  Positioned(
                                    left: 8,
                                    bottom: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: outOfStock ? NfColors.danger : Colors.white.withAlpha(240),
                                        borderRadius: BorderRadius.circular(10),
                                        boxShadow: [
                                          BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 6),
                                        ],
                                      ),
                                      child: Text(
                                        outOfStock ? 'HABIS' : 'Stok: ${NfFormatters.stockDisplay(p.stock, p.unit)}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: outOfStock ? Colors.white : const Color(0xFF334155),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (!outOfStock)
                                    Positioned(
                                      right: 8,
                                      bottom: 8,
                                      child: InkWell(
                                        onTap: () => _quickAddProduct(p),
                                        borderRadius: BorderRadius.circular(999),
                                        child: Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: NfColors.green,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 1.5),
                                            boxShadow: [
                                              BoxShadow(
                                                color: NfColors.greenDark.withAlpha(90),
                                                blurRadius: 8,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(Icons.add_rounded, color: Colors.white, size: 19),
                                        ),
                                      ),
                                    ),
                                  if (cartQty > 0)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: NfColors.greenDark,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          NfFormatters.stockDisplay(cartQty, p.unit),
                                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.category.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: NfColors.greenDark,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF0F172A)),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        NfFormatters.rupiah(p.effectivePriceForMode(c.buyerMode)),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13.5,
                                          color: NfColors.brown,
                                        ),
                                      ),
                                      Text(
                                        '/${NfFormatters.catalogPriceUnit(p.unit)}',
                                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                                      ),
                                    ],
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

  Widget _buildCartPane(PosController c, bool isWide) {
    return Padding(
      padding: EdgeInsets.fromLTRB(isWide ? 0 : 12, isWide ? 4 : 4, isWide ? 0 : 12, isWide ? 0 : 88),
      child: NfGlassSurface(
        style: c.uiStyle,
        borderRadius: 26,
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.shopping_basket_rounded, color: NfColors.greenDark, size: 19),
                const SizedBox(width: 6),
                const Text('Keranjang Kasir', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
                const Spacer(),
                if (c.heldBills.isNotEmpty)
                  TextButton(
                    onPressed: () => _showHeldBillsSheet(c),
                    child: Text('Antrean (${c.heldBills.length})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                IconButton(
                  tooltip: 'Tahan Nota (F4)',
                  onPressed: c.cart.isEmpty ? null : () => c.holdCurrentBill(),
                  icon: const Icon(Icons.pause_circle_outline_rounded, size: 20),
                ),
                IconButton(
                  tooltip: 'Kosongkan',
                  onPressed: c.cart.isEmpty ? null : () => c.clearCart(),
                  icon: const Icon(Icons.delete_outline_rounded, color: NfColors.danger, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 4),
            NfSlidingSegmented<String>(
              style: c.uiStyle,
              greenActive: true,
              selected: c.buyerMode,
              onChanged: (m) => c.setBuyerMode(m),
              items: const [
                ('reguler', 'Reguler', null),
                ('member', 'Member', null),
                ('karyawan', 'Staf', null),
                ('reseller', 'Reseller', null),
              ],
            ),
            if (c.buyerMode == 'member') ...[
              const SizedBox(height: 8),
              Row(
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
            ],
            if (c.activeMemberDetails != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '👑 ${c.customerName} (${c.activeMemberDetails!['points'] ?? 0} Poin)',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF92400E)),
                      ),
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
            if (c.linkedOnlineOrder != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: NfColors.lightBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: NfColors.green),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'ORDER WEB: ${c.linkedOnlineOrder!.orderCode} • ${c.linkedOnlineOrder!.customerName}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: NfColors.greenDark),
                    ),
                    const SizedBox(height: 6),
                    FilledButton.icon(
                      onPressed: _sendSkemaABillDialog,
                      icon: const Icon(Icons.notifications_active_rounded, size: 15),
                      label: const Text('Kirim Tagihan Timbang (Skema A)', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
            const Divider(height: 16),
            Expanded(
              child: c.cart.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shopping_basket_outlined, size: 40, color: Color(0xFFCBD5E1)),
                          SizedBox(height: 8),
                          Text(
                            'Keranjang masih kosong.\nKetuk produk atau scan barcode PLU.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: c.cart.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, idx) {
                        final it = c.cart[idx];
                        final sub = it.subtotal(c.buyerMode);
                        return InkWell(
                          onTap: it.skipStockDeduction ? null : () => _tapProduct(it.product),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(225),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(it.product.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
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
                                  icon: const Icon(Icons.close_rounded, size: 17, color: NfColors.danger),
                                  onPressed: () => c.removeCartItemAt(idx),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 16),
            if (c.pointsDiscountRp > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Potongan Poin (${c.pointsToRedeem} pts)', style: const TextStyle(fontSize: 12, color: NfColors.greenDark, fontWeight: FontWeight.w700)),
                    Text('-${NfFormatters.rupiah(c.pointsDiscountRp)}', style: const TextStyle(fontSize: 12, color: NfColors.greenDark, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                Text(
                  NfFormatters.rupiah(c.cartGrandTotal),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 21, color: NfColors.brown),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: c.cart.isEmpty ? null : _openPayment,
                icon: const Icon(Icons.payments_rounded),
                label: const Text('BAYAR TRANSAKSI (F2)', style: TextStyle(fontSize: 14)),
              ),
            ),
          ],
        ),
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
