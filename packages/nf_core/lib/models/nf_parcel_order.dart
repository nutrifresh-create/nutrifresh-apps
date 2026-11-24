class NfParcelOrder {
  final String id;
  final String orderCode;
  final String customerName;
  final String customerPhone;
  final String institution;
  final String deliveryDate;
  final String deliveryTime;
  final double totalAmount;
  final double dpAmount;
  final String paymentStatus;
  final String orderStatus;
  final String linkedTxId;
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> raw;

  const NfParcelOrder({
    required this.id,
    required this.orderCode,
    required this.customerName,
    required this.customerPhone,
    required this.institution,
    required this.deliveryDate,
    required this.deliveryTime,
    required this.totalAmount,
    required this.dpAmount,
    required this.paymentStatus,
    required this.orderStatus,
    required this.linkedTxId,
    required this.items,
    required this.raw,
  });

  factory NfParcelOrder.fromRow(Map<String, dynamic> row) {
    final data = (row['data'] is Map)
        ? Map<String, dynamic>.from(row['data'] as Map)
        : Map<String, dynamic>.from(row);
    final rawItems = row['items'] ?? data['items'];
    final items = (rawItems is List)
        ? rawItems.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    return NfParcelOrder(
      id: (row['id'] ?? data['id'] ?? '').toString(),
      orderCode: (row['order_code'] ?? data['orderCode'] ?? row['id'] ?? '').toString(),
      customerName: (row['customer_name'] ?? data['customerName'] ?? 'Pelanggan').toString(),
      customerPhone: (row['customer_phone'] ?? data['customerPhone'] ?? '').toString(),
      institution: (row['institution'] ?? data['institution'] ?? '').toString(),
      deliveryDate: (row['delivery_date'] ?? data['deliveryDate'] ?? '').toString(),
      deliveryTime: (row['delivery_time'] ?? data['deliveryTime'] ?? '08:00').toString(),
      totalAmount: _n(row['total_amount'] ?? data['totalAmount']),
      dpAmount: _n(row['dp_amount'] ?? data['dpAmount']),
      paymentStatus: (row['payment_status'] ?? data['paymentStatus'] ?? 'Belum Bayar').toString(),
      orderStatus: (row['order_status'] ?? data['orderStatus'] ?? 'Menunggu Konfirmasi').toString(),
      linkedTxId: (row['linked_tx_id'] ?? data['linkedTxId'] ?? '').toString(),
      items: items,
      raw: data,
    );
  }

  double get remainingAmount =>
      (totalAmount - dpAmount).clamp(0, double.infinity);

  bool get isClosed => orderStatus == 'Selesai' || orderStatus == 'Dibatalkan';

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }
}
