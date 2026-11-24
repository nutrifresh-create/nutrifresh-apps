import 'dart:io';
import 'dart:typed_data';
import 'package:nf_core/nf_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PosPrintService {
  PosPrintService._();
  static final PosPrintService instance = PosPrintService._();

  static const String _prefPrinterKey = 'nf_pos_default_printer_name';
  String? _defaultPrinterName;

  String? get defaultPrinterName => _defaultPrinterName;

  Future<void> loadSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString(_prefPrinterKey) ?? '').trim();
    _defaultPrinterName = saved.isEmpty ? null : saved;
  }

  Future<void> setDefaultPrinterName(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = (name ?? '').trim();
    _defaultPrinterName = clean.isEmpty ? null : clean;
    if (_defaultPrinterName == null) {
      await prefs.remove(_prefPrinterKey);
    } else {
      await prefs.setString(_prefPrinterKey, _defaultPrinterName!);
    }
  }

  Future<List<Printer>> listPrinters() async {
    try {
      return await Printing.listPrinters();
    } catch (_) {
      return [];
    }
  }

  Future<bool> _printPdfBytes(Uint8List bytes, String jobName) async {
    if (_defaultPrinterName != null && _defaultPrinterName!.isNotEmpty) {
      final printers = await listPrinters();
      for (final p in printers) {
        if (p.name == _defaultPrinterName) {
          final ok = await Printing.directPrintPdf(
            printer: p,
            name: jobName,
            onLayout: (_) async => bytes,
          );
          if (ok) return true;
        }
      }
    }
    await Printing.layoutPdf(
      name: jobName,
      onLayout: (_) async => bytes,
    );
    return true;
  }

  PdfPageFormat _thermalFormat(NfStoreSettings settings) {
    final is80 = settings.thermalWidth == '80mm';
    final w = is80 ? 80 * PdfPageFormat.mm : 58 * PdfPageFormat.mm;
    return PdfPageFormat(w, double.infinity, marginAll: 3 * PdfPageFormat.mm);
  }

  Future<Uint8List> buildReceiptPdf(
    NfTransaction tx,
    NfStoreSettings settings,
  ) async {
    final doc = pw.Document();
    final fmt = _thermalFormat(settings);
    final is80 = settings.thermalWidth == '80mm';
    final fs = is80 ? 9.0 : 8.0;

    doc.addPage(
      pw.Page(
        pageFormat: fmt,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                'NUTRIFRESH',
                style: pw.TextStyle(
                  fontSize: is80 ? 15 : 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                settings.receiptHeaderSub,
                style: pw.TextStyle(fontSize: fs - 0.5),
              ),
            ),
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
                    pw.Text(
                      name,
                      style: pw.TextStyle(
                        fontSize: fs,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          '${NfFormatters.stockDisplay(qty, unit)} x ${NfFormatters.rupiah(price)}',
                          style: pw.TextStyle(fontSize: fs - 0.5),
                        ),
                        pw.Text(
                          NfFormatters.rupiah(sub),
                          style: pw.TextStyle(
                            fontSize: fs,
                            fontWeight: pw.FontWeight.bold,
                          ),
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
                pw.Text(
                  'TOTAL',
                  style: pw.TextStyle(
                    fontSize: fs + 2,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  NfFormatters.rupiah(tx.total),
                  style: pw.TextStyle(
                    fontSize: fs + 2,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
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
                    style: pw.TextStyle(
                      fontSize: fs - 0.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
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
            pw.SizedBox(height: 10),
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
    await for (final page in Printing.raster(pdfBytes, pages: [0], dpi: 220)) {
      pngBytes = await page.toPng();
      break;
    }
    if (pngBytes == null) throw Exception('Gagal merender resi PNG.');
    return _savePngFile('Resi_NutriFresh_${tx.id}.png', pngBytes);
  }

  Future<Uint8List> buildBarcodeLabelPdf(
    NfProduct product,
    NfStoreSettings settings, {
    int copies = 1,
  }) async {
    final dims = <String, List<double>>{
      '30x20': [30, 20],
      '40x30': [40, 30],
      '50x35': [50, 35],
      '58x40': [58, 40],
    }[settings.labelSize] ?? [50, 35];

    final fmt = PdfPageFormat(
      dims[0] * PdfPageFormat.mm,
      dims[1] * PdfPageFormat.mm,
      marginAll: 2 * PdfPageFormat.mm,
    );
    final codeVal = product.barcode.trim().isEmpty ? product.id : product.barcode.trim();
    final priceText =
        '${NfFormatters.rupiah(product.price)} / ${NfFormatters.catalogPriceUnit(product.unit)}';

    final doc = pw.Document();
    final count = copies < 1 ? 1 : copies;
    for (int i = 0; i < count; i++) {
      doc.addPage(
        pw.Page(
          pageFormat: fmt,
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'NUTRIFRESH',
                style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                product.name,
                maxLines: 1,
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                priceText,
                style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
              ),
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: codeVal,
                    drawText: true,
                    textStyle: const pw.TextStyle(fontSize: 7),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return doc.save();
  }

  Future<void> printBarcodeLabel(
    NfProduct product,
    NfStoreSettings settings, {
    int copies = 1,
  }) async {
    final bytes = await buildBarcodeLabelPdf(product, settings, copies: copies);
    await _printPdfBytes(bytes, 'Barcode_${product.barcode}');
  }

  Future<String> exportBarcodeLabelPng(
    NfProduct product,
    NfStoreSettings settings,
  ) async {
    final pdfBytes = await buildBarcodeLabelPdf(product, settings, copies: 1);
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
    doc.addPage(
      pw.Page(
        pageFormat: fmt,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                'NUTRIFRESH\nLAPORAN TUTUP SHIFT',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
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
    final fmt = _thermalFormat(settings);
    final itemsToPrint = po.items.isNotEmpty
        ? po.items
        : [{'parcelType': 'Parcel Custom', 'qty': 1, 'unitPrice': po.totalAmount, 'deliveryMode': 'Diantar'}];
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
              decoration: pw.BoxDecoration(
                border: pw.Border.all(width: 1.2),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'NUTRIFRESH PARSEL',
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        po.orderCode,
                        style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                  pw.Divider(thickness: 0.8),
                  pw.Text(
                    '${po.customerName}${po.institution.isNotEmpty ? ' (${po.institution})' : ''}',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '${it['deliveryMode'] ?? 'Diantar'} • ${it['deliveryDate'] ?? po.deliveryDate} • ${it['deliveryTime'] ?? po.deliveryTime}',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    '${qty}x ${it['parcelType'] ?? 'Parcel'} @${NfFormatters.rupiah(unitPrice)}',
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                  ),
                  if ((it['note'] ?? '').toString().isNotEmpty)
                    pw.Text('Isi: ${it['note']}', style: const pw.TextStyle(fontSize: 8)),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'Tujuan: ${d['address'] ?? '-'}',
                    style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Bayar: ${po.paymentStatus}', style: const pw.TextStyle(fontSize: 7.5)),
                      pw.Text(
                        'WA: ${NfFormatters.localWaDisplay(po.customerPhone)}',
                        style: const pw.TextStyle(fontSize: 7.5),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
    await _printPdfBytes(await doc.save(), 'Stiker_${po.orderCode}');
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
