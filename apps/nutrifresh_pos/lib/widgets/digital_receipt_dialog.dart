import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nf_core/nf_core.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/pos_print_service.dart';

class DigitalReceiptDialog extends StatelessWidget {
  final NfTransaction tx;
  final NfStoreSettings settings;
  final bool justPaid;

  const DigitalReceiptDialog({
    super.key,
    required this.tx,
    required this.settings,
    this.justPaid = false,
  });

  String get _receiptUrl =>
      '${NfConfig.publicWebOrigin}/?resi=${Uri.encodeComponent(tx.id)}&k=${Uri.encodeComponent(tx.receiptToken)}';

  Future<void> _sendWa(BuildContext context) async {
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
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Icon(
            justPaid ? Icons.check_circle_rounded : Icons.receipt_long_rounded,
            color: NfColors.greenDark,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              justPaid ? 'Transaksi Berhasil!' : 'Resi Digital ${tx.id}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(
                      child: Text('NUTRIFRESH', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: NfColors.greenDark)),
                    ),
                    Center(
                      child: Text(
                        tx.isVoid ? 'DIBATALKAN (VOID)' : 'LUNAS • ${tx.paymentMethod}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: tx.isVoid ? NfColors.danger : NfColors.greenDark,
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
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${it['name']} (${NfFormatters.stockDisplay(qty, unit)})',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                            Text(NfFormatters.rupiah(sub), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
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
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: NfColors.brown),
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
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => PosPrintService.instance.printReceipt(tx, settings),
                    icon: const Icon(Icons.print_rounded, size: 18),
                    label: const Text('Cetak Struk'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final path = await PosPrintService.instance.exportReceiptPng(tx, settings);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Resi PNG tersimpan di: $path')),
                        );
                      }
                    },
                    icon: const Icon(Icons.image_rounded, size: 18),
                    label: const Text('Simpan PNG'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _sendWa(context),
                    icon: const Icon(Icons.chat_rounded, size: 18, color: Color(0xFF16A34A)),
                    label: const Text('Kirim Resi WA'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _receiptUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link Resi Digital disalin ke clipboard!')),
                      );
                    },
                    icon: const Icon(Icons.link_rounded, size: 18),
                    label: const Text('Salin Link'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tutup'),
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
