class NfOnlineOrder {
  final String id;
  final String orderCode;
  final String receiptToken;
  final String customerName;
  final String customerPhone;
  final String deliveryMode;
  final String address;
  final String paymentMethod;
  final String voucherCode;
  final String voucherTitle;
  final double estimatedTotal;
  final double finalTotal;
  final double shippingFee;
  final String orderStatus;
  final String linkedTxId;
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> weighedItems;
  final DateTime createdAt;
  final Map<String, dynamic> raw;

  const NfOnlineOrder({
    required this.id,
    required this.orderCode,
    required this.receiptToken,
    required this.customerName,
    required this.customerPhone,
    required this.deliveryMode,
    required this.address,
    required this.paymentMethod,
    required this.voucherCode,
    required this.voucherTitle,
    required this.estimatedTotal,
    required this.finalTotal,
    required this.shippingFee,
    required this.orderStatus,
    required this.linkedTxId,
    required this.items,
    required this.weighedItems,
    required this.createdAt,
    required this.raw,
  });

  factory NfOnlineOrder.fromRow(Map<String, dynamic> row) {
    final data = (row['data'] is Map)
        ? Map<String, dynamic>.from(row['data'] as Map)
        : Map<String, dynamic>.from(row);
    final rawItems = row['items'] ?? data['items'];
    final items = (rawItems is List)
        ? rawItems.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final rawWeighed = data['weighedItems'];
    final weighed = (rawWeighed is List)
        ? rawWeighed.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];

    return NfOnlineOrder(
      id: (row['id'] ?? data['id'] ?? '').toString(),
      orderCode: (row['order_code'] ?? data['orderCode'] ?? row['id'] ?? '').toString(),
      receiptToken: (row['receipt_token'] ?? data['receiptToken'] ?? '').toString(),
      customerName: (row['customer_name'] ?? data['customerName'] ?? 'Pelanggan').toString(),
      customerPhone: (row['customer_phone'] ?? data['customerPhone'] ?? '').toString(),
      deliveryMode: (row['delivery_mode'] ?? data['deliveryMode'] ?? 'Kirim ke Rumah').toString(),
      address: (row['address'] ?? data['address'] ?? '').toString(),
      paymentMethod: (row['payment_method'] ?? data['paymentMethod'] ?? 'QRIS').toString(),
      voucherCode: (row['voucher_code'] ?? data['voucherCode'] ?? '').toString(),
      voucherTitle: (row['voucher_title'] ?? data['voucherTitle'] ?? '').toString(),
      estimatedTotal: _n(row['estimated_total'] ?? data['estimatedTotal']),
      finalTotal: _n(row['final_total'] ?? data['finalTotal'] ?? row['estimated_total']),
      shippingFee: _n(data['shippingFee']),
      orderStatus: (row['order_status'] ?? data['orderStatus'] ?? 'Menunggu Timbang').toString(),
      linkedTxId: (row['linked_tx_id'] ?? data['linkedTxId'] ?? '').toString(),
      items: items,
      weighedItems: weighed,
      createdAt: DateTime.tryParse((row['created_at'] ?? data['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      raw: data,
    );
  }

  bool get isClosed => orderStatus == 'Selesai' || orderStatus == 'Dibatalkan';

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }
}
