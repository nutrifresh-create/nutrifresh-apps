class NfActiveShift {
  final String status; // 'open' or 'closed'
  final String shiftId;
  final String cashierName;
  final double initialCash;
  final DateTime? openedAt;

  const NfActiveShift({
    required this.status,
    required this.shiftId,
    required this.cashierName,
    required this.initialCash,
    this.openedAt,
  });

  factory NfActiveShift.closed() => const NfActiveShift(
        status: 'closed',
        shiftId: '',
        cashierName: '',
        initialCash: 0,
      );

  factory NfActiveShift.fromMap(Map<String, dynamic> map) {
    return NfActiveShift(
      status: (map['status'] ?? 'closed').toString(),
      shiftId: (map['id'] ?? map['shiftId'] ?? '').toString(),
      cashierName: (map['cashierName'] ?? '').toString(),
      initialCash: (map['initialCash'] is num)
          ? (map['initialCash'] as num).toDouble()
          : double.tryParse(map['initialCash']?.toString() ?? '') ?? 0,
      openedAt: DateTime.tryParse((map['openedAt'] ?? '').toString()),
    );
  }

  bool get isOpen => status == 'open';

  Map<String, dynamic> toMap() => {
        'id': shiftId,
        'status': status,
        'cashierName': cashierName,
        'initialCash': initialCash,
        'openedAt': openedAt?.toIso8601String(),
      };
}
