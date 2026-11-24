import 'nf_product.dart';

class NfCartItem {
  final NfProduct product;
  int qty;
  int originalRequestedQty;
  int? customNominal;
  String itemNote;
  String? linkedPoId;
  bool skipStockDeduction;

  NfCartItem({
    required this.product,
    required this.qty,
    this.originalRequestedQty = 0,
    this.customNominal,
    this.itemNote = '',
    this.linkedPoId,
    this.skipStockDeduction = false,
  });

  int subtotal(String buyerMode) => product.calculateLineAmount(
        qty,
        buyerMode: buyerMode,
        customNominal: customNominal,
      );

  double costTotal() => skipStockDeduction ? 0 : product.calculateLineCost(qty);

  Map<String, dynamic> toTransactionItemJson(String buyerMode) {
    return {
      'id': product.id,
      'name': product.name,
      'unit': product.unit,
      'price': product.effectivePriceForMode(buyerMode),
      'cost': product.cost,
      'qty': qty,
      'subtotal': subtotal(buyerMode),
      'itemDiscount': 0,
      'itemNote': itemNote,
      if (linkedPoId != null && linkedPoId!.isNotEmpty) 'linkedPoId': linkedPoId,
      if (skipStockDeduction) 'skipStockDeduction': true,
    };
  }
}

class NfTransaction {
  final String id;
  final String receiptToken;
  final DateTime date;
  final String cashier;
  final String salesChannel;
  final String buyerMode;
  final String customerName;
  final String customerPhone;
  final String paymentMethod;
  final String referenceNote;
  final List<Map<String, dynamic>> items;
  final double subtotalItems;
  final double totalDiscount;
  final double total;
  final double totalCost;
  final double grossProfit;
  final double cash;
  final double change;
  final int pointsRedeemed;
  final int pointsEarned;
  final int pointsAfter;
  final String status;
  final String voidReason;
  final String linkedOnlineOrderId;
  final Map<String, dynamic> raw;

  const NfTransaction({
    required this.id,
    required this.receiptToken,
    required this.date,
    required this.cashier,
    required this.salesChannel,
    required this.buyerMode,
    required this.customerName,
    required this.customerPhone,
    required this.paymentMethod,
    required this.referenceNote,
    required this.items,
    required this.subtotalItems,
    required this.totalDiscount,
    required this.total,
    required this.totalCost,
    required this.grossProfit,
    required this.cash,
    required this.change,
    required this.pointsRedeemed,
    required this.pointsEarned,
    required this.pointsAfter,
    required this.status,
    required this.voidReason,
    required this.linkedOnlineOrderId,
    required this.raw,
  });

  factory NfTransaction.fromRow(Map<String, dynamic> row) {
    final data = (row['data'] is Map)
        ? Map<String, dynamic>.from(row['data'] as Map)
        : Map<String, dynamic>.from(row);
    final rawItems = data['items'];
    final items = (rawItems is List)
        ? rawItems
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    final parsedDate = DateTime.tryParse(
          (data['date'] ?? row['tx_date'] ?? '').toString(),
        ) ??
        DateTime.now();

    return NfTransaction(
      id: (row['id'] ?? data['id'] ?? '').toString(),
      receiptToken: (data['receiptToken'] ?? '').toString(),
      date: parsedDate,
      cashier: (row['cashier'] ?? data['cashier'] ?? 'Kasir').toString(),
      salesChannel:
          (row['channel'] ?? data['salesChannel'] ?? 'Offline / Toko').toString(),
      buyerMode: (data['buyerMode'] ?? 'reguler').toString(),
      customerName:
          (row['customer_name'] ?? data['customerName'] ?? 'Pelanggan').toString(),
      customerPhone:
          (row['customer_phone'] ?? data['customerPhone'] ?? '').toString(),
      paymentMethod:
          (row['payment_method'] ?? data['paymentMethod'] ?? 'Tunai').toString(),
      referenceNote: (data['referenceNote'] ?? '-').toString(),
      items: items,
      subtotalItems: _n(data['subtotalItems'] ?? row['total']),
      totalDiscount: _n(data['totalDiscount']),
      total: _n(row['total'] ?? data['total']),
      totalCost: _n(data['totalCost']),
      grossProfit: _n(row['profit'] ?? data['grossProfit']),
      cash: _n(data['cash'] ?? row['total']),
      change: _n(data['change']),
      pointsRedeemed: _n(data['pointsRedeemed']).round(),
      pointsEarned: _n(data['pointsEarned']).round(),
      pointsAfter: _n(data['pointsAfter']).round(),
      status: (row['status'] ?? data['status'] ?? 'success').toString(),
      voidReason: (data['voidReason'] ?? '').toString(),
      linkedOnlineOrderId: (data['linkedOnlineOrderId'] ?? '').toString(),
      raw: data,
    );
  }

  bool get isVoid => status == 'cancelled';

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }
}
