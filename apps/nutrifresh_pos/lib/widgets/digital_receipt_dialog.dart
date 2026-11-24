import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nf_core/nf_core.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/pos_print_service.dart';

Future<void> showDigitalReceiptGlassModal({
  required BuildContext context,
  required NfUiStyle style,
  required NfTransaction tx,
  required NfStoreSettings settings,
  bool justPaid = false,
}) {
  return showNfGlassModal<void>(
    context: context,
    style: style,
    title: justPaid ? 'Transaksi Berhasil!' : 'Resi Digital ${tx.id}',
    subtitle: '${tx.customerName} • ${NfFormatters.rupiah(tx.total)} (${tx.paymentMethod})',
    icon: justPaid ? Icons.check_circle_rounded : Icons.receipt_long_rounded,
    headerGradient: const [Color(0xFF558B2F), Color(0xFF7CB342)],
    builder: (ctx) => _DigitalReceiptContent(tx: tx, settings: settings),
  );
}

class _DigitalReceiptContent extends StatelessWidget {
  final NfTransaction tx;
  final NfStoreSettings settings;

  const _DigitalReceiptContent({required this.tx, required this.settings});

  String get _receiptUrl =>
      '${NfConfig.publicWebOrigin}/?resi=${Uri.encodeComponent(tx.id)}&k=${Uri.encodeComponent(tx.receiptToken)}';

  Future<void> _sendWa() async {
    final msg = 'Halo Kak *${tx.customerName}* 🍐\n'
        'Terima kasih telah berbelanja di *NutriFresh*!\n\n'
        'No. Nota: *${tx.id}*\n'
        'Total Bayar: *${NfFormatters.rupiah(tx.total)}* (${tx.paymentMethod} — LUNAS)\n'
        '${tx.pointsEarned > 0 ? '⭐ Poin didapat: +${tx.pointsEarned} Poin (Saldo: ${tx.pointsAfter})\n' : ''}'
        '\n🧾 *Resi Digital (Simpan PNG/PDF):*\n$_receiptUrl';
    final ph = NfFormatters.normalizeWaPhone(tx.customerPhone);
    final url = ph.length >= 10
        ? 'https://wa.me/$ph?text=${Uri.encodeComponent(msg)}'
        : 'https://wa.me/?text=${Uri.encodeComponent(msg)}';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Image.asset('assets/images/logo.png', height: 34, fit: BoxFit.contain),
              ),
              const SizedBox(height: 4),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: tx.isVoid ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    tx.isVoid ? 'DIBATALKAN (VOID)' : 'LUNAS • ${tx.paymentMethod}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: tx.isVoid ? NfColors.danger : const Color(0xFF166534),
                    ),
                  ),
                ),
              ),
              const Divider(height: 18),
              _kv('No. Nota', tx.id),
              _kv('Waktu', NfFormatters.dateTimeShort(tx.date)),
              _kv('Pelanggan', tx.customerName),
              _kv('Kasir', tx.cashier),
              const Divider(height: 18),
              ...tx.items.map((it) {
                final qty = (it['qty'] as num?) ?? 0;
                final unit = (it['unit'] ?? 'Gram').toString();
                final sub = (it['subtotal'] as num?) ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${it['name']} (${NfFormatters.stockDisplay(qty, unit)})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(NfFormatters.rupiah(sub), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                    ],
                  ),
                );
              }),
              const Divider(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TOTAL BAYAR', style: TextStyle(fontWeight: FontWeight.w900)),
                  Text(
                    NfFormatters.rupiah(tx.total),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: NfColors.brown),
                  ),
                ],
              ),
              if (tx.paymentMethod == 'Tunai')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _kv('Tunai / Kembali', '${NfFormatters.rupiah(tx.cash)} / ${NfFormatters.rupiah(tx.change)}'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => PosPrintService.instance.printReceipt(tx, settings),
                icon: const Icon(Icons.print_rounded, size: 17),
                label: const Text('Cetak Struk', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () async {
                  final path = await PosPrintService.instance.exportReceiptPng(tx, settings);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Resi PNG tersimpan: $path')),
                    );
                  }
                },
                icon: const Icon(Icons.image_rounded, size: 17),
                label: const Text('Simpan PNG', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _sendWa,
                icon: const Icon(Icons.chat_rounded, size: 16, color: Color(0xFF16A34A)),
                label: const Text('Kirim Resi WA', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _receiptUrl));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link Resi Digital disalin!')),
                  );
                },
                icon: const Icon(Icons.link_rounded, size: 16),
                label: const Text('Salin Link', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          Text(v, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
