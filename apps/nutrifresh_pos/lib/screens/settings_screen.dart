import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nf_core/nf_core.dart';
import 'package:printing/printing.dart';
import '../services/pos_print_service.dart';
import '../state/pos_controller.dart';

class SettingsScreen extends StatefulWidget {
  final PosController controller;
  const SettingsScreen({super.key, required this.controller});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<Printer> _winPrinters = [];
  List<BtPrinterDevice> _btPrinters = [];
  bool _loadingPrinters = false;

  @override
  void initState() {
    super.initState();
    _refreshPrinters();
  }

  Future<void> _refreshPrinters() async {
    setState(() => _loadingPrinters = true);
    if (Platform.isAndroid) {
      final list = await PosPrintService.instance.listBluetoothPrinters();
      if (mounted) {
        setState(() {
          _btPrinters = list;
          _loadingPrinters = false;
        });
      }
    } else {
      final list = await PosPrintService.instance.listWindowsPrinters();
      if (mounted) {
        setState(() {
          _winPrinters = list;
          _loadingPrinters = false;
        });
      }
    }
  }

  Future<void> _switchCashierDialog() async {
    final c = widget.controller;
    final activeEmps = c.employees.where((e) => e.isActive).toList();
    if (activeEmps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Daftar karyawan belum tersedia.')));
      return;
    }
    NfEmployee selected = activeEmps.first;
    final pinCtrl = TextEditingController();

    final ok = await showNfGlassModal<bool>(
      context: context,
      style: c.uiStyle,
      title: 'Ganti Kasir Shift (PIN)',
      subtitle: 'Ganti kasir aktif tanpa logout perangkat toko',
      icon: Icons.switch_account_rounded,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<NfEmployee>(
              value: selected,
              decoration: const InputDecoration(labelText: 'Pilih Nama Karyawan'),
              items: activeEmps.map((e) => DropdownMenuItem(value: e, child: Text('${e.name} (${e.role})'))).toList(),
              onChanged: (v) {
                if (v != null) setM(() => selected = v);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'PIN Pribadi Karyawan'),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Aktifkan Kasir')),
          ],
        ),
      ),
    );
    if (ok == true) {
      final err = await c.switchCashierByPin(selected, pinCtrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Kasir aktif berganti ke ${selected.name}')));
      }
    }
    pinCtrl.dispose();
  }

  Future<void> _unlockOwnerDialog() async {
    final pinCtrl = TextEditingController();
    final ok = await showNfGlassModal<bool>(
      context: context,
      style: widget.controller.uiStyle,
      title: 'Buka Kunci Owner / Kepala Toko',
      subtitle: 'Buka akses Laba, VOID, Master Data, & Cabang',
      icon: Icons.lock_open_rounded,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: pinCtrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Masukkan PIN Owner'),
          ),
          const SizedBox(height: 14),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Buka Kunci')),
        ],
      ),
    );
    if (ok == true) {
      final err = await widget.controller.unlockOwnerWithPin(pinCtrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Akses Owner aktif.')));
      }
    }
    pinCtrl.dispose();
  }

  Future<void> _openBranchModal() async {
    final ctrl = TextEditingController(text: NfSupabaseService.instance.branchId);
    final ok = await showNfGlassModal<bool>(
      context: context,
      style: widget.controller.uiStyle,
      title: 'Identitas Cabang Perangkat',
      subtitle: 'Siap multi-cabang (default: cabang-1)',
      icon: Icons.store_mall_directory_rounded,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'ID Cabang Aktif (contoh: cabang-1, cabang-2)'),
          ),
          const SizedBox(height: 14),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Simpan ID Cabang')),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      await NfSupabaseService.instance.setBranchId(ctrl.text.trim());
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cabang perangkat diatur ke: ${NfSupabaseService.instance.branchId}')),
        );
      }
    }
    ctrl.dispose();
  }

  Future<void> _openSuppliersModal() async {
    final c = widget.controller;
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    await showNfGlassModal<void>(
      context: context,
      style: c.uiStyle,
      title: 'Master Supplier / Agen Kulakan',
      subtitle: 'Tersinkron ke POS & Office',
      icon: Icons.local_shipping_rounded,
      maxWidth: 520,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: TextField(controller: nameCtrl, decoration: const InputDecoration(isDense: true, labelText: 'Nama Agen *'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(isDense: true, labelText: 'No. WA'))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: TextField(controller: noteCtrl, decoration: const InputDecoration(isDense: true, labelText: 'Catatan (misal: Apel & Pir)'))),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) return;
                    await NfSupabaseService.instance.upsertSupplier(
                      id: NfFormatters.generateId('SUP'),
                      name: nameCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                      note: noteCtrl.text.trim(),
                    );
                    nameCtrl.clear();
                    phoneCtrl.clear();
                    noteCtrl.clear();
                    await c.syncAllData();
                    setM(() {});
                  },
                  child: const Text('Tambah'),
                ),
              ],
            ),
            const Divider(height: 20),
            if (c.suppliers.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('Belum ada data supplier.')))
            else
              ...c.suppliers.map((s) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text((s['name'] ?? '-').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${s['phone'] ?? '-'} • ${s['note'] ?? ''}', style: const TextStyle(fontSize: 11)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: NfColors.danger, size: 19),
                      onPressed: () async {
                        await NfSupabaseService.instance.deleteRow('nf_suppliers', s['id'].toString());
                        await c.syncAllData();
                        setM(() {});
                      },
                    ),
                  )),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();
    noteCtrl.dispose();
  }

  Future<void> _openResellersModal() async {
    final c = widget.controller;
    final nameCtrl = TextEditingController();
    final shopCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    await showNfGlassModal<void>(
      context: context,
      style: c.uiStyle,
      title: 'Master Mitra Reseller',
      subtitle: 'Berlaku pusat di seluruh cabang NutriFresh',
      icon: Icons.storefront_rounded,
      maxWidth: 520,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: TextField(controller: nameCtrl, decoration: const InputDecoration(isDense: true, labelText: 'Nama Reseller *'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: shopCtrl, decoration: const InputDecoration(isDense: true, labelText: 'Nama Toko'))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(isDense: true, labelText: 'No. WA'))),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) return;
                    await NfSupabaseService.instance.upsertReseller(
                      id: NfFormatters.generateId('RSL'),
                      name: nameCtrl.text.trim(),
                      shopName: shopCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                    );
                    nameCtrl.clear();
                    shopCtrl.clear();
                    phoneCtrl.clear();
                    await c.syncAllData();
                    setM(() {});
                  },
                  child: const Text('Tambah'),
                ),
              ],
            ),
            const Divider(height: 20),
            if (c.resellers.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('Belum ada data reseller.')))
            else
              ...c.resellers.map((r) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${r['name'] ?? '-'}${(r['shopName'] ?? '').toString().isNotEmpty ? ' (${r['shopName']})' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${r['phone'] ?? '-'} • Status: ${r['status'] ?? 'Aktif'}', style: const TextStyle(fontSize: 11)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: NfColors.danger, size: 19),
                      onPressed: () async {
                        await NfSupabaseService.instance.deleteRow('nf_resellers', r['id'].toString());
                        await c.syncAllData();
                        setM(() {});
                      },
                    ),
                  )),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    shopCtrl.dispose();
    phoneCtrl.dispose();
  }

  Future<void> _openRewardsModal() async {
    final c = widget.controller;
    final titleCtrl = TextEditingController();
    final ptsCtrl = TextEditingController(text: '100');
    final discCtrl = TextEditingController(text: '5000');

    await showNfGlassModal<void>(
      context: context,
      style: c.uiStyle,
      title: 'Promo & Hadiah Poin Member',
      subtitle: 'Tampil otomatis di tab Tukar Poin aplikasi Pelanggan',
      icon: Icons.workspace_premium_rounded,
      maxWidth: 520,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(isDense: true, labelText: 'Judul Hadiah / Voucher *')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: TextField(controller: ptsCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true, labelText: 'Harga Poin'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: discCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true, labelText: 'Potongan Rp'))),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    if (titleCtrl.text.trim().isEmpty) return;
                    await NfSupabaseService.instance.upsertPointReward(
                      id: NfFormatters.generateId('RWD'),
                      title: titleCtrl.text.trim(),
                      pointsCost: int.tryParse(ptsCtrl.text.trim()) ?? 100,
                      discountRp: int.tryParse(discCtrl.text.trim()) ?? 0,
                    );
                    titleCtrl.clear();
                    await c.syncAllData();
                    setM(() {});
                  },
                  child: const Text('Tambah'),
                ),
              ],
            ),
            const Divider(height: 20),
            if (c.pointRewards.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('Belum ada katalog hadiah poin.')))
            else
              ...c.pointRewards.map((r) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text((r['title'] ?? '-').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${r['pointsCost'] ?? 0} Poin • Potongan ${NfFormatters.rupiah((r['discountRp'] as num?) ?? 0)}',
                        style: const TextStyle(fontSize: 11)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: NfColors.danger, size: 19),
                      onPressed: () async {
                        await NfSupabaseService.instance.deleteRow('nf_point_rewards', r['id'].toString());
                        await c.syncAllData();
                        setM(() {});
                      },
                    ),
                  )),
          ],
        ),
      ),
    );
    titleCtrl.dispose();
    ptsCtrl.dispose();
    discCtrl.dispose();
  }

  Future<void> _openBannersModal() async {
    final c = widget.controller;
    final raw = Map<String, dynamic>.from(c.settings.raw);
    final slides = (raw['promoSlides'] is List)
        ? (raw['promoSlides'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    bool showFlash = raw['showFlashSaleCard'] == true;
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String theme = 'green';

    await showNfGlassModal<void>(
      context: context,
      style: c.uiStyle,
      title: 'Kelola Banner Katalog',
      subtitle: 'Langsung mengubah tumpukan banner vertikal di aplikasi & web',
      icon: Icons.campaign_rounded,
      maxWidth: 520,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: showFlash,
              onChanged: (v) async {
                setM(() => showFlash = v);
                raw['showFlashSaleCard'] = v;
                await NfSupabaseService.instance.saveStoreSettings(raw);
                await c.syncAllData();
              },
              title: const Text('Tampilkan Banner Flash Sale Obral', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
            ),
            const Divider(),
            TextField(controller: titleCtrl, decoration: const InputDecoration(isDense: true, labelText: 'Judul Banner Baru *')),
            const SizedBox(height: 8),
            TextField(controller: descCtrl, decoration: const InputDecoration(isDense: true, labelText: 'Deskripsi Singkat')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: theme,
                    decoration: const InputDecoration(isDense: true, labelText: 'Warna Kartu'),
                    items: const [
                      DropdownMenuItem(value: 'green', child: Text('Hijau NutriFresh')),
                      DropdownMenuItem(value: 'amber', child: Text('Oranye Segar')),
                      DropdownMenuItem(value: 'blue', child: Text('Biru Modern')),
                      DropdownMenuItem(value: 'red', child: Text('Merah Promo')),
                    ],
                    onChanged: (v) => setM(() => theme = v ?? 'green'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    if (titleCtrl.text.trim().isEmpty) return;
                    slides.add({
                      'badge': 'PROMO SPESIAL',
                      'title': titleCtrl.text.trim(),
                      'desc': descCtrl.text.trim(),
                      'theme': theme,
                      'ctaText': 'Belanja Sekarang',
                      'actionType': 'catalog',
                    });
                    raw['promoSlides'] = slides;
                    await NfSupabaseService.instance.saveStoreSettings(raw);
                    titleCtrl.clear();
                    descCtrl.clear();
                    await c.syncAllData();
                    setM(() {});
                  },
                  child: const Text('+ Banner'),
                ),
              ],
            ),
            const Divider(height: 18),
            ...List.generate(slides.length, (i) {
              final s = slides[i];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('Banner ${i + 1}: ${s['title'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                subtitle: Text((s['desc'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                trailing: slides.length > 1
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline, color: NfColors.danger, size: 19),
                        onPressed: () async {
                          slides.removeAt(i);
                          raw['promoSlides'] = slides;
                          await NfSupabaseService.instance.saveStoreSettings(raw);
                          await c.syncAllData();
                          setM(() {});
                        },
                      )
                    : null,
              );
            }),
          ],
        ),
      ),
    );
    titleCtrl.dispose();
    descCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final ps = PosPrintService.instance;
    final isWide = MediaQuery.of(context).size.width >= 760;

    return ListView(
      padding: EdgeInsets.fromLTRB(12, 6, 12, isWide ? 22 : 96),
      children: [
        _sectionCard(
          style: c.uiStyle,
          icon: Icons.palette_rounded,
          iconColor: NfColors.greenDark,
          title: 'Tema Tampilan POS (Perangkat Ini)',
          subtitle: 'Pilih Liquid Glass berkaca buram iOS 26 atau Natural solid ringan.',
          child: Row(
            children: [
              Expanded(
                child: _themeOptionCard(
                  active: c.uiStyle == NfUiStyle.glass,
                  title: 'Liquid Glass',
                  subtitle: 'Kaca buram modern',
                  badge: Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [Color(0xFF34D399), Color(0xFF38BDF8), Color(0xFFFBBF24)]),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 17),
                  ),
                  onTap: () => c.setUiStyle(NfUiStyle.glass),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _themeOptionCard(
                  active: c.uiStyle == NfUiStyle.natural,
                  title: 'Natural',
                  subtitle: 'Bersih, solid & ringan',
                  badge: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: NfColors.lightBg,
                      border: Border.all(color: const Color(0xFF86EFAC)),
                    ),
                    child: const Icon(Icons.eco_rounded, color: NfColors.greenDark, size: 17),
                  ),
                  onTap: () => c.setUiStyle(NfUiStyle.natural),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          style: c.uiStyle,
          icon: Icons.print_rounded,
          iconColor: const Color(0xFF2563EB),
          title: Platform.isAndroid ? 'Printer Bluetooth Langsung (Tanpa Pop-Up)' : 'Printer Langsung Windows (Tanpa Pop-Up)',
          subtitle: 'Mendukung Struk Thermal, Tutup Shift, Stiker PO & Label Barcode (ESC/POS & TSPL).',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ps.activePrinterSummary,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: NfColors.greenDark),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cari Ulang Printer',
                    onPressed: _loadingPrinters ? null : _refreshPrinters,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => ps.printTestPage(c.settings),
                    icon: const Icon(Icons.print_rounded, size: 15),
                    label: const Text('Tes', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (Platform.isAndroid) ...[
                if (_btPrinters.isEmpty)
                  const Text(
                    'Belum ada printer Bluetooth ter-pair. Hubungkan dulu printer di Pengaturan Bluetooth Android, lalu ketuk ikon segarkan di atas.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _printerPill(
                        label: 'Dialog Sistem',
                        selected: ps.btPrinterAddress == null,
                        onTap: () async {
                          await ps.setBluetoothPrinter(null);
                          setState(() {});
                        },
                      ),
                      ..._btPrinters.map((d) => _printerPill(
                            label: d.name,
                            selected: ps.btPrinterAddress == d.address,
                            onTap: () async {
                              await ps.setBluetoothPrinter(d);
                              setState(() {});
                            },
                          )),
                    ],
                  ),
                const SizedBox(height: 12),
                const Text('Protokol Cetak Stiker Label Bluetooth:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                NfSlidingSegmented<String>(
                  style: c.uiStyle,
                  greenActive: true,
                  selected: ps.btLabelProtocol,
                  onChanged: (v) async {
                    await ps.setBtLabelProtocol(v);
                    setState(() {});
                  },
                  items: const [
                    ('escpos', 'ESC/POS (Struk)', null),
                    ('tspl', 'TSPL (Stiker Label)', null),
                  ],
                ),
              ] else ...[
                if (_winPrinters.isEmpty)
                  const Text('Tidak ada printer Windows terdeteksi.', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _printerPill(
                        label: 'Tanya Setiap Cetak',
                        selected: ps.defaultPrinterName == null,
                        onTap: () async {
                          await ps.setDefaultPrinterName(null);
                          setState(() {});
                        },
                      ),
                      ..._winPrinters.map((p) => _printerPill(
                            label: p.name,
                            selected: ps.defaultPrinterName == p.name,
                            onTap: () async {
                              await ps.setDefaultPrinterName(p.name);
                              setState(() {});
                            },
                          )),
                    ],
                  ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: c.settings.thermalWidth == '80mm' ? '80mm' : '58mm',
                      decoration: const InputDecoration(labelText: 'Lebar Thermal'),
                      items: const [
                        DropdownMenuItem(value: '58mm', child: Text('58 mm')),
                        DropdownMenuItem(value: '80mm', child: Text('80 mm')),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        final next = Map<String, dynamic>.from(c.settings.raw)..['thermalWidth'] = v;
                        await NfSupabaseService.instance.saveStoreSettings(next);
                        await c.syncAllData();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: ['30x20', '40x30', '50x35', '58x40'].contains(c.settings.labelSize) ? c.settings.labelSize : '50x35',
                      decoration: const InputDecoration(labelText: 'Stiker Barcode'),
                      items: const [
                        DropdownMenuItem(value: '30x20', child: Text('30 × 20 mm')),
                        DropdownMenuItem(value: '40x30', child: Text('40 × 30 mm')),
                        DropdownMenuItem(value: '50x35', child: Text('50 × 35 mm')),
                        DropdownMenuItem(value: '58x40', child: Text('58 × 40 mm')),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        final next = Map<String, dynamic>.from(c.settings.raw)..['labelSize'] = v;
                        await NfSupabaseService.instance.saveStoreSettings(next);
                        await c.syncAllData();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          style: c.uiStyle,
          icon: Icons.hub_rounded,
          iconColor: const Color(0xFF0F766E),
          title: 'Master Data, Katalog & Cabang',
          subtitle: 'Cabang aktif: ${NfSupabaseService.instance.branchId} • ${c.isOwnerUnlocked ? 'Akses Owner Terbuka' : 'Terkunci PIN Owner'}',
          child: c.isOwnerUnlocked
              ? Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _openSuppliersModal,
                      icon: const Icon(Icons.local_shipping_rounded, size: 17),
                      label: Text('Supplier (${c.suppliers.length})'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _openResellersModal,
                      icon: const Icon(Icons.storefront_rounded, size: 17),
                      label: Text('Reseller (${c.resellers.length})'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _openRewardsModal,
                      icon: const Icon(Icons.workspace_premium_rounded, size: 17),
                      label: Text('Promo Poin (${c.pointRewards.length})'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _openBannersModal,
                      icon: const Icon(Icons.campaign_rounded, size: 17),
                      label: const Text('Banner Katalog'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openBranchModal,
                      icon: const Icon(Icons.store_mall_directory_rounded, size: 17),
                      label: Text('Cabang: ${NfSupabaseService.instance.branchId}'),
                    ),
                  ],
                )
              : OutlinedButton.icon(
                  onPressed: _unlockOwnerDialog,
                  icon: const Icon(Icons.lock_open_rounded, size: 18),
                  label: const Text('Masukkan PIN Owner untuk Kelola Master Data & Cabang'),
                ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          style: c.uiStyle,
          icon: Icons.verified_user_rounded,
          iconColor: const Color(0xFFD97706),
          title: 'Sesi Kasir, PIN & Keamanan Perangkat',
          subtitle: 'Aktif: ${c.session?.name ?? '-'} (${c.session?.role ?? '-'})',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _switchCashierDialog,
                icon: const Icon(Icons.switch_account_rounded, size: 18),
                label: const Text('Ganti Kasir Shift (PIN)'),
              ),
              if (!c.isOwnerUnlocked)
                OutlinedButton.icon(
                  onPressed: _unlockOwnerDialog,
                  icon: const Icon(Icons.lock_open_rounded, size: 18),
                  label: const Text('Buka Kunci Owner (PIN)'),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: NfColors.danger,
                  side: const BorderSide(color: Color(0xFFFECACA)),
                ),
                onPressed: () => c.signOut(),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Keluar Akun Perangkat'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _themeOptionCard({
    required bool active,
    required String title,
    required String subtitle,
    required Widget badge,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active ? NfColors.lightBg : Colors.white.withAlpha(220),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? NfColors.green : const Color(0xFFE2E8F0),
            width: active ? 2 : 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                badge,
                if (active) const Icon(Icons.check_circle_rounded, color: NfColors.green, size: 20),
              ],
            ),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
          ],
        ),
      ),
    );
  }

  Widget _printerPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected ? NfColors.green : const Color(0xFFF1F5F9),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : const Color(0xFF334155),
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required NfUiStyle style,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return NfGlassSurface(
      style: style,
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 19),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900))),
            ],
          ),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
