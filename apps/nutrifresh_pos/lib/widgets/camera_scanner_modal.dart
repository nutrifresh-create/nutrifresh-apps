import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nf_core/nf_core.dart';

/// Membuka Kamera Scanner Barcode PLU / QR Member pada Tablet / HP Android.
/// Di Windows PC (.exe), menampilkan pengingat untuk memakai Barcode Scanner USB.
Future<String?> openBarcodeQrCameraScanner({
  required BuildContext context,
  required NfUiStyle style,
  String title = 'Scan Barcode PLU / QR',
  String hint = 'Arahkan kamera ke barcode produk atau kartu QR Member',
}) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    final manualCtrl = TextEditingController();
    final res = await showNfGlassModal<String>(
      context: context,
      style: style,
      title: title,
      subtitle: 'Di PC Windows, arahkan Barcode Scanner USB atau ketik kode lalu Enter',
      icon: Icons.qr_code_scanner_rounded,
      headerGradient: const [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: manualCtrl,
            autofocus: true,
            decoration: InputDecoration(labelText: hint),
            onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(manualCtrl.text.trim()),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Gunakan Kode'),
          ),
        ],
      ),
    );
    manualCtrl.dispose();
    return (res != null && res.isNotEmpty) ? res : null;
  }

  return Navigator.of(context).push<String>(
    PageRouteBuilder(
      opaque: false,
      pageBuilder: (_, __, ___) => _CameraScannerPage(title: title, hint: hint),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ),
  );
}

class _CameraScannerPage extends StatefulWidget {
  final String title;
  final String hint;
  const _CameraScannerPage({required this.title, required this.hint});

  @override
  State<_CameraScannerPage> createState() => _CameraScannerPageState();
}

class _CameraScannerPageState extends State<_CameraScannerPage>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _scannerCtrl = MobileScannerController();
  late final AnimationController _laserAnim;
  bool _handled = false;
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    _laserAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _laserAnim.dispose();
    _scannerCtrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final bc in capture.barcodes) {
      final raw = (bc.rawValue ?? '').trim();
      if (raw.isNotEmpty) {
        _handled = true;
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.click);
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scannerCtrl,
            onDetect: _onDetect,
          ),
          // Bingkai Bidik Modern
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 190,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF8BC34A), width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8BC34A).withAlpha(90),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: AnimatedBuilder(
                  animation: _laserAnim,
                  builder: (_, __) => Align(
                    alignment: Alignment(0, (_laserAnim.value * 1.7) - 0.85),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFA3E635),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFFA3E635).withAlpha(180), blurRadius: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Header Transparan
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 14,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(155),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withAlpha(65)),
              ),
              child: Row(
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Senter / Flash',
                    onPressed: () {
                      setState(() => _torchOn = !_torchOn);
                      _scannerCtrl.toggleTorch();
                    },
                    icon: Icon(
                      _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                      color: _torchOn ? const Color(0xFFFDE047) : Colors.white,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ganti Kamera',
                    onPressed: () => _scannerCtrl.switchCamera(),
                    icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          // Petunjuk Bawah
          Positioned(
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).padding.bottom + 36,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(165),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withAlpha(45)),
              ),
              child: Text(
                widget.hint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
