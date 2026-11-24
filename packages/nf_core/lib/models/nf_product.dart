import '../utils/nf_formatters.dart';

class NfProduct {
  final String id;
  final String name;
  final String category;
  final String unit;
  final String barcode;
  final double price;
  final double cost;
  final int stock;
  final int minStock;
  final bool active;
  final String img;
  final bool isObral;
  final int bundleQty;
  final double bundlePrice;
  final double employeePrice;
  final double resellerPrice;
  final Map<String, dynamic> raw;

  const NfProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.barcode,
    required this.price,
    required this.cost,
    required this.stock,
    required this.minStock,
    required this.active,
    required this.img,
    required this.isObral,
    required this.bundleQty,
    required this.bundlePrice,
    required this.employeePrice,
    required this.resellerPrice,
    required this.raw,
  });

  factory NfProduct.fromRow(Map<String, dynamic> row) {
    final data = (row['data'] is Map)
        ? Map<String, dynamic>.from(row['data'] as Map)
        : Map<String, dynamic>.from(row);
    var unit = (data['unit'] ?? row['unit'] ?? 'Gram').toString();
    var stockNum = _toNum(row['stock'] ?? data['stock']);
    if (unit == 'Kg' || unit == 'kg') {
      unit = 'Gram';
      if (stockNum > 0 && stockNum < 500) stockNum *= 1000;
    }
    return NfProduct(
      id: (row['id'] ?? data['id'] ?? '').toString(),
      name: (data['name'] ?? row['name'] ?? '').toString(),
      category: (data['category'] ?? row['category'] ?? 'Buah Lokal').toString(),
      unit: unit,
      barcode: (data['barcode'] ?? row['barcode'] ?? '').toString(),
      price: _toNum(row['price'] ?? data['price']),
      cost: _toNum(row['cost'] ?? data['cost']),
      stock: stockNum.round(),
      minStock: _toNum(row['min_stock'] ?? data['minStock']).round(),
      active: (row['active'] ?? data['active']) != false,
      img: (row['img_url'] ?? data['img'] ?? '').toString(),
      isObral: data['isObral'] == true ||
          (data['name']?.toString().startsWith('[OBRAL]') ?? false),
      bundleQty: _toNum(data['bundleQty']).round(),
      bundlePrice: _toNum(data['bundlePrice']),
      employeePrice: _toNum(data['employeePrice']),
      resellerPrice: _toNum(data['resellerPrice']),
      raw: data,
    );
  }

  double effectivePriceForMode(String buyerMode) {
    if (buyerMode == 'karyawan' && employeePrice > 0) return employeePrice;
    if (buyerMode == 'reseller' && resellerPrice > 0) return resellerPrice;
    return price;
  }

  int calculateLineAmount(int qty, {String buyerMode = 'reguler', int? customNominal}) {
    if (customNominal != null && customNominal > 0) {
      return NfFormatters.roundToThousand(customNominal);
    }
    if (qty <= 0) return 0;
    final unitPrice = effectivePriceForMode(buyerMode);
    final div = NfFormatters.unitDivisor(unit);
    double rawAmt;
    if (buyerMode == 'reguler' && bundleQty >= 2 && bundlePrice > 0 && qty >= bundleQty) {
      final bundles = qty ~/ bundleQty;
      final rem = qty - (bundles * bundleQty);
      rawAmt = (bundles * bundlePrice) + ((rem / div) * unitPrice);
    } else {
      rawAmt = (qty / div) * unitPrice;
    }
    return NfFormatters.roundToThousand(rawAmt);
  }

  double calculateLineCost(int qty) {
    final div = NfFormatters.unitDivisor(unit);
    return (qty / div) * cost;
  }

  Map<String, dynamic> toDataJson() {
    final map = Map<String, dynamic>.from(raw);
    map['id'] = id;
    map['name'] = name;
    map['category'] = category;
    map['unit'] = unit;
    map['barcode'] = barcode;
    map['price'] = price;
    map['cost'] = cost;
    map['stock'] = stock;
    map['minStock'] = minStock;
    map['active'] = active;
    map['img'] = img;
    map['isObral'] = isObral;
    map['bundleQty'] = bundleQty;
    map['bundlePrice'] = bundlePrice;
    map['employeePrice'] = employeePrice;
    map['resellerPrice'] = resellerPrice;
    return map;
  }

  static double _toNum(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }
}
