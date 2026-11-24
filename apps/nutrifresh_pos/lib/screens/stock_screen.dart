import 'package:flutter/material.dart';
import 'package:nf_core/nf_core.dart';
import '../services/pos_print_service.dart';
import '../state/pos_controller.dart';

class StockScreen extends StatefulWidget {
  final PosController controller;
  const StockScreen({super.key, required this.controller});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openStockOpnameDialog(NfProduct p) async {
    final qtyCtrl = TextEditingController(text: p.stock.toString());
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Timbang Ulang: ${p.name}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Stok tercatat: ${NfFormatters.stockDisplay(p.stock, p.unit)}'),
              const SizedBox(height: 10),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Stok Fisik Baru (${NfFormatters.displayUnit(p.unit)})'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'Catatan Opname'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Simpan Opname')),
        ],
      ),
    );
    if (ok == true) {
      final newQty = int.tryParse(qtyCtrl.text.trim());
      if (newQty != null) {
        final delta = newQty - p.stock;
        if (delta != 0) {
          await NfSupabaseService.instance.adjustStockAtomic(
            productId: p.id,
            deltaQty: delta,
            reason: 'Timbang Ulang${noteCtrl.text.trim().isNotEmpty ? ': ${noteCtrl.text.trim()}' : ''}',
            actor: widget.controller.session?.name ?? 'Staf',
          );
          await widget.controller.syncAllData();
        }
      }
    }
    qtyCtrl.dispose();
    noteCtrl.dispose();
  }

  Future<void> _openPurchaseDialog(NfProduct p) async {
    final qtyCtrl = TextEditingController(text: p.unit == 'Gram' ? '10000' : '10');
    final costCtrl = TextEditingController();
    final supCtrl = TextEditingController(text: 'Supplier Umum');
    String payStatus = 'Lunas';

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Kulakan Masuk: ${p.name}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'Jumlah Masuk (${NfFormatters.displayUnit(p.unit)})'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: costCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Total Harga Beli Kulakan (Rp)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: supCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Supplier'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: payStatus,
                  decoration: const InputDecoration(labelText: 'Status Bayar'),
                  items: const [
                    DropdownMenuItem(value: 'Lunas', child: Text('Lunas')),
                    DropdownMenuItem(value: 'Tempo', child: Text('Tempo (Masuk Hutang Office)')),
                  ],
                  onChanged: (v) => setD(() => payStatus = v ?? 'Lunas'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Simpan Kulakan')),
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
          actor: widget.controller.session?.name ?? 'Staf',
        );
        await NfSupabaseService.instance.addPurchase(
          id: purId,
          product: p,
          qty: qty,
          totalCost: totalCost,
          supplierName: supCtrl.text.trim(),
          paymentStatus: payStatus,
          actor: widget.controller.session?.name ?? 'Staf',
        );
        await widget.controller.syncAllData();
      }
    }
    qtyCtrl.dispose();
    costCtrl.dispose();
    supCtrl.dispose();
  }

  Future<void> _openWasteDialog(NfProduct p) async {
    final qtyCtrl = TextEditingController(text: p.unit == 'Gram' ? '500' : '1');
    final reasonCtrl = TextEditingController(text: 'Busuk / Rusak');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Catat Buah Rusak: ${p.name}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Jumlah Rusak (${NfFormatters.displayUnit(p.unit)})'),
              ),
              const SizedBox(height: 10),
              TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Alasan')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NfColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Potong Stok Rusak'),
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

  Future<void> _openStockCard(NfProduct p) async {
    final rows = await NfSupabaseService.instance.fetchStockCard(p.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Kartu Stok: ${p.name}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        content: SizedBox(
          width: 480,
          height: 360,
          child: rows.isEmpty
              ? const Center(child: Text('Belum ada riwayat mutasi stok.'))
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, idx) {
                    final r = rows[idx];
                    final delta = (r['delta_qty'] as num?) ?? 0;
                    final after = (r['stock_after'] as num?) ?? 0;
                    return ListTile(
                      dense: true,
                      title: Text('${r['reason'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      subtitle: Text('${r['actor'] ?? '-'} • Saldo: ${NfFormatters.stockDisplay(after, p.unit)}', style: const TextStyle(fontSize: 11)),
                      trailing: Text(
                        '${delta >= 0 ? '+' : ''}${NfFormatters.stockDisplay(delta, p.unit)}',
                        style: TextStyle(fontWeight: FontWeight.w900, color: delta >= 0 ? NfColors.greenDark : NfColors.danger),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tutup')),
        ],
      ),
    );
  }

  Future<void> _openAddOrEditProduct({NfProduct? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final bcCtrl = TextEditingController(text: existing?.barcode ?? '');
    final priceCtrl = TextEditingController(text: existing != null ? existing.price.round().toString() : '');
    final costCtrl = TextEditingController(text: existing != null ? existing.cost.round().toString() : '');
    final stockCtrl = TextEditingController(text: existing != null ? existing.stock.toString() : '0');
    String unit = existing?.unit ?? 'Gram';
    String cat = existing?.category ?? 'Buah Lokal';
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

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(existing == null ? 'Tambah Produk Baru' : 'Edit ${existing.name}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama Produk *')),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: cat,
                          decoration: const InputDecoration(labelText: 'Kategori'),
                          items: catOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (v) => setD(() => cat = v ?? 'Buah Lokal'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: unit,
                          decoration: const InputDecoration(labelText: 'Satuan'),
                          items: unitOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (v) => setD(() => unit = v ?? 'Gram'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: bcCtrl, decoration: const InputDecoration(labelText: 'Kode Barcode PLU')),
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
                  if (existing == null) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: stockCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'Stok Awal (${NfFormatters.displayUnit(unit)})'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      final p = NfProduct(
        id: existing?.id ?? NfFormatters.generateId('PRD'),
        name: nameCtrl.text.trim(),
        category: cat,
        unit: unit,
        barcode: bcCtrl.text.trim(),
        price: double.tryParse(priceCtrl.text.trim()) ?? 0,
        cost: double.tryParse(costCtrl.text.trim()) ?? 0,
        stock: existing?.stock ?? (int.tryParse(stockCtrl.text.trim()) ?? 0),
        minStock: existing?.minStock ?? 0,
        active: existing?.active ?? true,
        img: existing?.img ?? '',
        isObral: existing?.isObral ?? false,
        bundleQty: existing?.bundleQty ?? 0,
        bundlePrice: existing?.bundlePrice ?? 0,
        employeePrice: existing?.employeePrice ?? 0,
        resellerPrice: existing?.resellerPrice ?? 0,
        raw: existing?.raw ?? const {},
      );
      await NfSupabaseService.instance.upsertProduct(p);
      await widget.controller.syncAllData();
    }
    nameCtrl.dispose();
    bcCtrl.dispose();
    priceCtrl.dispose();
    costCtrl.dispose();
    stockCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final q = _searchCtrl.text.trim().toLowerCase();
    final items = c.inventory.where((p) {
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) || p.barcode.toLowerCase().contains(q) || p.category.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Cari produk, barcode PLU, atau kategori...',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () => _openAddOrEditProduct(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Produk Baru'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, idx) {
              final p = items[idx];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    NfCachedImage(
                      url: p.img,
                      width: 52,
                      height: 52,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                          Text(
                            '${p.category}  •  Jual: ${NfFormatters.rupiah(p.price)}/${NfFormatters.catalogPriceUnit(p.unit)}  •  PLU: ${p.barcode.isEmpty ? '-' : p.barcode}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                          Text(
                            'Stok: ${NfFormatters.stockDisplay(p.stock, p.unit)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: p.stock <= p.minStock ? NfColors.danger : NfColors.greenDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (act) async {
                        if (act == 'kulakan') await _openPurchaseDialog(p);
                        if (act == 'opname') await _openStockOpnameDialog(p);
                        if (act == 'rusak') await _openWasteDialog(p);
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
                        PopupMenuItem(value: 'kartu', child: Text('📋 Kartu Stok')),
                        PopupMenuItem(value: 'bc_print', child: Text('🖨️ Cetak Barcode Langsung')),
                        PopupMenuItem(value: 'bc_png', child: Text('🖼️ Unduh Label Barcode PNG')),
                        PopupMenuItem(value: 'edit', child: Text('✏️ Edit Produk & Harga')),
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
