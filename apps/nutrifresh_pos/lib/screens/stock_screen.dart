import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nf_core/nf_core.dart';
import '../services/pos_print_service.dart';
import '../state/pos_controller.dart';
import '../widgets/camera_scanner_modal.dart';

class StockScreen extends StatefulWidget {
  final PosController controller;
  const StockScreen({super.key, required this.controller});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final _searchCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _generateUniquePlu() {
    final used = widget.controller.inventory
        .map((p) => p.barcode.trim().toUpperCase())
        .where((b) => b.isNotEmpty)
        .toSet();
    for (int n = 200101; n < 299999; n++) {
      final candidate = n.toString();
      if (!used.contains(candidate)) return candidate;
    }
    return 'PLU${DateTime.now().millisecondsSinceEpoch % 100000}';
  }

  Future<void> _scanToFilterStock() async {
    final code = await openBarcodeQrCameraScanner(
      context: context,
      style: widget.controller.uiStyle,
      title: 'Scan Barcode Produk',
      hint: 'Scan stiker barcode di rak untuk langsung menemukan produknya',
    );
    if (code != null && code.isNotEmpty && mounted) {
      setState(() => _searchCtrl.text = code);
    }
  }

  Future<void> _openStockOpnameDialog(NfProduct p) async {
    final qtyCtrl = TextEditingController(text: p.stock.toString());
    final noteCtrl = TextEditingController();
    final ok = await showNfGlassModal<bool>(
      context: context,
      style: widget.controller.uiStyle,
      title: 'Timbang Ulang / Opname',
      subtitle: '${p.name} • Stok tercatat: ${NfFormatters.stockDisplay(p.stock, p.unit)}',
      icon: Icons.scale_rounded,
      headerGradient: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: qtyCtrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            decoration: InputDecoration(labelText: 'Stok Fisik Riil (${NfFormatters.displayUnit(p.unit)})'),
          ),
          const SizedBox(height: 10),
          TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Catatan Opname (Opsional)')),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal'))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Simpan Opname'))),
            ],
          ),
        ],
      ),
    );
    if (ok == true) {
      final newQty = int.tryParse(qtyCtrl.text.trim());
      if (newQty != null && newQty != p.stock) {
        await NfSupabaseService.instance.adjustStockAtomic(
          productId: p.id,
          deltaQty: newQty - p.stock,
          reason: 'Timbang Ulang${noteCtrl.text.trim().isNotEmpty ? ': ${noteCtrl.text.trim()}' : ''}',
          actor: widget.controller.session?.name ?? 'Staf',
        );
        await widget.controller.syncAllData();
      }
    }
    qtyCtrl.dispose();
    noteCtrl.dispose();
  }

  Future<void> _openPurchaseDialog(NfProduct p) async {
    final c = widget.controller;
    final qtyCtrl = TextEditingController(text: p.unit == 'Gram' ? '10000' : '10');
    final costCtrl = TextEditingController();
    final dueCtrl = TextEditingController(text: NfFormatters.ymd(DateTime.now().add(const Duration(days: 7))));
    final supCtrl = TextEditingController(
      text: c.suppliers.isNotEmpty ? (c.suppliers.first['name'] ?? 'Supplier Umum').toString() : 'Supplier Umum',
    );
    String payStatus = 'Lunas';

    final ok = await showNfGlassModal<bool>(
      context: context,
      style: c.uiStyle,
      title: 'Kulakan Masuk',
      subtitle: p.name,
      icon: Icons.local_shipping_rounded,
      headerGradient: const [Color(0xFF558B2F), Color(0xFF7CB342)],
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Jumlah Masuk (${NfFormatters.displayUnit(p.unit)}) *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: costCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Total Harga Beli Kulakan (Rp) *'),
            ),
            const SizedBox(height: 10),
            TextField(controller: supCtrl, decoration: const InputDecoration(labelText: 'Nama Supplier')),
            if (c.suppliers.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: c.suppliers.take(6).map((s) {
                  final nm = (s['name'] ?? '').toString();
                  return InkWell(
                    onTap: () => setM(() => supCtrl.text = nm),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: NfColors.lightBg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: Text(nm, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: NfColors.greenDark)),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: payStatus,
              decoration: const InputDecoration(labelText: 'Status Bayar'),
              items: const [
                DropdownMenuItem(value: 'Lunas', child: Text('Lunas')),
                DropdownMenuItem(value: 'Tempo', child: Text('Tempo (Otomatis masuk Hutang Office)')),
              ],
              onChanged: (v) => setM(() => payStatus = v ?? 'Lunas'),
            ),
            if (payStatus == 'Tempo') ...[
              const SizedBox(height: 10),
              TextField(controller: dueCtrl, decoration: const InputDecoration(labelText: 'Jatuh Tempo (YYYY-MM-DD)')),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal'))),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Simpan Kulakan'))),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
      final totalCost = double.tryParse(costCtrl.text.trim()) ?? 0;
      if (qty > 0) {
        final unitCost = totalCost > 0 ? (totalCost / (qty / NfFormatters.unitDivisor(p.unit))) : null;
        final purId = NfFormatters.generateId('PUR');
        await NfSupabaseService.instance.adjustStockAtomic(
          productId: p.id,
          deltaQty: qty,
          newUnitCost: unitCost,
          reason: 'Kulakan $purId (${supCtrl.text.trim()})',
          refId: purId,
          actor: c.session?.name ?? 'Staf',
        );
        await NfSupabaseService.instance.addPurchase(
          id: purId,
          product: p,
          qty: qty,
          totalCost: totalCost,
          supplierName: supCtrl.text.trim().isEmpty ? 'Supplier Umum' : supCtrl.text.trim(),
          paymentStatus: payStatus,
          dueDate: payStatus == 'Tempo' ? dueCtrl.text.trim() : '',
          actor: c.session?.name ?? 'Staf',
        );
        await c.syncAllData();
      }
    }
    qtyCtrl.dispose();
    costCtrl.dispose();
    dueCtrl.dispose();
    supCtrl.dispose();
  }

  Future<void> _openWasteDialog(NfProduct p) async {
    final qtyCtrl = TextEditingController(text: p.unit == 'Gram' ? '500' : '1');
    final reasonCtrl = TextEditingController(text: 'Busuk / Rusak');
    final ok = await showNfGlassModal<bool>(
      context: context,
      style: widget.controller.uiStyle,
      title: 'Catat Buah Rusak / Susut',
      subtitle: p.name,
      icon: Icons.delete_sweep_rounded,
      headerGradient: const [Color(0xFFB91C1C), Color(0xFFEF4444)],
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: qtyCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Jumlah Rusak (${NfFormatters.displayUnit(p.unit)}) *'),
          ),
          const SizedBox(height: 10),
          TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Alasan Susut / Rusak')),
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
                  child: const Text('Potong Stok Rusak'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (ok == true) {
      final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
      if (qty > 0) {
        final wId = NfFormatters.generateId('WST');
        await NfSupabaseService.instance.adjustStockAtomic(
          productId: p.id,
          deltaQty: -qty,
          reason: 'Rusak: ${reasonCtrl.text.trim()}',
          refId: wId,
          actor: widget.controller.session?.name ?? 'Staf',
        );
        await NfSupabaseService.instance.addWasteLog(
          id: wId,
          product: p,
          qty: qty,
          reason: reasonCtrl.text.trim(),
          actor: widget.controller.session?.name ?? 'Staf',
        );
        await widget.controller.syncAllData();
      }
    }
    qtyCtrl.dispose();
    reasonCtrl.dispose();
  }

  Future<void> _openPecahGradeDialog(NfProduct src) async {
    final c = widget.controller;
    final targets = c.inventory.where((x) => x.id != src.id).toList();
    NfProduct? destProd;
    final qtyCtrl = TextEditingController(text: src.unit == 'Gram' ? '1000' : '1');
    final newNameCtrl = TextEditingController(text: '[OBRAL] ${src.name}');
    final newPriceCtrl = TextEditingController(text: NfFormatters.roundToThousand(src.price * 0.65).toString());
    bool createNewObral = true;

    final ok = await showNfGlassModal<bool>(
      context: context,
      style: c.uiStyle,
      title: 'Pecah Grade / Obral',
      subtitle: 'Sumber: ${src.name} (Stok: ${NfFormatters.stockDisplay(src.stock, src.unit)})',
      icon: Icons.call_split_rounded,
      headerGradient: const [Color(0xFFD97706), Color(0xFFF59E0B)],
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Jumlah Dipecah (${NfFormatters.displayUnit(src.unit)}) *'),
            ),
            const SizedBox(height: 10),
            NfSlidingSegmented<bool>(
              style: c.uiStyle,
              greenActive: true,
              selected: createNewObral,
              onChanged: (v) => setM(() => createNewObral = v),
              items: const [
                (true, 'Buat Item Obral Baru', null),
                (false, 'Ke Produk Ada', null),
              ],
            ),
            const SizedBox(height: 10),
            if (createNewObral) ...[
              TextField(controller: newNameCtrl, decoration: const InputDecoration(labelText: 'Nama Produk Obral *')),
              const SizedBox(height: 10),
              TextField(controller: newPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga Jual Obral (Rp) *')),
            ] else
              DropdownButtonFormField<NfProduct>(
                value: destProd,
                decoration: const InputDecoration(labelText: 'Pilih Produk Tujuan'),
                items: targets.map((t) => DropdownMenuItem(value: t, child: Text(t.name, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setM(() => destProd = v),
              ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Proses Pecah Grade'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
      if (qty > 0 && qty <= src.stock) {
        final actor = c.session?.name ?? 'Staf';
        String targetId;
        if (createNewObral) {
          targetId = NfFormatters.generateId('OBR');
          final obralProd = NfProduct(
            id: targetId,
            name: newNameCtrl.text.trim(),
            category: src.category,
            unit: src.unit,
            barcode: _generateUniquePlu(),
            price: double.tryParse(newPriceCtrl.text.trim()) ?? src.price,
            cost: src.cost,
            stock: 0,
            minStock: 0,
            active: true,
            img: src.img,
            isObral: true,
            bundleQty: 0,
            bundlePrice: 0,
            employeePrice: 0,
            resellerPrice: 0,
            raw: {'originalPrice': src.price, 'isObral': true},
          );
          await NfSupabaseService.instance.upsertProduct(obralProd);
        } else {
          if (destProd == null) return;
          targetId = destProd!.id;
        }
        await NfSupabaseService.instance.batchAdjustStockAtomic(
          items: [
            {'product_id': src.id, 'delta_qty': -qty, 'reason': 'Pecah Grade keluar'},
            {'product_id': targetId, 'delta_qty': qty, 'new_unit_cost': src.cost, 'reason': 'Pecah Grade dari ${src.name}'},
          ],
          reason: 'Pecah Grade ${src.name}',
          actor: actor,
          preventNegative: true,
        );
        await c.syncAllData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pecah Grade / Obral berhasil diproses!')));
        }
      }
    }
    qtyCtrl.dispose();
    newNameCtrl.dispose();
    newPriceCtrl.dispose();
  }

  /// PRODUKSI DAPUR v1.1: PENCARIAN PRODUK JADI & PENCARIAN BAHAN MENTAH SUPER MUDAH!
  Future<void> _openKitchenProductionModal() async {
    final c = widget.controller;
    if (c.inventory.isEmpty) return;

    NfProduct? targetProd;
    // Prioritaskan produk Jus / Potong / Parsel sebagai rekomendasi default
    final preferredTargets = c.inventory.where((p) =>
        p.category.contains('Jus') || p.category.contains('Potong') || p.category.contains('Parsel')).toList();
    targetProd = preferredTargets.isNotEmpty ? preferredTargets.first : c.inventory.first;

    final targetSearchCtrl = TextEditingController();
    final ingSearchCtrl = TextEditingController();
    final outQtyCtrl = TextEditingController(text: '10');
    final List<({NfProduct prod, TextEditingController qtyCtrl})> selectedIngredients = [];

    final ok = await showNfGlassModal<bool>(
      context: context,
      style: c.uiStyle,
      title: 'Produksi Dapur (Jus / Salad / Parsel)',
      subtitle: 'Cari bahan cepat → potong bahan otomatis → hitung HPP akurat',
      icon: Icons.blender_rounded,
      headerGradient: const [Color(0xFF047857), Color(0xFF10B981)],
      maxWidth: 580,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) {
          final outQty = (int.tryParse(outQtyCtrl.text.trim()) ?? 1).clamp(1, 99999).toInt();
          final tQuery = targetSearchCtrl.text.trim().toLowerCase();
          final targetSuggestions = tQuery.isEmpty
              ? const <NfProduct>[]
              : c.inventory.where((p) => p.name.toLowerCase().contains(tQuery) || p.barcode.toLowerCase().contains(tQuery)).take(6).toList();

          final iQuery = ingSearchCtrl.text.trim().toLowerCase();
          final ingSuggestions = iQuery.isEmpty
              ? c.inventory.where((p) => p.id != targetProd?.id && p.stock > 0).take(6).toList()
              : c.inventory
                  .where((p) => p.id != targetProd?.id && (p.name.toLowerCase().contains(iQuery) || p.category.toLowerCase().contains(iQuery) || p.barcode.toLowerCase().contains(iQuery)))
                  .take(8)
                  .toList();

          double totalRawCost = 0;
          for (final ing in selectedIngredients) {
            final q = int.tryParse(ing.qtyCtrl.text.trim()) ?? 0;
            totalRawCost += ing.prod.calculateLineCost(q);
          }
          final hppPerUnit = targetProd == null
              ? 0.0
              : totalRawCost / (outQty / NfFormatters.unitDivisor(targetProd!.unit));

          void addIngredient(NfProduct p) {
            final exists = selectedIngredients.any((e) => e.prod.id == p.id);
            if (exists) return;
            final defQty = p.unit == 'Gram' ? '500' : '1';
            setM(() {
              selectedIngredients.add((prod: p, qtyCtrl: TextEditingController(text: defQty)));
              ingSearchCtrl.clear();
            });
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. PRODUK JADI DENGAN PENCARIAN INSTAN
              const Text('1. Produk Jadi Hasil Produksi', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: Color(0xFF065F46))),
              const SizedBox(height: 6),
              if (targetProd != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF6EE7B7)),
                  ),
                  child: Row(
                    children: [
                      NfCachedImage(url: targetProd!.img, width: 42, height: 42, borderRadius: BorderRadius.circular(10)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(targetProd!.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                            Text(
                              '${targetProd!.category} • Stok: ${NfFormatters.stockDisplay(targetProd!.stock, targetProd!.unit)}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF047857)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 7),
              TextField(
                controller: targetSearchCtrl,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                  hintText: 'Ganti produk jadi? Ketik nama Jus / Salad / Parsel...',
                ),
                onChanged: (_) => setM(() {}),
              ),
              if (targetSuggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Column(
                    children: targetSuggestions.map((p) => ListTile(
                          dense: true,
                          leading: NfCachedImage(url: p.img, width: 32, height: 32, borderRadius: BorderRadius.circular(8)),
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                          subtitle: Text('${p.category} • Stok: ${NfFormatters.stockDisplay(p.stock, p.unit)}', style: const TextStyle(fontSize: 10.5)),
                          onTap: () => setM(() {
                            targetProd = p;
                            targetSearchCtrl.clear();
                          }),
                        )).toList(),
                  ),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: outQtyCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                decoration: InputDecoration(
                  labelText: 'Jumlah Hasil Jadi (${targetProd != null ? NfFormatters.displayUnit(targetProd!.unit) : 'Pcs'}) *',
                ),
                onChanged: (_) => setM(() {}),
              ),

              const Divider(height: 22),

              // 2. PENCARIAN BAHAN MENTAH SUPER CEPAT
              const Text('2. Cari & Tambahkan Bahan Mentah / Kemasan', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: Color(0xFF1D4ED8))),
              const SizedBox(height: 6),
              TextField(
                controller: ingSearchCtrl,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF2563EB)),
                  hintText: 'Ketik bahan (misal: alpukat, gula, cup, pita, keranjang)...',
                  suffixIcon: ingSearchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 17),
                          onPressed: () => setM(() => ingSearchCtrl.clear()),
                        )
                      : null,
                ),
                onChanged: (_) => setM(() {}),
              ),
              const SizedBox(height: 7),
              Container(
                constraints: const BoxConstraints(maxHeight: 165),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: ingSuggestions.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: Center(child: Text('Bahan tidak ditemukan.', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)))),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: ingSuggestions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, idx) {
                          final p = ingSuggestions[idx];
                          final already = selectedIngredients.any((e) => e.prod.id == p.id);
                          return ListTile(
                            dense: true,
                            leading: NfCachedImage(url: p.img, width: 34, height: 34, borderRadius: BorderRadius.circular(8)),
                            title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                            subtitle: Text(
                              'Stok: ${NfFormatters.stockDisplay(p.stock, p.unit)} • HPP: ${NfFormatters.rupiah(p.cost)}/${NfFormatters.catalogPriceUnit(p.unit)}',
                              style: const TextStyle(fontSize: 10.5),
                            ),
                            trailing: already
                                ? const Icon(Icons.check_circle_rounded, color: NfColors.green, size: 20)
                                : FilledButton.tonal(
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () => addIngredient(p),
                                    child: const Text('+ Pakai', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                                  ),
                            onTap: already ? null : () => addIngredient(p),
                          );
                        },
                      ),
              ),

              const SizedBox(height: 12),
              Text(
                'Bahan Terpilih (${selectedIngredients.length} item):',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
              ),
              const SizedBox(height: 6),
              if (selectedIngredients.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Text(
                    'Belum ada bahan dipilih. Ketik nama bahan di atas lalu ketuk "+ Pakai".',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                )
              else
                ...List.generate(selectedIngredients.length, (i) {
                  final row = selectedIngredients[i];
                  final q = int.tryParse(row.qtyCtrl.text.trim()) ?? 0;
                  final lineCost = row.prod.calculateLineCost(q);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 7),
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(row.prod.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                              Text(
                                'Modal: ${NfFormatters.rupiah(lineCost)} • Sisa: ${NfFormatters.stockDisplay(row.prod.stock, row.prod.unit)}',
                                style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 96,
                          child: TextField(
                            controller: row.qtyCtrl,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                              suffixText: NfFormatters.displayUnit(row.prod.unit),
                            ),
                            onChanged: (_) => setM(() {}),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_rounded, color: NfColors.danger, size: 18),
                          onPressed: () => setM(() {
                            row.qtyCtrl.dispose();
                            selectedIngredients.removeAt(i);
                          }),
                        ),
                      ],
                    ),
                  );
                }),

              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NfColors.lightBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: NfColors.green.withAlpha(90)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Modal Bahan:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        Text(NfFormatters.rupiah(totalRawCost), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Estimasi HPP Baru / Satuan:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: NfColors.greenDark)),
                        Text(NfFormatters.rupiah(hppPerUnit), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: NfColors.brown)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: (targetProd == null || selectedIngredients.isEmpty)
                    ? null
                    : () => Navigator.of(ctx).pop(true),
                icon: const Icon(Icons.check_circle_rounded),
                label: const Text('Proses Produksi & Potong Bahan'),
              ),
            ],
          );
        },
      ),
    );

    if (ok == true && targetProd != null) {
      final outQty = int.tryParse(outQtyCtrl.text.trim()) ?? 0;
      if (outQty > 0) {
        final batch = <Map<String, dynamic>>[];
        double totalRawCost = 0;
        for (final ing in selectedIngredients) {
          final q = int.tryParse(ing.qtyCtrl.text.trim()) ?? 0;
          if (q > 0) {
            totalRawCost += ing.prod.calculateLineCost(q);
            batch.add({'product_id': ing.prod.id, 'delta_qty': -q, 'reason': 'Bahan Produksi ${targetProd!.name}'});
          }
        }
        final hppPerUnit = totalRawCost > 0
            ? totalRawCost / (outQty / NfFormatters.unitDivisor(targetProd!.unit))
            : targetProd!.cost;
        batch.add({
          'product_id': targetProd!.id,
          'delta_qty': outQty,
          'new_unit_cost': hppPerUnit,
          'reason': 'Hasil Produksi Dapur',
        });
        await NfSupabaseService.instance.batchAdjustStockAtomic(
          items: batch,
          reason: 'Produksi ${targetProd!.name}',
          actor: c.session?.name ?? 'Staf',
          preventNegative: false,
        );
        await c.syncAllData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Produksi ${targetProd!.name} (+${NfFormatters.stockDisplay(outQty, targetProd!.unit)}) tersimpan!')),
          );
        }
      }
    }
    targetSearchCtrl.dispose();
    ingSearchCtrl.dispose();
    outQtyCtrl.dispose();
    for (final ing in selectedIngredients) {
      ing.qtyCtrl.dispose();
    }
  }

  Future<void> _openQuickPriceEditorModal() async {
    final c = widget.controller;
    final ctrls = {for (final p in c.inventory) p.id: TextEditingController(text: p.price.round().toString())};
    bool saving = false;

    await showNfGlassModal<void>(
      context: context,
      style: c.uiStyle,
      title: 'Edit Harga Cepat Massal',
      subtitle: 'Ubah banyak harga jual sekaligus lalu klik Simpan Semua',
      icon: Icons.sell_rounded,
      headerGradient: const [Color(0xFF936C38), Color(0xFFD97706)],
      maxWidth: 560,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...c.inventory.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                            Text('${p.category} • /${NfFormatters.catalogPriceUnit(p.unit)}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: ctrls[p.id],
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                          decoration: const InputDecoration(isDense: true, prefixText: 'Rp '),
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      setM(() => saving = true);
                      int changed = 0;
                      for (final p in c.inventory) {
                        final nextPrice = double.tryParse(ctrls[p.id]!.text.trim());
                        if (nextPrice != null && nextPrice > 0 && nextPrice.round() != p.price.round()) {
                          final updated = NfProduct.fromRow({'id': p.id, 'data': {...p.toDataJson(), 'price': nextPrice}});
                          await NfSupabaseService.instance.upsertProduct(updated);
                          changed++;
                        }
                      }
                      await c.syncAllData();
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$changed harga produk berhasil diperbarui!')),
                        );
                      }
                    },
              icon: const Icon(Icons.save_rounded),
              label: Text(saving ? 'Menyimpan...' : 'Simpan Semua Perubahan Harga'),
            ),
          ],
        ),
      ),
    );
    for (final ctrl in ctrls.values) {
      ctrl.dispose();
    }
  }

  Future<void> _openBatchBarcodeModal() async {
    final c = widget.controller;
    final copiesMap = <String, int>{};

    await showNfGlassModal<void>(
      context: context,
      style: c.uiStyle,
      title: 'Cetak Label Barcode Massal',
      subtitle: 'Tentukan jumlah stiker per produk (${PosPrintService.instance.activePrinterSummary})',
      icon: Icons.qr_code_2_rounded,
      headerGradient: const [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
      maxWidth: 540,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) {
          final totalLabels = copiesMap.values.fold<int>(0, (a, b) => a + b);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...c.inventory.where((p) => p.active).map((p) {
                final count = copiesMap[p.id] ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                            Text('${NfFormatters.rupiah(p.price)}/${NfFormatters.catalogPriceUnit(p.unit)} • PLU: ${p.barcode.isEmpty ? p.id : p.barcode}',
                                style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: count > 0 ? () => setM(() => copiesMap[p.id] = count - 1) : null,
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                      ),
                      SizedBox(
                        width: 28,
                        child: Text('$count', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900)),
                      ),
                      IconButton(
                        onPressed: () => setM(() => copiesMap[p.id] = count + 1),
                        icon: const Icon(Icons.add_circle_outline, size: 20, color: NfColors.greenDark),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: totalLabels == 0
                    ? null
                    : () async {
                        final tasks = <(NfProduct, int)>[];
                        for (final p in c.inventory) {
                          final n = copiesMap[p.id] ?? 0;
                          if (n > 0) tasks.add((p, n));
                        }
                        Navigator.of(ctx).pop();
                        await PosPrintService.instance.printBatchBarcodeLabels(tasks, c.settings);
                      },
                icon: const Icon(Icons.print_rounded),
                label: Text('Cetak $totalLabels Stiker Barcode Sekarang'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openStockCard(NfProduct p) async {
    final rows = await NfSupabaseService.instance.fetchStockCard(p.id);
    if (!mounted) return;
    await showNfGlassModal<void>(
      context: context,
      style: widget.controller.uiStyle,
      title: 'Kartu Stok: ${p.name}',
      subtitle: 'Saldo saat ini: ${NfFormatters.stockDisplay(p.stock, p.unit)}',
      icon: Icons.history_rounded,
      maxWidth: 520,
      builder: (_) => rows.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: Text('Belum ada riwayat mutasi stok.')),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: rows.map((r) {
                final delta = (r['delta_qty'] as num?) ?? 0;
                final after = (r['stock_after'] as num?) ?? 0;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${r['reason'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  subtitle: Text('${r['actor'] ?? '-'} • Saldo: ${NfFormatters.stockDisplay(after, p.unit)}', style: const TextStyle(fontSize: 11)),
                  trailing: Text(
                    '${delta >= 0 ? '+' : ''}${NfFormatters.stockDisplay(delta, p.unit)}',
                    style: TextStyle(fontWeight: FontWeight.w900, color: delta >= 0 ? NfColors.greenDark : NfColors.danger),
                  ),
                );
              }).toList(),
            ),
    );
  }

  /// TAMBAH / EDIT PRODUK v1.1: LENGKAP DENGAN UPLOAD FOTO KE SUPABASE STORAGE + AUTO PLU + SCAN BARCODE!
  Future<void> _openAddOrEditProduct({NfProduct? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final bcCtrl = TextEditingController(
      text: (existing?.barcode.isNotEmpty ?? false) ? existing!.barcode : _generateUniquePlu(),
    );
    final priceCtrl = TextEditingController(text: existing != null ? existing.price.round().toString() : '');
    final costCtrl = TextEditingController(text: existing != null ? existing.cost.round().toString() : '');
    final empPriceCtrl = TextEditingController(text: existing != null && existing.employeePrice > 0 ? existing.employeePrice.round().toString() : '');
    final resPriceCtrl = TextEditingController(text: existing != null && existing.resellerPrice > 0 ? existing.resellerPrice.round().toString() : '');
    final stockCtrl = TextEditingController(text: existing != null ? existing.stock.toString() : '0');
    final minStockCtrl = TextEditingController(text: existing != null ? existing.minStock.toString() : '0');
    final bundleQtyCtrl = TextEditingController(text: existing != null && existing.bundleQty > 0 ? existing.bundleQty.toString() : '');
    final bundlePriceCtrl = TextEditingController(text: existing != null && existing.bundlePrice > 0 ? existing.bundlePrice.round().toString() : '');
    final imgUrlCtrl = TextEditingController(text: existing?.img ?? '');

    String unit = existing?.unit ?? 'Gram';
    String cat = existing?.category ?? 'Buah Lokal';
    bool isActive = existing?.active ?? true;
    bool isObral = existing?.isObral ?? false;
    Uint8List? pickedPreviewBytes;
    bool uploadingPhoto = false;
    final prodId = existing?.id ?? NfFormatters.generateId('PRD');

    final catOptions = <String>{
      'Buah Lokal',
      'Buah Impor',
      '🍹 Aneka Jus Buah',
      'Buah Potong / Pack',
      'Parsel & Gift',
      '📦 Bahan & Perlengkapan',
      if (cat.isNotEmpty) cat,
    }.toList();
    final unitOptions = <String>{
      'Gram', 'Pack', 'Pcs', 'Cup', 'Box', 'Paket', 'ml',
      if (unit.isNotEmpty) unit,
    }.toList();

    final ok = await showNfGlassModal<bool>(
      context: context,
      style: widget.controller.uiStyle,
      title: existing == null ? 'Tambah Produk Baru' : 'Edit Produk',
      subtitle: existing?.name ?? 'Foto otomatis tersinkron ke Kasir & Katalog Web',
      icon: Icons.inventory_2_rounded,
      headerGradient: const [Color(0xFF558B2F), Color(0xFF7CB342)],
      maxWidth: 520,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) {
          Future<void> pickAndUploadPhoto(ImageSource source) async {
            try {
              final xfile = await _picker.pickImage(
                source: source,
                maxWidth: 900,
                maxHeight: 900,
                imageQuality: 80,
              );
              if (xfile == null) return;
              final bytes = await xfile.readAsBytes();
              setM(() {
                pickedPreviewBytes = bytes;
                uploadingPhoto = true;
              });
              final ext = xfile.name.contains('.') ? xfile.name.split('.').last : 'jpg';
              final publicUrl = await NfSupabaseService.instance.uploadProductImageBytes(
                bytes: bytes,
                filePrefix: prodId,
                ext: ext,
              );
              setM(() {
                imgUrlCtrl.text = publicUrl;
                uploadingPhoto = false;
              });
            } catch (e) {
              setM(() => uploadingPhoto = false);
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Gagal unggah foto: $e')));
              }
            }
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Bagian Foto Produk
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: pickedPreviewBytes != null
                            ? Image.memory(pickedPreviewBytes!, fit: BoxFit.cover)
                            : NfCachedImage(url: imgUrlCtrl.text.trim(), width: 72, height: 72),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            uploadingPhoto ? 'Mengunggah foto ke Cloud...' : 'Foto Produk (Kasir & Katalog)',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: uploadingPhoto ? null : () => pickAndUploadPhoto(ImageSource.gallery),
                                icon: const Icon(Icons.photo_library_rounded, size: 15),
                                label: Text(Platform.isWindows ? 'Pilih File Foto' : 'Galeri', style: const TextStyle(fontSize: 11.5)),
                              ),
                              if (Platform.isAndroid || Platform.isIOS)
                                FilledButton.tonalIcon(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: uploadingPhoto ? null : () => pickAndUploadPhoto(ImageSource.camera),
                                  icon: const Icon(Icons.camera_alt_rounded, size: 15),
                                  label: const Text('Kamera', style: TextStyle(fontSize: 11.5)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama Produk *')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: cat,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Kategori'),
                      items: catOptions.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) => setM(() => cat = v ?? 'Buah Lokal'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: unit,
                      decoration: const InputDecoration(labelText: 'Satuan'),
                      items: unitOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => setM(() => unit = v ?? 'Gram'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Kode PLU + Auto Generate + Scan Kamera!
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: bcCtrl,
                      style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800),
                      decoration: const InputDecoration(labelText: 'Kode Barcode PLU'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12)),
                    onPressed: () => setM(() => bcCtrl.text = _generateUniquePlu()),
                    child: const Text('✨ Auto', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                    tooltip: 'Scan Barcode Kemasan',
                    onPressed: () async {
                      final code = await openBarcodeQrCameraScanner(
                        context: ctx,
                        style: widget.controller.uiStyle,
                        title: 'Scan Barcode Produk',
                        hint: 'Arahkan kamera ke barcode kemasan produk',
                      );
                      if (code != null && code.isNotEmpty) {
                        setM(() => bcCtrl.text = code);
                      }
                    },
                    icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 19),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'Harga Jual / ${NfFormatters.catalogPriceUnit(unit)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: costCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Harga Modal (HPP)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: empPriceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Harga Karyawan (Ops)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: resPriceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Harga Reseller (Ops)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (existing == null) ...[
                    Expanded(
                      child: TextField(
                        controller: stockCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: 'Stok Awal (${NfFormatters.displayUnit(unit)})'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: TextField(
                      controller: minStockCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'Stok Minimal (${NfFormatters.displayUnit(unit)})'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: bundleQtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Promo Paket Min Qty (Ops)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: bundlePriceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Harga Paket Rp (Ops)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: isActive,
                      onChanged: (v) => setM(() => isActive = v),
                      title: const Text('Tampil di Katalog', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  Expanded(
                    child: SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: isObral,
                      onChanged: (v) => setM(() => isObral = v),
                      title: const Text('Tandai Obral 🔥', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: uploadingPhoto ? null : () => Navigator.of(ctx).pop(false), child: const Text('Batal'))),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: uploadingPhoto ? null : () => Navigator.of(ctx).pop(true),
                      icon: const Icon(Icons.save_rounded),
                      label: Text(uploadingPhoto ? 'Mengunggah Foto...' : 'Simpan Produk'),
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
      final p = NfProduct(
        id: prodId,
        name: nameCtrl.text.trim(),
        category: cat,
        unit: unit,
        barcode: bcCtrl.text.trim().isEmpty ? _generateUniquePlu() : bcCtrl.text.trim(),
        price: double.tryParse(priceCtrl.text.trim()) ?? 0,
        cost: double.tryParse(costCtrl.text.trim()) ?? 0,
        stock: existing?.stock ?? (int.tryParse(stockCtrl.text.trim()) ?? 0),
        minStock: int.tryParse(minStockCtrl.text.trim()) ?? 0,
        active: isActive,
        img: imgUrlCtrl.text.trim(),
        isObral: isObral,
        bundleQty: int.tryParse(bundleQtyCtrl.text.trim()) ?? 0,
        bundlePrice: double.tryParse(bundlePriceCtrl.text.trim()) ?? 0,
        employeePrice: double.tryParse(empPriceCtrl.text.trim()) ?? 0,
        resellerPrice: double.tryParse(resPriceCtrl.text.trim()) ?? 0,
        raw: existing?.raw ?? const {},
      );
      await NfSupabaseService.instance.upsertProduct(p);
      await widget.controller.syncAllData();
    }
    nameCtrl.dispose();
    bcCtrl.dispose();
    priceCtrl.dispose();
    costCtrl.dispose();
    empPriceCtrl.dispose();
    resPriceCtrl.dispose();
    stockCtrl.dispose();
    minStockCtrl.dispose();
    bundleQtyCtrl.dispose();
    bundlePriceCtrl.dispose();
    imgUrlCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final q = _searchCtrl.text.trim().toLowerCase();
    final isWide = MediaQuery.of(context).size.width >= 760;
    final items = c.inventory.where((p) {
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) || p.barcode.toLowerCase().contains(q) || p.category.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
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
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          decoration: const InputDecoration(
                            hintText: 'Cari produk, PLU, atau kategori...',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      if (_searchCtrl.text.isNotEmpty)
                        InkWell(
                          onTap: () => setState(() => _searchCtrl.clear()),
                          child: const Icon(Icons.cancel_rounded, size: 17, color: Color(0xFF94A3B8)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              NfPressScale(
                onTap: _scanToFilterStock,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)]),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 19),
                ),
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                onPressed: () => _openAddOrEditProduct(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Baru'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _quickActionPill(Icons.sell_rounded, 'Edit Harga Cepat', const Color(0xFFB45309), const Color(0xFFFEF3C7), _openQuickPriceEditorModal),
              const SizedBox(width: 8),
              _quickActionPill(Icons.blender_rounded, 'Produksi Jus / Parsel', const Color(0xFF047857), const Color(0xFFD1FAE5), _openKitchenProductionModal),
              const SizedBox(width: 8),
              _quickActionPill(Icons.qr_code_2_rounded, 'Barcode Massal', const Color(0xFF1D4ED8), const Color(0xFFDBEAFE), _openBatchBarcodeModal),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(12, 0, 12, isWide ? 20 : 94),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 9),
            itemBuilder: (_, idx) {
              final p = items[idx];
              return NfGlassSurface(
                style: c.uiStyle,
                borderRadius: 22,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    NfCachedImage(
                      url: p.img,
                      width: 54,
                      height: 54,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
                          Text(
                            '${p.category} • ${NfFormatters.rupiah(p.price)}/${NfFormatters.catalogPriceUnit(p.unit)}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: p.stock <= p.minStock ? const Color(0xFFFEE2E2) : NfColors.lightBg,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Stok: ${NfFormatters.stockDisplay(p.stock, p.unit)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: p.stock <= p.minStock ? NfColors.danger : NfColors.greenDark,
                                  ),
                                ),
                              ),
                              if (p.barcode.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text('PLU: ${p.barcode}', style: const TextStyle(fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.w800, color: Color(0xFF1D4ED8))),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      onSelected: (act) async {
                        if (act == 'kulakan') await _openPurchaseDialog(p);
                        if (act == 'opname') await _openStockOpnameDialog(p);
                        if (act == 'rusak') await _openWasteDialog(p);
                        if (act == 'pecah') await _openPecahGradeDialog(p);
                        if (act == 'kartu') await _openStockCard(p);
                        if (act == 'edit') await _openAddOrEditProduct(existing: p);
                        if (act == 'bc_print') {
                          await PosPrintService.instance.printBarcodeLabel(p, c.settings);
                        }
                        if (act == 'bc_png') {
                          final path = await PosPrintService.instance.exportBarcodeLabelPng(p, c.settings);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Label PNG disimpan di: $path')));
                          }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'kulakan', child: Text('🚚 Kulakan Masuk')),
                        PopupMenuItem(value: 'opname', child: Text('⚖️ Timbang Ulang / Opname')),
                        PopupMenuItem(value: 'rusak', child: Text('🗑️ Catat Buah Rusak')),
                        PopupMenuItem(value: 'pecah', child: Text('🔀 Pecah Grade / Obral')),
                        PopupMenuItem(value: 'kartu', child: Text('📋 Kartu Stok')),
                        PopupMenuItem(value: 'bc_print', child: Text('🖨️ Cetak Barcode Langsung')),
                        PopupMenuItem(value: 'bc_png', child: Text('🖼️ Unduh Label Barcode PNG')),
                        PopupMenuItem(value: 'edit', child: Text('✏️ Edit Produk, Foto & PLU')),
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

  Widget _quickActionPill(IconData icon, String label, Color fg, Color bg, VoidCallback onTap) {
    return NfPressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: fg.withAlpha(80)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: fg)),
          ],
        ),
      ),
    );
  }
}
