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
  List<Printer> _printers = [];
  bool _loadingPrinters = false;

  @override
  void initState() {
    super.initState();
    _refreshPrinters();
  }

  Future<void> _refreshPrinters() async {
    setState(() => _loadingPrinters = true);
    final list = await PosPrintService.instance.listPrinters();
    if (mounted) {
      setState(() {
        _printers = list;
        _loadingPrinters = false;
      });
    }
  }

  Future<void> _switchCashierDialog() async {
    final c = widget.controller;
    final activeEmps = c.employees.where((e) => e.isActive).toList();
    if (activeEmps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daftar karyawan belum tersedia.')),
      );
      return;
    }
    NfEmployee selected = activeEmps.first;
    final pinCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Ganti Kasir Shift (PIN)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<NfEmployee>(
                  value: selected,
                  decoration: const InputDecoration(labelText: 'Pilih Nama Karyawan'),
                  items: activeEmps
                      .map((e) => DropdownMenuItem(value: e, child: Text('${e.name} (${e.role})')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setD(() => selected = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'PIN Pribadi Karyawan'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Aktifkan Kasir')),
          ],
        ),
      ),
    );
    if (ok == true) {
      final err = await c.switchCashierByPin(selected, pinCtrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err ?? 'Kasir aktif berganti ke ${selected.name}')),
        );
      }
    }
    pinCtrl.dispose();
  }

  Future<void> _unlockOwnerDialog() async {
    final pinCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Buka Akses Owner (PIN)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        content: TextField(
          controller: pinCtrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Masukkan PIN Owner'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Buka Kunci')),
        ],
      ),
    );
    if (ok == true) {
      final err = await widget.controller.unlockOwnerWithPin(pinCtrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err ?? 'Akses Owner aktif (Laba & VOID terbuka).')),
        );
      }
    }
    pinCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final defaultPrinter = PosPrintService.instance.defaultPrinterName;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionCard(
          title: 'Printer Langsung (Tanpa Pop-Up Browser)',
          subtitle: 'Pilih printer thermal Windows Anda agar struk, label barcode, tutup shift, dan stiker PO langsung tercetak.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      defaultPrinter == null
                          ? 'Printer Default: Dialog Sistem (Belum dipilih)'
                          : 'Printer Langsung Aktif: $defaultPrinter',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: NfColors.greenDark),
                    ),
                  ),
                  IconButton(
                    onPressed: _loadingPrinters ? null : _refreshPrinters,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_printers.isEmpty)
                const Text(
                  'Tidak ada daftar printer lokal terdeteksi (di Tablet Android, cetak memakai layanan print/Bluetooth sistem).',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Tanya Setiap Cetak'),
                      selected: defaultPrinter == null,
                      onSelected: (_) async {
                        await PosPrintService.instance.setDefaultPrinterName(null);
                        setState(() {});
                      },
                    ),
                    ..._printers.map((p) {
                      final sel = defaultPrinter == p.name;
                      return ChoiceChip(
                        label: Text(p.name),
                        selected: sel,
                        selectedColor: NfColors.green,
                        onSelected: (_) async {
                          await PosPrintService.instance.setDefaultPrinterName(p.name);
                          setState(() {});
                        },
                      );
                    }),
                  ],
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: c.settings.thermalWidth == '80mm' ? '80mm' : '58mm',
                      decoration: const InputDecoration(labelText: 'Lebar Kertas Thermal'),
                      items: const [
                        DropdownMenuItem(value: '58mm', child: Text('58 mm (Kecil)')),
                        DropdownMenuItem(value: '80mm', child: Text('80 mm (Lebar)')),
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
                      value: ['30x20', '40x30', '50x35', '58x40'].contains(c.settings.labelSize)
                          ? c.settings.labelSize
                          : '50x35',
                      decoration: const InputDecoration(labelText: 'Ukuran Stiker Barcode'),
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
        const SizedBox(height: 14),
        _sectionCard(
          title: 'Tema Tampilan POS (Perangkat Ini)',
          subtitle: 'Pilih gaya Natural untuk tampilan bersih & ringan, atau Glass bernuansa hijau lembut.',
          child: SegmentedButton<NfUiStyle>(
            segments: const [
              ButtonSegment(value: NfUiStyle.natural, icon: Icon(Icons.eco_rounded), label: Text('Natural (Ringan)')),
              ButtonSegment(value: NfUiStyle.glass, icon: Icon(Icons.auto_awesome_rounded), label: Text('Liquid Glass')),
            ],
            selected: {c.uiStyle},
            onSelectionChanged: (s) => c.setUiStyle(s.first),
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          title: 'Sesi Kasir, PIN & Keamanan Perangkat',
          subtitle: 'Aktif saat ini: ${c.session?.name ?? '-'} (${c.session?.role ?? '-'})',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: _switchCashierDialog,
                icon: const Icon(Icons.switch_account_rounded),
                label: const Text('Ganti Kasir Shift (PIN)'),
              ),
              if (!c.isOwnerUnlocked)
                OutlinedButton.icon(
                  onPressed: _unlockOwnerDialog,
                  icon: const Icon(Icons.lock_open_rounded),
                  label: const Text('Buka Kunci Owner (PIN)'),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: NfColors.danger),
                onPressed: () => c.signOut(),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Keluar Akun Perangkat'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({required String title, required String subtitle, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
