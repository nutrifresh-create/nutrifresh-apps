import 'dart:math';
import 'package:intl/intl.dart';

class NfFormatters {
  static final NumberFormat _idrFmt = NumberFormat('#,##0', 'id_ID');

  static int roundToThousand(num amount) {
    final val = amount.toDouble();
    if (val <= 0) return 0;
    final rounded = (val / 1000.0).round() * 1000;
    return rounded == 0 ? 1000 : rounded;
  }

  static String rupiah(num amount) {
    final v = amount.round();
    final neg = v < 0 ? '-' : '';
    return '${neg}Rp ${_idrFmt.format(v.abs())}';
  }

  static int unitDivisor(String unit) {
    return (unit == 'Gram' || unit == 'ml') ? 1000 : 1;
  }

  static String displayUnit(String unit) {
    if (unit == 'Gram') return 'gr';
    if (unit == 'ml') return 'ml';
    return unit.isEmpty ? 'Pcs' : unit;
  }

  static String catalogPriceUnit(String unit) {
    if (unit == 'Gram') return 'Kg';
    if (unit == 'ml') return 'Liter';
    return unit.isEmpty ? 'Pcs' : unit;
  }

  static String stockDisplay(num stock, String unit) {
    final u = unit.isEmpty ? 'Gram' : unit;
    final n = stock.round();
    if (u == 'Gram') {
      if (n.abs() >= 1000) {
        final kg = n / 1000.0;
        final s = kg == kg.roundToDouble()
            ? kg.toStringAsFixed(0)
            : kg.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
        return '${s.replaceAll('.', ',')} Kg';
      }
      return '${_idrFmt.format(n)} gr';
    }
    if (u == 'ml') {
      if (n.abs() >= 1000) {
        final l = n / 1000.0;
        final s = l == l.roundToDouble()
            ? l.toStringAsFixed(0)
            : l.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
        return '${s.replaceAll('.', ',')} L';
      }
      return '${_idrFmt.format(n)} ml';
    }
    return '${_idrFmt.format(n)} $u';
  }

  static String normalizeWaPhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('0')) {
      digits = '62${digits.substring(1)}';
    } else if (digits.startsWith('8')) {
      digits = '62$digits';
    }
    return digits;
  }

  static String localWaDisplay(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('62')) return '0${digits.substring(2)}';
    return digits;
  }

  static String dateTimeShort(DateTime dt) {
    final l = dt.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    final d = l.day.toString().padLeft(2, '0');
    final m = months[l.month - 1];
    final h = l.hour.toString().padLeft(2, '0');
    final min = l.minute.toString().padLeft(2, '0');
    return '$d $m ${l.year} $h:$min';
  }

  static String ymd(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }

  static String generateId(String prefix) {
    final now = DateTime.now();
    final y = (now.year % 100).toString().padLeft(2, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    final suffix = List.generate(4, (_) => chars[rnd.nextInt(chars.length)]).join();
    return '$prefix-$y$m$d-$suffix';
  }

  static String generateReceiptToken() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
  }
}
