import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/nf_config.dart';
import '../models/nf_online_order.dart';
import '../models/nf_parcel_order.dart';
import '../models/nf_product.dart';
import '../models/nf_shift.dart';
import '../models/nf_staff.dart';
import '../models/nf_transaction.dart';

class NfSupabaseService {
  NfSupabaseService._();
  static final NfSupabaseService instance = NfSupabaseService._();

  static const String _branchPrefKey = 'nutri_active_branch_id';
  String _branchId = NfConfig.defaultBranchId;

  String get branchId => _branchId;
  SupabaseClient get client => Supabase.instance.client;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString(_branchPrefKey) ?? '').trim();
    if (saved.isNotEmpty) _branchId = saved;

    await Supabase.initialize(
      url: NfConfig.supabaseUrl,
      anonKey: NfConfig.supabaseAnonKey,
    );
  }

  Future<void> setBranchId(String id) async {
    final clean = id.trim().isEmpty ? NfConfig.defaultBranchId : id.trim();
    _branchId = clean;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_branchPrefKey, clean);
  }

  // ---------- SETTINGS & SHIFT ----------
  Future<NfStoreSettings> fetchStoreSettings() async {
    final res = await client
        .from('nf_settings')
        .select('data')
        .eq('tenant_id', NfConfig.tenantId)
        .eq('id', 'store_settings')
        .maybeSingle();
    if (res != null && res['data'] is Map) {
      return NfStoreSettings.fromMap(Map<String, dynamic>.from(res['data'] as Map));
    }
    return NfStoreSettings.defaults();
  }

  Future<void> saveStoreSettings(Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data)..remove('ownerPinHash');
    payload['id'] = 'store_settings';
    await client.from('nf_settings').upsert({
      'tenant_id': NfConfig.tenantId,
      'branch_id': _branchId,
      'id': 'store_settings',
      'data': payload,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'tenant_id,id');
  }

  Future<NfActiveShift> fetchActiveShift() async {
    final res = await client
        .from('nf_settings')
        .select('data')
        .eq('tenant_id', NfConfig.tenantId)
        .eq('id', 'active_shift_state')
        .maybeSingle();
    if (res != null && res['data'] is Map) {
      return NfActiveShift.fromMap(Map<String, dynamic>.from(res['data'] as Map));
    }
    return NfActiveShift.closed();
  }

  Future<void> saveActiveShift(NfActiveShift shift) async {
    final map = shift.toMap();
    map['id'] = 'active_shift_state';
    await client.from('nf_settings').upsert({
      'tenant_id': NfConfig.tenantId,
      'branch_id': _branchId,
      'id': 'active_shift_state',
      'data': map,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'tenant_id,id');
  }

  Future<void> saveShiftLog(Map<String, dynamic> logData) async {
    final id = (logData['id'] ?? '').toString();
    await client.from('nf_shift_logs').upsert({
      'tenant_id': NfConfig.tenantId,
      'branch_id': _branchId,
      'id': id,
      'opened_at': logData['openedAt'],
      'closed_at': logData['closedAt'],
      'cashier': logData['cashierName'],
      'expected_cash': logData['expectedCash'] ?? 0,
      'actual_cash': logData['actualCash'] ?? 0,
      'discrepancy': logData['discrepancy'] ?? 0,
      'data': logData,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'tenant_id,id');
  }

  Future<void> bridgeShiftDepositToOffice({
    required String shiftId,
    required int depositAmount,
    required String cashierName,
    String note = '-',
  }) async {
    if (depositAmount <= 0) return;
    await client.rpc('nf_bridge_shift_deposit_to_office', params: {
      'p_shift_id': shiftId,
      'p_deposit_amount': depositAmount,
      'p_cashier_name': cashierName,
      'p_note': note,
      'p_entry_date': null,
      'p_tenant_id': NfConfig.tenantId,
      'p_branch_id': _branchId,
    });
  }

  // ---------- STAFF & AUTH RPC ----------
  Future<Map<String, dynamic>> getMyStaffProfile() async {
    final res = await client.rpc('nf_get_my_staff_profile', params: {
      'p_tenant_id': NfConfig.tenantId,
    });
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'is_authenticated': false, 'is_owner': false, 'is_staff': false};
  }

  Future<List<NfEmployee>> fetchEmployees() async {
    final rows = await client
        .from('nf_employees')
        .select('*')
        .eq('tenant_id', NfConfig.tenantId)
        .order('name', ascending: true);
    return (rows as List)
        .whereType<Map>()
        .map((r) => NfEmployee.fromRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<Map<String, dynamic>> verifyEmployeePin(String empId, String pin) async {
    final res = await client.rpc('nf_verify_employee_pin', params: {
      'p_employee_id': empId,
      'p_pin': pin.trim(),
      'p_tenant_id': NfConfig.tenantId,
    });
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'ok': false, 'reason': 'Verifikasi PIN gagal.'};
  }

  Future<Map<String, dynamic>> verifyOwnerPin(String pin) async {
    final res = await client.rpc('nf_verify_owner_pin', params: {
      'p_pin': pin.trim(),
      'p_tenant_id': NfConfig.tenantId,
    });
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'ok': false};
  }

  // ---------- INVENTORY & ATOMIC STOCK RPC ----------
  Future<List<NfProduct>> fetchInventory() async {
    final rows = await client
        .from('nf_inventory')
        .select('*')
        .eq('tenant_id', NfConfig.tenantId)
        .order('name', ascending: true);
    return (rows as List)
        .whereType<Map>()
        .map((r) => NfProduct.fromRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<void> upsertProduct(NfProduct p) async {
    final data = p.toDataJson();
    await client.from('nf_inventory').upsert({
      'tenant_id': NfConfig.tenantId,
      'branch_id': _branchId,
      'id': p.id,
      'name': p.name,
      'category': p.category,
      'unit': p.unit,
      'barcode': p.barcode,
      'price': p.price,
      'cost': p.cost,
      'stock': p.stock,
      'min_stock': p.minStock,
      'active': p.active,
      'img_url': p.img,
      'data': data,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'tenant_id,id');
  }

  Future<Map<String, dynamic>?> adjustStockAtomic({
    required String productId,
    required int deltaQty,
    double? newUnitCost,
    required String reason,
    String? refId,
    required String actor,
    bool preventNegative = false,
  }) async {
    final res = await client.rpc('nf_adjust_stock_atomic', params: {
      'p_product_id': productId,
      'p_delta_qty': deltaQty,
      'p_new_unit_cost': (newUnitCost != null && newUnitCost > 0) ? newUnitCost : null,
      'p_reason': reason,
      'p_ref_id': refId,
      'p_actor': actor,
      'p_prevent_negative': preventNegative,
      'p_tenant_id': NfConfig.tenantId,
      'p_branch_id': _branchId,
    });
    return res is Map ? Map<String, dynamic>.from(res) : null;
  }

  Future<void> batchAdjustStockAtomic({
    required List<Map<String, dynamic>> items,
    required String reason,
    String? refId,
    required String actor,
    bool preventNegative = true,
  }) async {
    if (items.isEmpty) return;
    await client.rpc('nf_batch_adjust_stock_atomic', params: {
      'p_items': items,
      'p_reason': reason,
      'p_ref_id': refId,
      'p_actor': actor,
      'p_prevent_negative': preventNegative,
      'p_tenant_id': NfConfig.tenantId,
      'p_branch_id': _branchId,
    });
  }

  Future<List<Map<String, dynamic>>> fetchStockCard(String productId) async {
    final res = await client.rpc('nf_get_stock_card', params: {
      'p_product_id': productId,
      'p_limit': 100,
      'p_tenant_id': NfConfig.tenantId,
    });
    if (res is List) {
      return res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  // ---------- TRANSACTIONS, MEMBER & AUDIT ----------
  Future<List<NfTransaction>> fetchTransactions({int limit = 150}) async {
    final rows = await client
        .from('nf_transactions')
        .select('*')
        .eq('tenant_id', NfConfig.tenantId)
        .order('tx_date', ascending: false)
        .limit(limit);
    return (rows as List)
        .whereType<Map>()
        .map((r) => NfTransaction.fromRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<void> saveTransaction(Map<String, dynamic> tx) async {
    await client.from('nf_transactions').upsert({
      'tenant_id': NfConfig.tenantId,
      'branch_id': _branchId,
      'id': tx['id'],
      'tx_date': tx['date'],
      'cashier': tx['cashier'],
      'channel': tx['salesChannel'],
      'payment_method': tx['paymentMethod'],
      'customer_name': tx['customerName'],
      'customer_phone': tx['customerPhone'],
      'total': tx['total'] ?? 0,
      'profit': tx['grossProfit'] ?? 0,
      'status': tx['status'] ?? 'success',
      'data': tx,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'tenant_id,id');
  }

  Future<Map<String, dynamic>?> posGetMemberDetails(String queryText) async {
    final res = await client.rpc('nf_pos_get_member_details', params: {
      'p_query': queryText.trim(),
      'p_tenant_id': NfConfig.tenantId,
    });
    if (res is Map) return Map<String, dynamic>.from(res);
    return null;
  }

  Future<Map<String, dynamic>?> posSettleMemberTx({
    required String memberPhone,
    required String memberName,
    required String txId,
    required double txTotal,
    required int pointsRedeemed,
    required int pointsEarned,
    required String cashier,
    String voucherId = '',
  }) async {
    final res = await client.rpc('nf_pos_settle_member_tx', params: {
      'p_member_phone': memberPhone,
      'p_member_name': memberName,
      'p_tx_id': txId,
      'p_tx_total': txTotal,
      'p_points_redeemed': pointsRedeemed,
      'p_voucher_id': voucherId,
      'p_points_earned': pointsEarned,
      'p_cashier': cashier,
      'p_tenant_id': NfConfig.tenantId,
      'p_branch_id': _branchId,
    });
    return res is Map ? Map<String, dynamic>.from(res) : null;
  }

  Future<void> logAuditEvent({
    required String action,
    required String entityType,
    required String entityId,
    required String summary,
    required String actorName,
    String reason = '-',
    Map<String, dynamic> payload = const {},
  }) async {
    try {
      await client.rpc('nf_log_audit_event', params: {
        'p_action': action,
        'p_entity_type': entityType,
        'p_entity_id': entityId,
        'p_summary': summary,
        'p_reason': reason,
        'p_actor_name': actorName,
        'p_actor_role': '',
        'p_payload': payload,
        'p_tenant_id': NfConfig.tenantId,
        'p_branch_id': _branchId,
      });
    } catch (_) {}
  }

  // ---------- ONLINE ORDERS (SKEMA A) & PARCEL ORDERS ----------
  Future<List<NfOnlineOrder>> fetchOnlineOrders({int limit = 100}) async {
    final rows = await client
        .from('nf_online_orders')
        .select('*')
        .eq('tenant_id', NfConfig.tenantId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .whereType<Map>()
        .map((r) => NfOnlineOrder.fromRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<void> updateOnlineOrder(NfOnlineOrder ord, {
    required String status,
    double? finalTotal,
    double? shippingFee,
    String? linkedTxId,
    List<Map<String, dynamic>>? weighedItems,
  }) async {
    final nextData = Map<String, dynamic>.from(ord.raw);
    nextData['orderStatus'] = status;
    if (finalTotal != null) nextData['finalTotal'] = finalTotal;
    if (shippingFee != null) nextData['shippingFee'] = shippingFee;
    if (linkedTxId != null) nextData['linkedTxId'] = linkedTxId;
    if (weighedItems != null) nextData['weighedItems'] = weighedItems;
    nextData['updatedAt'] = DateTime.now().toIso8601String();

    await client.from('nf_online_orders').update({
      'order_status': status,
      'final_total': finalTotal ?? ord.finalTotal,
      if (linkedTxId != null) 'linked_tx_id': linkedTxId,
      'data': nextData,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('tenant_id', NfConfig.tenantId).eq('id', ord.id);
  }

  Future<List<NfParcelOrder>> fetchParcelOrders({int limit = 120}) async {
    final rows = await client
        .from('nf_parcel_orders')
        .select('*')
        .eq('tenant_id', NfConfig.tenantId)
        .order('delivery_date', ascending: true)
        .limit(limit);
    return (rows as List)
        .whereType<Map>()
        .map((r) => NfParcelOrder.fromRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<void> updateParcelOrderStatus(
    NfParcelOrder po, {
    String? orderStatus,
    String? paymentStatus,
    double? dpAmount,
    String? linkedTxId,
  }) async {
    final nextData = Map<String, dynamic>.from(po.raw);
    if (orderStatus != null) nextData['orderStatus'] = orderStatus;
    if (paymentStatus != null) nextData['paymentStatus'] = paymentStatus;
    if (dpAmount != null) nextData['dpAmount'] = dpAmount;
    if (linkedTxId != null) nextData['linkedTxId'] = linkedTxId;

    await client.from('nf_parcel_orders').update({
      if (orderStatus != null) 'order_status': orderStatus,
      if (paymentStatus != null) 'payment_status': paymentStatus,
      if (dpAmount != null) 'dp_amount': dpAmount,
      if (linkedTxId != null) 'linked_tx_id': linkedTxId,
      'data': nextData,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('tenant_id', NfConfig.tenantId).eq('id', po.id);
  }

  // ---------- EXPENSES, WASTE & PURCHASES ----------
  Future<void> addExpense({
    required String id,
    required String cashier,
    required String desc,
    required double amount,
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    final data = {
      'id': id,
      'date': nowIso,
      'cashier': cashier,
      'desc': desc,
      'amount': amount,
      'status': 'active',
    };
    await client.from('nf_expenses').upsert({
      'tenant_id': NfConfig.tenantId,
      'branch_id': _branchId,
      'id': id,
      'expense_date': nowIso,
      'cashier': cashier,
      'description': desc,
      'amount': amount,
      'data': data,
      'updated_at': nowIso,
    }, onConflict: 'tenant_id,id');
  }

  Future<void> addWasteLog({
    required String id,
    required NfProduct product,
    required int qty,
    required String reason,
    required String actor,
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    final loss = product.calculateLineCost(qty);
    final data = {
      'id': id,
      'date': nowIso,
      'productId': product.id,
      'productName': product.name,
      'unit': product.unit,
      'qty': qty,
      'totalLoss': loss,
      'reason': reason,
      'actor': actor,
    };
    await client.from('nf_waste_logs').upsert({
      'tenant_id': NfConfig.tenantId,
      'branch_id': _branchId,
      'id': id,
      'waste_date': nowIso,
      'product_id': product.id,
      'product_name': product.name,
      'qty': qty,
      'loss_cost': loss,
      'data': data,
      'updated_at': nowIso,
    }, onConflict: 'tenant_id,id');
  }

  Future<void> addPurchase({
    required String id,
    required NfProduct product,
    required int qty,
    required double totalCost,
    required String supplierName,
    required String paymentStatus,
    String dueDate = '',
    required String actor,
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    final data = {
      'id': id,
      'date': nowIso,
      'supplierName': supplierName,
      'productId': product.id,
      'productName': product.name,
      'unit': product.unit,
      'qty': qty,
      'totalCost': totalCost,
      'paymentStatus': paymentStatus,
      'dueDate': dueDate,
      'staff': actor,
    };
    await client.from('nf_purchases').upsert({
      'tenant_id': NfConfig.tenantId,
      'branch_id': _branchId,
      'id': id,
      'purchase_date': nowIso,
      'supplier_name': supplierName,
      'product_id': product.id,
      'total_cost': totalCost,
      'payment_status': paymentStatus,
      'due_date': dueDate.isEmpty ? null : dueDate,
      'data': data,
      'updated_at': nowIso,
    }, onConflict: 'tenant_id,id');

    if (paymentStatus == 'Tempo' && totalCost > 0) {
      try {
        await client.rpc('nf_bridge_tempo_purchase_to_office', params: {
          'p_purchase_id': id,
          'p_supplier_name': supplierName,
          'p_amount': totalCost.round(),
          'p_due_date': dueDate,
          'p_note': 'Kulakan ${product.name}',
          'p_staff_name': actor,
          'p_tenant_id': NfConfig.tenantId,
          'p_branch_id': _branchId,
        });
      } catch (_) {}
    }
  }

  // ---------- REALTIME SUBSCRIPTION (KHUSUS POS/INTERNAL) ----------
  RealtimeChannel subscribeTable({
    required String table,
    required void Function() onChange,
  }) {
    final ch = client.channel('nf-pos-$table-${DateTime.now().millisecondsSinceEpoch}');
    ch.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'tenant_id',
        value: NfConfig.tenantId,
      ),
      callback: (_) => onChange(),
    ).subscribe();
    return ch;
  }
}
