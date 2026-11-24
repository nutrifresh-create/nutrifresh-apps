class NfStaffSession {
  final String id;
  final String name;
  final String email;
  final String role;
  final bool isOwner;

  const NfStaffSession({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isOwner,
  });
}

class NfEmployee {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String branch;
  final String status;

  const NfEmployee({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.branch,
    required this.status,
  });

  factory NfEmployee.fromRow(Map<String, dynamic> row) {
    final data = (row['data'] is Map)
        ? Map<String, dynamic>.from(row['data'] as Map)
        : Map<String, dynamic>.from(row);
    return NfEmployee(
      id: (row['id'] ?? data['id'] ?? '').toString(),
      name: (row['name'] ?? data['name'] ?? 'Karyawan').toString(),
      email: (row['email'] ?? data['email'] ?? '').toString(),
      phone: (row['phone'] ?? data['phone'] ?? '').toString(),
      role: (row['role'] ?? data['role'] ?? 'Kasir').toString(),
      branch: (row['branch'] ?? data['branch'] ?? 'Cabang 1 - Cilacap Tengah').toString(),
      status: (row['status'] ?? data['status'] ?? 'Aktif').toString(),
    );
  }

  bool get isActive => status != 'Non-Aktif';
}

class NfStoreSettings {
  final String waNumber;
  final String shopAddress;
  final String shopHours;
  final String receiptHeaderSub;
  final String receiptFooterText;
  final String thermalWidth; // '58mm' or '80mm'
  final String labelSize; // '50x35', '40x30', etc.
  final int rpPerPoint;
  final int redeemUnitPoints;
  final int redeemUnitRp;
  final Map<String, dynamic> raw;

  const NfStoreSettings({
    required this.waNumber,
    required this.shopAddress,
    required this.shopHours,
    required this.receiptHeaderSub,
    required this.receiptFooterText,
    required this.thermalWidth,
    required this.labelSize,
    required this.rpPerPoint,
    required this.redeemUnitPoints,
    required this.redeemUnitRp,
    required this.raw,
  });

  factory NfStoreSettings.defaults() => const NfStoreSettings(
        waNumber: '6289508011241',
        shopAddress:
            'Jl. Rinjani, Perumahan Pertamina, Sidanegara, Kec. Cilacap Tengah, Kab. Cilacap',
        shopHours: 'Buka Setiap Hari: 07.00 - 21.00 WIB',
        receiptHeaderSub: 'Fresh & Premium Fruits',
        receiptFooterText: 'Terima kasih telah berbelanja di NutriFresh!',
        thermalWidth: '58mm',
        labelSize: '50x35',
        rpPerPoint: 1000,
        redeemUnitPoints: 50,
        redeemUnitRp: 1000,
        raw: {},
      );

  factory NfStoreSettings.fromMap(Map<String, dynamic> map) {
    final d = NfStoreSettings.defaults();
    return NfStoreSettings(
      waNumber: (map['waNumber'] ?? d.waNumber).toString(),
      shopAddress: (map['shopAddress'] ?? d.shopAddress).toString(),
      shopHours: (map['shopHours'] ?? d.shopHours).toString(),
      receiptHeaderSub: (map['receiptHeaderSub'] ?? d.receiptHeaderSub).toString(),
      receiptFooterText:
          (map['receiptFooterText'] ?? d.receiptFooterText).toString(),
      thermalWidth: (map['thermalWidth'] ?? d.thermalWidth).toString(),
      labelSize: (map['labelSize'] ?? d.labelSize).toString(),
      rpPerPoint: int.tryParse('${map['rpPerPoint'] ?? ''}') ?? d.rpPerPoint,
      redeemUnitPoints:
          int.tryParse('${map['redeemUnitPoints'] ?? ''}') ?? d.redeemUnitPoints,
      redeemUnitRp:
          int.tryParse('${map['redeemUnitRp'] ?? ''}') ?? d.redeemUnitRp,
      raw: Map<String, dynamic>.from(map),
    );
  }
}
