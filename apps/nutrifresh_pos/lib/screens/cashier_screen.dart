import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nf_core/nf_core.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/pos_print_service.dart';
import '../state/pos_controller.dart';
import '../widgets/camera_scanner_modal.dart';
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
  final _custNameCtrl = TextEditingController();
  String _selectedCategory = 'Semua';
  int _mobileSubTab = 0; // 0 = Etalase, 1 = Keranjang
  bool _isListView = false;
  bool _sortByPopular = true;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _memberSearchCtrl.dispose();
    _custNameCtrl.dispose();
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
    if (cat == 'Parsel & Gift') return '🎁 Parsel';
    return cat;
  }

  Map<String, int> _buildPopularityMap(PosController c) {
    final counts = <String, int>{};
    for (final tx in c.transactions) {
      if (tx.isVoid) continue;
      for (final it in tx.items) {
        final id = (it['id'] ?? '').toString();
        if (id.isNotEmpty) counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    return counts;
  }

  Future<void> _tapProduct(NfProduct p) async {
    final c = widget.controller;
    if (!c.activeShift.isOpen) {
      final opened = await showOpenShiftGlassModal(context: context, controller: c);
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
      final opened = await showOpenShiftGlassModal(context: context, controller: c);
      if (opened != true) return;
    }
    if (p.stock <= 0) return;
    final existingIdx = c.cart.indexWhere((x) => x.product.id == p.id && x.linkedPoId == null);
    final step = p.unit == 'Gram' ? 500 : 1;
    final nextQty = existingIdx >= 0
        ? (c.cart[existingIdx].qty + step).clamp(1, p.stock).toInt()
        : step.clamp(1, p.stock).toInt();
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
    // Jika memindai QR Member (MEM-...) langsung aktifkan mode Member
    if (q.toUpperCase().startsWith('MEM-')) {
      _searchCtrl.clear();
      setState(() {});
      _lookupAndToastMember(q);
      return;
    }
    final exact = widget.controller.inventory.where(
      (p) => p.active && p.barcode.isNotEmpty && p.barcode.toLowerCase() == q.toLowerCase(),
    );
    if (exact.isNotEmpty) {
      _searchCtrl.clear();
      setState(() {});
      _tapProduct(exact.first);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kode "$q" tidak ditemukan di daftar produk.')),
      );
    }
  }

  Future<void> _openCameraBarcodeScan() async {
    final code = await openBarcodeQrCameraScanner(
      context: context,
      style: widget.controller.uiStyle,
      title: 'Scan Barcode PLU / QR Member',
      hint: 'Arahkan kamera ke stiker barcode produk atau QR Member',
    );
    if (code != null && code.isNotEmpty && mounted) {
      _handleBarcodeOrSearchSubmit(code);
    }
  }

  Future<void> _openCameraMemberQrScan() async {
    final code = await openBarcodeQrCameraScanner(
      context: context,
      style: widget.controller.uiStyle,
      title: 'Scan Kartu QR Member',
      hint: 'Arahkan kamera ke kode QR di HP pelanggan',
    );
    if (code != null && code.isNotEmpty && mounted) {
      _memberSearchCtrl.text = code;
      await _lookupAndToastMember(code);
    }
  }

  Future<void> _lookupAndToastMember(String query) async {
    final ok = await widget.controller.lookupMember(query);
    if (!mounted) return;
    if (ok) {
      _custNameCtrl.text = widget.controller.customerName;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Member ${widget.controller.customerName} aktif!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member tidak ditemukan.')),
      );
    }
  }

  Future<void> _openPayment() async {
    final c = widget.controller;
    if (c.cart.isEmpty) return;
    if (!c.activeShift.isOpen) {
      final opened = await showOpenShiftGlassModal(context: context, controller: c);
      if (opened != true) return;
    }
    if (!mounted) return;
    final tx = await showPaymentGlassModal(context: context, controller: c);
    if (tx != null && mounted) {
      _custNameCtrl.clear();
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

    if (_sortByPopular) {
      final pop = _buildPopularityMap(c);
      filtered.sort((a, b) {
        final diff = (pop[b.id] ?? 0).compareTo(pop[a.id] ?? 0);
        return diff != 0 ? diff : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    } else {
      filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): _openPayment,
        const SingleActivator(LogicalKeyboardKey.f4): () => c.holdCurrentBill(),
      },
      child: Focus(
        autofocus: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 780;
            final productPane = _buildProductPane(c, filtered, isWide);
            final cartPane = _buildCartPane(c, isWide);

            if (isWide) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 10, 12),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: productPane),
                    const SizedBox(width: 10),
                    SizedBox(width: constraints.maxWidth >= 1080 ? 375 : 335, child: cartPane),
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
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: _mobileSubTab == 0
                            ? KeyedSubtree(key: const ValueKey('m_prod'), child: productPane)
                            : KeyedSubtree(key: const ValueKey('m_cart'), child: cartPane),
                      ),
                    ),
                  ],
                ),
                if (_mobileSubTab == 0 && c.cart.isNotEmpty)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 84,
                    child: NfPressScale(
                      onTap: () => setState(() => _mobileSubTab = 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF15803D), Color(0xFF7CB342)]),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(color: NfColors.greenDark.withAlpha(95), blurRadius: 18, offset: const Offset(0, 6)),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                              child: Text('${c.cart.length}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: NfColors.greenDark)),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text('Lihat Keranjang & Bayar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                            ),
                            NfAnimatedRupiah(
                              value: c.cartGrandTotal,
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

  Widget _buildProductPane(PosController c, List<NfProduct> filtered, bool isWide) {
    final cats = _categories(c.inventory);
    final bottomPad = isWide ? 14.0 : (c.cart.isNotEmpty ? 150.0 : 94.0);

    return LayoutBuilder(
      builder: (context, paneBox) {
        // Hitung kolom dari lebar aktual panel produk (persis pos.html: 3 kolom rapi di laptop 1366px, 4 kolom di layar lebar!)
        final paneW = paneBox.maxWidth;
        final cols = paneW >= 820 ? 4 : (paneW >= 490 ? 3 : 2);
        final cardRatio = isWide ? 1.04 : 0.86;

        return Column(
          children: [
            // Bar Pencari + Tombol Kamera Scanner (Biru) + Toggle Grid/List
            Padding(
              padding: EdgeInsets.fromLTRB(isWide ? 2 : 12, 2, isWide ? 2 : 12, 7),
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
                          const Icon(Icons.search_rounded, color: NfColors.greenDark, size: 19),
                          const SizedBox(width: 7),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                              decoration: const InputDecoration(
                                hintText: 'Scan Barcode PLU / Nama Buah...',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 9),
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
                              child: const Icon(Icons.cancel_rounded, size: 17, color: Color(0xFF94A3B8)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Tombol Kamera Barcode / QR Scanner (Biru Cerah!)
                  NfPressScale(
                    onTap: _openCameraBarcodeScan,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)]),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF2563EB).withAlpha(65), blurRadius: 10, offset: const Offset(0, 3)),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.qr_code_scanner_rounded, size: 17, color: Colors.white),
                          SizedBox(width: 5),
                          Text('Scan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Toggle Grid / List
                  NfPressScale(
                    onTap: () => setState(() => _isListView = !_isListView),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(235),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Icon(
                        _isListView ? Icons.grid_view_rounded : Icons.view_list_rounded,
                        size: 19,
                        color: const Color(0xFF334155),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Bar Kategori + Urutkan Terlaris
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isWide ? 2 : 12),
              child: Row(
                children: [
                  Expanded(
                    child: NfGlassSurface(
                      style: c.uiStyle,
                      borderRadius: 999,
                      elevated: false,
                      padding: const EdgeInsets.all(3.5),
                      child: SizedBox(
                        height: 32,
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
                                padding: const EdgeInsets.symmetric(horizontal: 11),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  gradient: active
                                      ? const LinearGradient(colors: [Color(0xFF8BC34A), Color(0xFF558B2F)])
                                      : null,
                                ),
                                child: Text(
                                  _catLabel(cat),
                                  style: TextStyle(
                                    fontSize: 11.5,
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
                  const SizedBox(width: 6),
                  NfPressScale(
                    onTap: () => setState(() => _sortByPopular = !_sortByPopular),
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: _sortByPopular ? const Color(0xFFFFF7ED) : Colors.white.withAlpha(235),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _sortByPopular ? const Color(0xFFFDBA74) : const Color(0xFFCBD5E1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _sortByPopular ? Icons.local_fire_department_rounded : Icons.sort_by_alpha_rounded,
                            size: 15,
                            color: _sortByPopular ? const Color(0xFFEA580C) : const Color(0xFF475569),
                          ),
                          if (isWide) ...[
                            const SizedBox(width: 4),
                            Text(
                              _sortByPopular ? 'Terlaris' : 'A–Z',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _sortByPopular ? const Color(0xFFC2410C) : const Color(0xFF475569),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text('Produk tidak ditemukan.', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
                    )
                  : (_isListView
                      ? ListView.separated(
                          padding: EdgeInsets.fromLTRB(isWide ? 2 : 12, 2, isWide ? 2 : 12, bottomPad),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 7),
                          itemBuilder: (_, idx) => _buildProductListTile(c, filtered[idx]),
                        )
                      : GridView.builder(
                          padding: EdgeInsets.fromLTRB(isWide ? 2 : 12, 2, isWide ? 2 : 12, bottomPad),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisSpacing: 9,
                            crossAxisSpacing: 9,
                            childAspectRatio: cardRatio,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (_, idx) => _buildProductGridCard(c, filtered[idx], isWide),
                        )),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProductGridCard(PosController c, NfProduct p, bool isWide) {
    final outOfStock = p.stock <= 0;
    final inCart = c.cart.where((x) => x.product.id == p.id && x.linkedPoId == null).toList();
    final cartQty = inCart.isNotEmpty ? inCart.first.qty : 0;

    return NfPressScale(
      onTap: () => _tapProduct(p),
      child: NfGlassSurface(
        style: c.uiStyle,
        borderRadius: 20,
        borderColor: cartQty > 0 ? NfColors.green : (outOfStock ? const Color(0xFFFECACA) : null),
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: isWide ? 11 : 12,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NfCachedImage(
                    url: p.img,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
                  ),
                  if (p.isObral)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: NfColors.danger, borderRadius: BorderRadius.circular(8)),
                        child: const Text('OBRAL', style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: outOfStock ? NfColors.danger : Colors.white.withAlpha(242),
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: [BoxShadow(color: Colors.black.withAlpha(18), blurRadius: 5)],
                      ),
                      child: Text(
                        outOfStock ? 'HABIS' : NfFormatters.stockDisplay(p.stock, p.unit),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          color: outOfStock ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ),
                  if (!outOfStock)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: NfPressScale(
                        onTap: () => _quickAddProduct(p),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF8BC34A), Color(0xFF558B2F)]),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.4),
                            boxShadow: [BoxShadow(color: NfColors.greenDark.withAlpha(90), blurRadius: 6)],
                          ),
                          child: const Icon(Icons.add_rounded, color: Colors.white, size: 17),
                        ),
                      ),
                    ),
                  if (cartQty > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF15803D),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white, width: 1.2),
                        ),
                        child: Text(
                          NfFormatters.stockDisplay(cartQty, p.unit),
                          style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          NfFormatters.rupiah(p.effectivePriceForMode(c.buyerMode)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: NfColors.brown),
                        ),
                      ),
                      Text(
                        '/${NfFormatters.catalogPriceUnit(p.unit)}',
                        style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
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
  }

  Widget _buildProductListTile(PosController c, NfProduct p) {
    final outOfStock = p.stock <= 0;
    return NfPressScale(
      onTap: () => _tapProduct(p),
      child: NfGlassSurface(
        style: c.uiStyle,
        borderRadius: 18,
        padding: const EdgeInsets.all(9),
        child: Row(
          children: [
            NfCachedImage(url: p.img, width: 46, height: 46, borderRadius: BorderRadius.circular(12)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                  Text(
                    '${p.category} • Stok: ${outOfStock ? 'HABIS' : NfFormatters.stockDisplay(p.stock, p.unit)}${p.barcode.isNotEmpty ? ' • PLU: ${p.barcode}' : ''}',
                    style: TextStyle(fontSize: 11, color: outOfStock ? NfColors.danger : const Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            Text(
              '${NfFormatters.rupiah(p.effectivePriceForMode(c.buyerMode))}/${NfFormatters.catalogPriceUnit(p.unit)}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: NfColors.brown),
            ),
            const SizedBox(width: 8),
            if (!outOfStock)
              NfPressScale(
                onTap: () => _quickAddProduct(p),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(color: NfColors.green, shape: BoxShape.circle),
                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartPane(PosController c, bool isWide) {
    final buyerOptions = [
      ('reguler', 'Reguler', const Color(0xFF16A34A), const Color(0xFFDCFCE7)),
      ('member', 'Member', const Color(0xFFD97706), const Color(0xFFFEF3C7)),
      ('karyawan', 'Staf', const Color(0xFF2563EB), const Color(0xFFDBEAFE)),
      ('reseller', 'Reseller', const Color(0xFF7C3AED), const Color(0xFFEDE9FE)),
    ];

    final channels = ['Offline / Toko', 'WhatsApp', 'Online App', 'PO Parsel', 'GrabFood', 'GoFood', 'ShopeeFood'];
    final activeChannel = channels.contains(c.salesChannel) ? c.salesChannel : 'Offline / Toko';

    return Padding(
      padding: EdgeInsets.fromLTRB(isWide ? 0 : 12, isWide ? 2 : 2, isWide ? 0 : 12, isWide ? 0 : 88),
      child: NfGlassSurface(
        style: c.uiStyle,
        borderRadius: 24,
        padding: const EdgeInsets.all(11),
        child: Column(
          children: [
            // Header Keranjang Berwarna (Order, Tahan, Kosongkan) persis pos.html!
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.shopping_basket_rounded, color: Color(0xFF15803D), size: 16),
                ),
                const SizedBox(width: 7),
                Text('Keranjang (${c.cart.length})', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
                const Spacer(),
                _cartPillBtn(
                  icon: Icons.shopping_bag_rounded,
                  label: c.pendingOnlineOrdersCount > 0 ? 'Order (${c.pendingOnlineOrdersCount})' : 'Order',
                  bg: const Color(0xFFCCFBF1),
                  fg: const Color(0xFF0F766E),
                  onTap: widget.onOpenOnlineOrders,
                ),
                const SizedBox(width: 4),
                _cartPillBtn(
                  icon: Icons.pause_rounded,
                  label: c.heldBills.isNotEmpty ? 'Tahan (${c.heldBills.length})' : 'Tahan',
                  bg: const Color(0xFFFEF3C7),
                  fg: const Color(0xFFB45309),
                  onTap: c.cart.isNotEmpty
                      ? () => c.holdCurrentBill()
                      : (c.heldBills.isNotEmpty ? () => _showHeldBillsSheet(c) : null),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: c.cart.isEmpty
                      ? null
                      : () {
                          c.clearCart();
                          _custNameCtrl.clear();
                        },
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c.cart.isEmpty ? const Color(0xFFF1F5F9) : const Color(0xFFFEE2E2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.delete_outline_rounded, size: 15, color: c.cart.isEmpty ? const Color(0xFF94A3B8) : NfColors.danger),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 4 Pil Mode Pembeli Berwarna Khas
            Row(
              children: buyerOptions.map((opt) {
                final active = c.buyerMode == opt.$1;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: NfPressScale(
                      onTap: () => c.setBuyerMode(opt.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: active ? opt.$3 : opt.$4.withAlpha(155),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: active ? opt.$3 : opt.$3.withAlpha(65)),
                        ),
                        child: Text(
                          opt.$2,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            color: active ? Colors.white : opt.$3,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 7),
            // Kanal Penjualan & Nama Pelanggan (seperti pos.html!)
            Row(
              children: [
                Expanded(
                  flex: 5,
                  child: DropdownButtonFormField<String>(
                    value: activeChannel,
                    isExpanded: true,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: channels.map((ch) => DropdownMenuItem(value: ch, child: Text(ch, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        c.salesChannel = v;
                        setState(() {});
                      }
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 6,
                  child: TextField(
                    controller: _custNameCtrl,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      hintText: c.customerName == 'Pelanggan Umum' ? 'Nama Pelanggan (Ops)' : c.customerName,
                    ),
                    onChanged: (v) => c.customerName = v.trim().isEmpty ? 'Pelanggan Umum' : v.trim(),
                  ),
                ),
              ],
            ),
            if (c.buyerMode == 'member') ...[
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _memberSearchCtrl,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        hintText: 'No. WA / Kode MEM-...',
                      ),
                      onSubmitted: (v) => _lookupAndToastMember(v),
                    ),
                  ),
                  const SizedBox(width: 5),
                  NfPressScale(
                    onTap: _openCameraMemberQrScan,
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFF59E0B)),
                      ),
                      child: const Icon(Icons.qr_code_scanner_rounded, size: 17, color: Color(0xFFB45309)),
                    ),
                  ),
                  const SizedBox(width: 5),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () => _lookupAndToastMember(_memberSearchCtrl.text),
                    child: const Text('Cari', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            ],
            if (c.activeMemberDetails != null)
              Container(
                margin: const EdgeInsets.only(top: 7),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(12),
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
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
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
                margin: const EdgeInsets.only(top: 7),
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: NfColors.lightBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: NfColors.green),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'ORDER WEB: ${c.linkedOnlineOrder!.orderCode} • ${c.linkedOnlineOrder!.customerName}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: NfColors.greenDark),
                    ),
                    const SizedBox(height: 5),
                    FilledButton.icon(
                      onPressed: _sendSkemaABillDialog,
                      icon: const Icon(Icons.notifications_active_rounded, size: 15),
                      label: const Text('Kirim Tagihan Timbang (Skema A)', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
            const Divider(height: 14),
            Expanded(
              child: c.cart.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shopping_basket_outlined, size: 38, color: Color(0xFFCBD5E1)),
                          SizedBox(height: 6),
                          Text(
                            'Keranjang masih kosong.\nKetuk produk atau scan barcode PLU.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 11.5),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: c.cart.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 7),
                      itemBuilder: (_, idx) {
                        final it = c.cart[idx];
                        final sub = it.subtotal(c.buyerMode);
                        return NfPressScale(
                          onTap: it.skipStockDeduction ? null : () => _tapProduct(it.product),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(235),
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
                                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                                      ),
                                      if (it.itemNote.isNotEmpty)
                                        Text(it.itemNote, style: const TextStyle(fontSize: 10, color: NfColors.brown, fontStyle: FontStyle.italic)),
                                    ],
                                  ),
                                ),
                                Text(NfFormatters.rupiah(sub), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: Color(0xFF0F172A))),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.close_rounded, size: 16, color: NfColors.danger),
                                  onPressed: () => c.removeCartItemAt(idx),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 14),
            if (c.pointsDiscountRp > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Potongan Poin (${c.pointsToRedeem} pts)', style: const TextStyle(fontSize: 11.5, color: NfColors.greenDark, fontWeight: FontWeight.w700)),
                    Text('-${NfFormatters.rupiah(c.pointsDiscountRp)}', style: const TextStyle(fontSize: 11.5, color: NfColors.greenDark, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('TOTAL BAYAR', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF334155))),
                NfAnimatedRupiah(
                  value: c.cartGrandTotal,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: NfColors.brown),
                ),
              ],
            ),
            const SizedBox(height: 9),
            NfPressScale(
              onTap: c.cart.isEmpty ? null : _openPayment,
              child: Container(
                width: double.infinity,
                height: 46,
                decoration: BoxDecoration(
                  gradient: c.cart.isEmpty
                      ? const LinearGradient(colors: [Color(0xFFCBD5E1), Color(0xFFCBD5E1)])
                      : const LinearGradient(colors: [Color(0xFF16A34A), Color(0xFF558B2F)]),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: c.cart.isEmpty
                      ? null
                      : [BoxShadow(color: const Color(0xFF15803D).withAlpha(80), blurRadius: 14, offset: const Offset(0, 5))],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.payments_rounded, color: Colors.white, size: 19),
                    SizedBox(width: 8),
                    Text('BAYAR TRANSAKSI (F2)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13.5)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cartPillBtn({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: onTap == null ? const Color(0xFFF1F5F9) : bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: onTap == null ? const Color(0xFF94A3B8) : fg),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: onTap == null ? const Color(0xFF94A3B8) : fg)),
          ],
        ),
      ),
    );
  }

  void _showHeldBillsSheet(PosController c) {
    showNfGlassModal<void>(
      context: context,
      style: c.uiStyle,
      title: 'Daftar Nota Ditahan',
      subtitle: 'Ketuk Muat untuk melanjutkan transaksi pembeli',
      icon: Icons.restore_rounded,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(c.heldBills.length, (idx) {
          final b = c.heldBills[idx];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${b['customerName']} — ${NfFormatters.rupiah((b['total'] as num?) ?? 0)}', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${(b['items'] as List).length} item'),
            trailing: FilledButton(
              onPressed: () {
                c.restoreHeldBill(idx);
                Navigator.of(ctx).pop();
              },
              child: const Text('Muat'),
            ),
          );
        }),
      ),
    );
  }
}
