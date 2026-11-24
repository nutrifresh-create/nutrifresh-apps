import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:nf_core/nf_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BtPrinterDevice {
  final String name;
  final String address;
  const BtPrinterDevice({required this.name, required this.address});
}

class PosPrintService {
  PosPrintService._();
  static final PosPrintService instance = PosPrintService._();

  static const MethodChannel _btChannel =
      MethodChannel('id.my.nutrifresh.pos/bt_printer');

  static const String _prefWinPrinterKey = 'nf_pos_default_printer_name';
  static const String _prefBtAddrKey = 'nf_pos_bt_printer_addr';
  static const String _prefBtNameKey = 'nf_pos_bt_printer_name';
  static const String _prefBtLabelProtoKey = 'nf_pos_bt_label_protocol';

  String? _defaultPrinterName;
  String? _btAddress;
  String? _btName;
  String _btLabelProtocol = 'escpos'; // 'escpos' | 'tspl'
  Uint8List? _cachedLogoPBytes;

  String? get defaultPrinterName => _defaultPrinterName;
  String? get btPrinterAddress => _btAddress;
  String? get btPrinterName => _btName;
  String get btLabelProtocol => _btLabelProtocol;

  bool get hasDirectPrinter => Platform.isAndroid
      ? (_btAddress != null && _btAddress!.isNotEmpty)
      : (_defaultPrinterName != null && _defaultPrinterName!.isNotEmpty);

  String get activePrinterSummary {
    if (Platform.isAndroid) {
      if (_btName != null && _btName!.isNotEmpty) {
        return 'Bluetooth: $_btName (${_btLabelProtocol.toUpperCase()})';
      }
      return 'Dialog Sistem (Belum pilih Bluetooth)';
    }
    return (_defaultPrinterName != null && _defaultPrinterName!.isNotEmpty)
        ? 'Windows: $_defaultPrinterName'
        : 'Dialog Sistem (Belum pilih Printer)';
  }

  Future<void> loadSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final savedWin = (prefs.getString(_prefWinPrinterKey) ?? '').trim();
    _defaultPrinterName = savedWin.isEmpty ? null : savedWin;
    final savedBtAddr = (prefs.getString(_prefBtAddrKey) ?? '').trim();
    final savedBtName = (prefs.getString(_prefBtNameKey) ?? '').trim();
    _btAddress = savedBtAddr.isEmpty ? null : savedBtAddr;
    _btName = savedBtName.isEmpty ? null : savedBtName;
    final proto = (prefs.getString(_prefBtLabelProtoKey) ?? 'escpos').trim();
    _btLabelProtocol = proto == 'tspl' ? 'tspl' : 'escpos';
  }

  Future<void> setDefaultPrinterName(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = (name ?? '').trim();
    _defaultPrinterName = clean.isEmpty ? null : clean;
    if (_defaultPrinterName == null) {
      await prefs.remove(_prefWinPrinterKey);
    } else {
      await prefs.setString(_prefWinPrinterKey, _defaultPrinterName!);
    }
  }

  Future<void> setBluetoothPrinter(BtPrinterDevice? dev) async {
    final prefs = await SharedPreferences.getInstance();
    if (dev == null || dev.address.trim().isEmpty) {
      _btAddress = null;
      _btName = null;
      await prefs.remove(_prefBtAddrKey);
      await prefs.remove(_prefBtNameKey);
    } else {
      _btAddress = dev.address.trim();
      _btName = dev.name.trim();
      await prefs.setString(_prefBtAddrKey, _btAddress!);
      await prefs.setString(_prefBtNameKey, _btName!);
    }
  }

  Future<void> setBtLabelProtocol(String proto) async {
    final clean = proto == 'tspl' ? 'tspl' : 'escpos';
    _btLabelProtocol = clean;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefBtLabelProtoKey, clean);
  }

  Future<List<Printer>> listWindowsPrinters() async {
    if (Platform.isAndroid) return [];
    try {
      return await Printing.listPrinters();
    } catch (_) {
      return [];
    }
  }

  Future<List<BtPrinterDevice>> listBluetoothPrinters() async {
    if (!Platform.isAndroid) return [];
    try {
      await _btChannel.invokeMethod('requestPermissions');
      final raw = await _btChannel.invokeMethod<List<dynamic>>('getBondedDevices');
      if (raw == null) return [];
      return raw
          .whereType<Map>()
          .map((m) => BtPrinterDevice(
                name: (m['name'] ?? 'Printer Bluetooth').toString(),
                address: (m['address'] ?? '').toString(),
              ))
          .where((d) => d.address.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Uint8List?> _loadThermalLogoBytes() async {
    if (_cachedLogoPBytes != null) return _cachedLogoPBytes;
    try {
      final bd = await rootBundle.load('assets/images/iconP.png');
      _cachedLogoPBytes = bd.buffer.asUint8List();
      return _cachedLogoPBytes;
    } catch (_) {
      return null;
    }
  }

  Uint8List _rgbaToEscPosRaster(Uint8List rgba, int width, int height) {
    final widthBytes = (width + 7) >> 3;
    final out = BytesBuilder(copy: false);
    out.add(const [0x1B, 0x40, 0x1B, 0x61, 0x01]);
    const maxBandH = 120;
    for (int y0 = 0; y0 < height; y0 += maxBandH) {
      final bandH = (y0 + maxBandH <= height) ? maxBandH : (height - y0);
      out.add([
        0x1D, 0x76, 0x30, 0x00,
        widthBytes & 0xFF, (widthBytes >> 8) & 0xFF,
        bandH & 0xFF, (bandH >> 8) & 0xFF,
      ]);
      final bandBuf = Uint8List(widthBytes * bandH);
      for (int y = 0; y < bandH; y++) {
        final sy = y0 + y;
        for (int x = 0; x < width; x++) {
          final idx = (sy * width + x) * 4;
          final r = rgba[idx];
          final g = rgba[idx + 1];
          final b = rgba[idx + 2];
          final a = rgba[idx + 3];
          final lum = (299 * r + 587 * g + 114 * b) ~/ 1000;
          if (a > 128 && lum < 170) {
            bandBuf[y * widthBytes + (x >> 3)] |= (0x80 >> (x & 7));
          }
        }
      }
      out.add(bandBuf);
    }
    out.add(const [0x1B, 0x64, 0x03, 0x1D, 0x56, 0x42, 0x00]);
    return out.toBytes();
  }

  Uint8List _rgbaToTsplBitmap(
    Uint8List rgba,
    int width,
    int height, {
    required double widthMm,
    required double heightMm,
  }) {
    final widthBytes = (width + 7) >> 3;
    final bitmap = Uint8List(widthBytes * height);
    bitmap.fillRange(0, bitmap.length, 0xFF);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = (y * width + x) * 4;
        final r = rgba[idx];
        final g = rgba[idx + 1];
        final b = rgba[idx + 2];
        final a = rgba[idx + 3];
        final lum = (299 * r + 587 * g + 114 * b) ~/ 1000;
        if (a > 128 && lum < 170) {
          bitmap[y * widthBytes + (x >> 3)] &= ~(0x80 >> (x & 7));
        }
      }
    }
    final header = 'SIZE ${widthMm.toStringAsFixed(0)} mm, ${heightMm.toStringAsFixed(0)} mm\r\n'
        'GAP 2 mm, 0 mm\r\n'
        'DIRECTION 1\r\n'
        'CLS\r\n'
        'BITMAP 0,0,$widthBytes,$height,0,';
    const footer = '\r\nPRINT 1,1\r\n';
    final out = BytesBuilder(copy: false);
    out.add(ascii.encode(header));
    out.add(bitmap);
    out.add(ascii.encode(footer));
    return out.toBytes();
  }

  Future<bool> _printPdfBytes(
    Uint8List pdfBytes,
    String jobName, {
    bool isLabelJob = false,
    double labelWidthMm = 50,
    double labelHeightMm = 35,
  }) async {
    if (Platform.isAndroid && _btAddress != null && _btAddress!.isNotEmpty) {
      try {
        final allBytes = BytesBuilder(copy: false);
        final useTspl = isLabelJob && _btLabelProtocol == 'tspl';
        await for (final page in Printing.raster(pdfBytes, dpi: 203)) {
          if (useTspl) {
            allBytes.add(_rgbaToTsplBitmap(
              page.pixels,
              page.width,
              page.height,
              widthMm: labelWidthMm,
              heightMm: labelHeightMm,
            ));
          } else {
            allBytes.add(_rgbaToEscPosRaster(page.pixels, page.width, page.height));
          }
        }
        final payload = allBytes.toBytes();
        if (payload.isNotEmpty) {
          final ok = await _btChannel.invokeMethod<bool>('printBytes', {
            'address': _btAddress,
            'bytes': payload,
          });
          if (ok == true) return true;
        }
      } catch (_) {}
    }

    if (!Platform.isAndroid && _defaultPrinterName != null && _defaultPrinterName!.isNotEmpty) {
      final printers = await listWindowsPrinters();
      for (final p in printers) {
        if (p.name == _defaultPrinterName) {
          final ok = await Printing.directPrintPdf(
            printer: p,
            name: jobName,
            onLayout: (_) async => pdfBytes,
          );
          if (ok) return true;
        }
      }
    }

    await Printing.layoutPdf(name: jobName, onLayout: (_) async => pdfBytes);
    return true;
  }

  Future<void> printTestPage(NfStoreSettings settings) async {
    final doc = pw.Document();
    final fmt = _thermalFormat(settings);
    final logoBytes = await _loadThermalLogoBytes();
    final logoImg = logoBytes != null ? pw.MemoryImage(logoBytes) : null;
    doc.addPage(
      pw.Page(
        pageFormat: fmt,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logoImg != null) pw.Image(logoImg, width: 90, fit: pw.BoxFit.contain),
            pw.SizedBox(height: 4),
            pw.Text('TES PRINTER NUTRIFRESH POS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            pw.Text('Koneksi: $activePrinterSummary', style: const pw.TextStyle(fontSize: 7.5)),
            pw.Text('Waktu: ${NfFormatters.dateTimeShort(DateTime.now())}', style: const pw.TextStyle(fontSize: 7.5)),
            pw.Divider(borderStyle: pw.BorderStyle.dashed),
            pw.Text('Printer siap digunakan!', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
          ],
        ),
      ),
    );
    await _printPdfBytes(await doc.save(), 'Test_Print_NutriFresh');
  }

  PdfPageFormat _thermalFormat(NfStoreSettings settings) {
    final is80 = settings.thermalWidth == '80mm';
    final w = is80 ? 76 * PdfPageFormat.mm : 48 * PdfPageFormat.mm;
    return PdfPageFormat(w, double.infinity, marginAll: 2 * PdfPageFormat.mm);
  }

  List<double> _labelDims(NfStoreSettings settings) {
    return <String, List<double>>{
          '30x20': [30, 20],
          '40x30': [40, 30],
          '50x35': [50, 35],
          '58x40': [58, 40],
        }[settings.labelSize] ??
        [50, 35];
  }

  Future<Uint8List> buildReceiptPdf(
    NfTransaction tx,
    NfStoreSettings settings,
  ) async {
    final doc = pw.Document();
    final fmt = _thermalFormat(settings);
    final is80 = settings.thermalWidth == '80mm';
    final fs = is80 ? 9.0 : 8.0;
    final logoBytes = await _loadThermalLogoBytes();
    final logoImg = logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    doc.addPage(
      pw.Page(
        pageFormat: fmt,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (logoImg != null)
              pw.Center(child: pw.Image(logoImg, width: is80 ? 115 : 88, fit: pw.BoxFit.contain))
            else
              pw.Center(
                child: pw.Text(
                  'NUTRIFRESH',
                  style: pw.TextStyle(fontSize: is80 ? 15 : 13, fontWeight: pw.FontWeight.bold),
                ),
              ),
            pw.SizedBox(height: 2),
            pw.Center(child: pw.Text(settings.receiptHeaderSub, style: pw.TextStyle(fontSize: fs - 0.5))),
            if (settings.shopAddress.isNotEmpty)
              pw.Center(
                child: pw.Text(
                  settings.shopAddress,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: fs - 1.0),
                ),
              ),
            pw.Center(
              child: pw.Text(
                'WA: ${NfFormatters.localWaDisplay(settings.waNumber)}',
                style: pw.TextStyle(fontSize: fs - 0.5),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.7),
            _metaRow('Nota', tx.id, fs),
            _metaRow('Waktu', NfFormatters.dateTimeShort(tx.date), fs),
            _metaRow('Kasir', tx.cashier, fs),
            _metaRow('Pelanggan', tx.customerName, fs),
            _metaRow('Bayar', tx.paymentMethod, fs),
            pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.7),
            ...tx.items.map((it) {
              final name = (it['name'] ?? '-').toString();
              final qty = (it['qty'] is num) ? (it['qty'] as num) : 0;
              final unit = (it['unit'] ?? 'Gram').toString();
              final price = (it['price'] is num) ? (it['price'] as num) : 0;
              final sub = (it['subtotal'] is num) ? (it['subtotal'] as num) : 0;
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(name, style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold)),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          '${NfFormatters.stockDisplay(qty, unit)} x ${NfFormatters.rupiah(price)}',
                          style: pw.TextStyle(fontSize: fs - 0.5),
                        ),
                        pw.Text(
                          NfFormatters.rupiah(sub),
                          style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
            pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.7),
            if (tx.totalDiscount > 0)
              _metaRow('Diskon', '-${NfFormatters.rupiah(tx.totalDiscount)}', fs),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('TOTAL', style: pw.TextStyle(fontSize: fs + 2, fontWeight: pw.FontWeight.bold)),
                pw.Text(NfFormatters.rupiah(tx.total), style: pw.TextStyle(fontSize: fs + 2, fontWeight: pw.FontWeight.bold)),
              ],
            ),
            if (tx.paymentMethod == 'Tunai') ...[
              _metaRow('Tunai', NfFormatters.rupiah(tx.cash), fs),
              _metaRow('Kembali', NfFormatters.rupiah(tx.change), fs),
            ],
            if (tx.pointsEarned > 0)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 3),
                child: pw.Center(
                  child: pw.Text(
                    '+${tx.pointsEarned} Poin (Saldo: ${tx.pointsAfter})',
                    style: pw.TextStyle(fontSize: fs - 0.5, fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ),
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(
                settings.receiptFooterText,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: fs - 0.5),
              ),
            ),
            pw.SizedBox(height: 8),
          ],
        ),
      ),
    );
    return doc.save();
  }

  pw.Widget _metaRow(String k, String v, double fs) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(k, style: pw.TextStyle(fontSize: fs - 0.5)),
        pw.Expanded(
          child: pw.Text(
            v,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(fontSize: fs - 0.5, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Future<void> printReceipt(NfTransaction tx, NfStoreSettings settings) async {
    final bytes = await buildReceiptPdf(tx, settings);
    await _printPdfBytes(bytes, 'Struk_${tx.id}');
  }

  Future<String> exportReceiptPng(
    NfTransaction tx,
    NfStoreSettings settings,
  ) async {
    final pdfBytes = await buildReceiptPdf(tx, settings);
    Uint8List? pngBytes;
    await for (final page in Printing.raster(pdfBytes, pages: [0], dpi: 240)) {
      pngBytes = await page.toPng();
      break;
    }
    if (pngBytes == null) throw Exception('Gagal merender resi PNG.');
    return _savePngFile('Resi_NutriFresh_${tx.id}.png', pngBytes);
  }

  Future<Uint8List> buildBatchBarcodePdf(
    List<(NfProduct, int)> tasks,
    NfStoreSettings settings,
  ) async {
    final dims = _labelDims(settings);
    final fmt = PdfPageFormat(
      dims[0] * PdfPageFormat.mm,
      dims[1] * PdfPageFormat.mm,
      marginAll: 1.8 * PdfPageFormat.mm,
    );
    final logoBytes = await _loadThermalLogoBytes();
    final logoImg = logoBytes != null ? pw.MemoryImage(logoBytes) : null;
    final doc = pw.Document();

    for (final (product, copies) in tasks) {
      final codeVal = product.barcode.trim().isEmpty ? product.id : product.barcode.trim();
      final priceText =
          '${NfFormatters.rupiah(product.price)} / ${NfFormatters.catalogPriceUnit(product.unit)}';
      final count = copies < 1 ? 1 : copies;
      for (int i = 0; i < count; i++) {
        doc.addPage(
          pw.Page(
            pageFormat: fmt,
            build: (_) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (logoImg != null)
                  pw.Image(logoImg, height: dims[1] <= 22 ? 12 : 16, fit: pw.BoxFit.contain)
                else
                  pw.Text('NUTRIFRESH', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                  product.name,
                  maxLines: 1,
                  style: pw.TextStyle(fontSize: dims[1] <= 22 ? 7.5 : 9, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  priceText,
                  style: pw.TextStyle(fontSize: dims[1] <= 22 ? 7.5 : 8.5, fontWeight: pw.FontWeight.bold),
                ),
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.code128(),
                      data: codeVal,
                      drawText: true,
                      textStyle: const pw.TextStyle(fontSize: 6.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    return doc.save();
  }

  Future<void> printBarcodeLabel(
    NfProduct product,
    NfStoreSettings settings, {
    int copies = 1,
  }) async {
    final dims = _labelDims(settings);
    final bytes = await buildBatchBarcodePdf([(product, copies)], settings);
    await _printPdfBytes(
      bytes,
      'Barcode_${product.barcode}',
      isLabelJob: true,
      labelWidthMm: dims[0],
      labelHeightMm: dims[1],
    );
  }

  Future<void> printBatchBarcodeLabels(
    List<(NfProduct, int)> tasks,
    NfStoreSettings settings,
  ) async {
    if (tasks.isEmpty) return;
    final dims = _labelDims(settings);
    final bytes = await buildBatchBarcodePdf(tasks, settings);
    await _printPdfBytes(
      bytes,
      'Batch_Barcode_NutriFresh',
      isLabelJob: true,
      labelWidthMm: dims[0],
      labelHeightMm: dims[1],
    );
  }

  Future<String> exportBarcodeLabelPng(
    NfProduct product,
    NfStoreSettings settings,
  ) async {
    final pdfBytes = await buildBatchBarcodePdf([(product, 1)], settings);
    Uint8List? pngBytes;
    await for (final page in Printing.raster(pdfBytes, pages: [0], dpi: 240)) {
      pngBytes = await page.toPng();
      break;
    }
    if (pngBytes == null) throw Exception('Gagal merender label PNG.');
    final safe = product.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return _savePngFile('Label_${product.barcode}_$safe.png', pngBytes);
  }

  Future<void> printShiftReport(
    Map<String, dynamic> rec,
    NfStoreSettings settings,
  ) async {
    final doc = pw.Document();
    final fmt = _thermalFormat(settings);
    const fs = 8.5;
    final logoBytes = await _loadThermalLogoBytes();
    final logoImg = logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    doc.addPage(
      pw.Page(
        pageFormat: fmt,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (logoImg != null)
              pw.Center(child: pw.Image(logoImg, width: 84, fit: pw.BoxFit.contain)),
            pw.Center(
              child: pw.Text(
                'LAPORAN TUTUP SHIFT KASIR',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Divider(borderStyle: pw.BorderStyle.dashed),
            _metaRow('ID Shift', '${rec['id'] ?? '-'}', fs),
            _metaRow('Kasir', '${rec['cashierName'] ?? '-'}', fs),
            _metaRow('Waktu', NfFormatters.dateTimeShort(DateTime.now()), fs),
            pw.Divider(borderStyle: pw.BorderStyle.dashed),
            _metaRow('Modal Awal', NfFormatters.rupiah((rec['initialCash'] as num?) ?? 0), fs),
            _metaRow('Jual Tunai', '+${NfFormatters.rupiah((rec['cashSales'] as num?) ?? 0)}', fs),
            _metaRow('Kas Keluar', '-${NfFormatters.rupiah((rec['cashExpenses'] as num?) ?? 0)}', fs),
            pw.Divider(borderStyle: pw.BorderStyle.dashed),
            _metaRow('TARGET LACI', NfFormatters.rupiah((rec['expectedCash'] as num?) ?? 0), fs),
            _metaRow('FISIK RIIL', NfFormatters.rupiah((rec['actualCash'] as num?) ?? 0), fs),
            _metaRow(
              'SELISIH',
              '${rec['status'] ?? '-'} (${NfFormatters.rupiah((rec['discrepancy'] as num?) ?? 0)})',
              fs,
            ),
            pw.SizedBox(height: 6),
            pw.Text('Catatan: ${rec['note'] ?? '-'}', style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 18),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Kasir', style: const pw.TextStyle(fontSize: 8)),
                pw.Text('Owner/Penerima', style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          ],
        ),
      ),
    );
    await _printPdfBytes(await doc.save(), 'Shift_${rec['id'] ?? 'POS'}');
  }

  Future<void> printParcelStickers(
    NfParcelOrder po,
    NfStoreSettings settings,
  ) async {
    final doc = pw.Document();
    final dims = _labelDims(settings);
    final useTspl = Platform.isAndroid && _btLabelProtocol == 'tspl';
    final fmt = useTspl
        ? PdfPageFormat(dims[0] * PdfPageFormat.mm, dims[1] * PdfPageFormat.mm, marginAll: 1.5 * PdfPageFormat.mm)
        : _thermalFormat(settings);
    final itemsToPrint = po.items.isNotEmpty
        ? po.items
        : [{'parcelType': 'Parcel Keranjang', 'qty': 1, 'unitPrice': po.totalAmount, 'deliveryMode': 'Diantar'}];
    for (final it in itemsToPrint) {
      final rawDests = it['destinations'];
      final dests = (rawDests is List && rawDests.isNotEmpty)
          ? rawDests.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : [
              {
                'address': it['deliveryMode'] == 'Diambil' ? 'DIAMBIL DI TOKO' : '-',
                'qty': it['qty'] ?? 1,
              }
            ];
      for (final d in dests) {
        final unitPrice = (it['unitPrice'] is num) ? (it['unitPrice'] as num) : 0;
        final qty = d['qty'] ?? it['qty'] ?? 1;
        doc.addPage(
          pw.Page(
            pageFormat: fmt,
            build: (_) => pw.Container(
              padding: const pw.EdgeInsets.all(4),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.2)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('NUTRIFRESH PARSEL', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                      pw.Text(po.orderCode, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.Divider(thickness: 0.7),
                  pw.Text(
                    '${po.customerName}${po.institution.isNotEmpty ? ' (${po.institution})' : ''}',
                    style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '${it['deliveryMode'] ?? 'Diantar'} • ${it['deliveryDate'] ?? po.deliveryDate} • ${it['deliveryTime'] ?? po.deliveryTime}',
                    style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '${qty}x ${it['parcelType'] ?? 'Parcel'} @${NfFormatters.rupiah(unitPrice)}',
                    style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                  ),
                  if ((it['note'] ?? '').toString().isNotEmpty)
                    pw.Text('Isi: ${it['note']}', style: const pw.TextStyle(fontSize: 7.5)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Tujuan: ${d['address'] ?? '-'}',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Bayar: ${po.paymentStatus}', style: const pw.TextStyle(fontSize: 7)),
                      pw.Text('WA: ${NfFormatters.localWaDisplay(po.customerPhone)}', style: const pw.TextStyle(fontSize: 7)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
    await _printPdfBytes(
      await doc.save(),
      'Stiker_${po.orderCode}',
      isLabelJob: true,
      labelWidthMm: dims[0],
      labelHeightMm: dims[1],
    );
  }

  Future<String> _savePngFile(String fileName, Uint8List bytes) async {
    Directory? dir;
    if (Platform.isWindows) {
      dir = await getDownloadsDirectory();
    }
    dir ??= await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}${Platform.pathSeparator}NutriFresh_Exports');
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }
    final file = File('${outDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
