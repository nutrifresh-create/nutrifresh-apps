import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nf_core/nf_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/pos_print_service.dart';

class PosController extends ChangeNotifier {
  final NfSupabaseService _sb = NfSupabaseService.instance;
  final NfAuthService _auth = NfAuthService.instance;

  bool isInitializing = true;
  bool isSyncing = false;
  NfUiStyle uiStyle = NfUiStyle.natural;

  NfStaffSession? session;
  bool isOwnerUnlocked = false;
  List<NfEmployee> employees = [];
  NfStoreSettings settings = NfStoreSettings.defaults();
  NfActiveShift activeShift = NfActiveShift.closed();

  List<NfProduct> inventory = [];
  List<NfTransaction> transactions = [];
  List<NfOnlineOrder> onlineOrders = [];
  List<NfParcelOrder> parcelOrders = [];

  // Cart State
  List<NfCartItem> cart = [];
  String buyerMode = 'reguler'; // reguler | member | karyawan | reseller
  String salesChannel = 'Offline / Toko';
  String customerName = 'Pelanggan Umum';
  String customerPhone = '';
  Map<String, dynamic>? activeMemberDetails;
  int pointsToRedeem = 0;
  double overallDiscountRp = 0;
  NfOnlineOrder? linkedOnlineOrder;
  List<Map<String, dynamic>> heldBills = [];

  final List<RealtimeChannel> _channels = [];
  StreamSubscription<AuthState>? _authSub;
  int _lastPendingOrdersCount = 0;

  bool get isLoggedIn => session != null;
  int get pendingOnlineOrdersCount =>
      onlineOrders.where((o) => !o.isClosed).length;
  int get pendingParcelOrdersCount =>
      parcelOrders.where((p) => !p.isClosed).length;

  int get cartSubtotal =>
      cart.fold<int>(0, (s, it) => s + it.subtotal(buyerMode));

  int get pointsDiscountRp {
    if (pointsToRedeem <= 0) return 0;
    final unitPts = settings.redeemUnitPoints < 1 ? 50 : settings.redeemUnitPoints;
    final unitRp = settings.redeemUnitRp < 100 ? 1000 : settings.redeemUnitRp;
    return (pointsToRedeem ~/ unitPts) * unitRp;
  }

  int get cartGrandTotal {
    final raw = cartSubtotal - overallDiscountRp.round() - pointsDiscountRp;
    return raw < 0 ? 0 : raw;
  }

  Future<void> bootstrap() async {
    isInitializing = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString('nutri_ui_theme') ?? 'natural';
      uiStyle = savedTheme == 'glass' ? NfUiStyle.glass : NfUiStyle.natural;
      await PosPrintService.instance.loadSavedPrinter();

      _authSub = _sb.client.auth.onAuthStateChange.listen((data) async {
        if (data.session?.user != null) {
          await _resolveStaffSession();
        } else {
          _teardownRealtime();
          session = null;
          isOwnerUnlocked = false;
          notifyListeners();
        }
      });

      if (_auth.currentUser != null) {
        await _resolveStaffSession();
      }
    } finally {
      isInitializing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _teardownRealtime();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> setUiStyle(NfUiStyle next) async {
    uiStyle = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nutri_ui_theme', next == NfUiStyle.glass ? 'glass' : 'natural');
    notifyListeners();
  }

  Future<String?> _resolveStaffSession() async {
    final u = _auth.currentUser;
    if (u == null) return 'Belum masuk.';
    try {
      final prof = await _sb.getMyStaffProfile();
      final isOwner = prof['is_owner'] == true;
      final isStaff = prof['is_staff'] == true;
      final status = (prof['status'] ?? 'Aktif').toString();

      if (!isOwner && (!isStaff || status == 'Non-Aktif')) {
        await _auth.signOut();
        session = null;
        notifyListeners();
        return 'Akun ${u.email ?? ''} tidak terdaftar sebagai Owner atau Karyawan aktif.';
      }

      session = NfStaffSession(
        id: isOwner ? 'OWNER' : (prof['employee_id'] ?? u.id).toString(),
        name: (prof['name'] ?? u.userMetadata?['full_name'] ?? u.email ?? 'Staf').toString(),
        email: (u.email ?? '').toLowerCase(),
        role: isOwner ? 'Owner NutriFresh' : (prof['role'] ?? 'Kasir').toString(),
        isOwner: isOwner,
      );
      isOwnerUnlocked = isOwner;

      await syncAllData();
      _setupRealtime();
      notifyListeners();
      return null;
    } catch (e) {
      return 'Gagal verifikasi akun: $e';
    }
  }

  Future<String?> signInGoogle() async {
    try {
      await _auth.signInWithGoogle();
      return await _resolveStaffSession();
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> signInEmail(String email, String password) async {
    try {
      await _auth.signInWithEmailPassword(email, password);
      return await _resolveStaffSession();
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> switchCashierByPin(NfEmployee emp, String pin) async {
    try {
      final res = await _sb.verifyEmployeePin(emp.id, pin);
      if (res['ok'] != true) {
        return (res['reason'] ?? 'PIN salah.').toString();
      }
      session = NfStaffSession(
        id: emp.id,
        name: emp.name,
        email: emp.email,
        role: emp.role,
        isOwner: false,
      );
      isOwnerUnlocked = false;
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> unlockOwnerWithPin(String pin) async {
    try {
      final res = await _sb.verifyOwnerPin(pin);
      if (res['ok'] != true) return 'PIN Owner salah.';
      isOwnerUnlocked = true;
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> signOut() async {
    _teardownRealtime();
    clearCart();
    session = null;
    isOwnerUnlocked = false;
    await _auth.signOut();
    notifyListeners();
  }

  Future<void> syncAllData() async {
    if (isSyncing) return;
    isSyncing = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        _sb.fetchStoreSettings(),
        _sb.fetchActiveShift(),
        _sb.fetchInventory(),
        _sb.fetchTransactions(limit: 150),
        _sb.fetchOnlineOrders(limit: 100),
        _sb.fetchParcelOrders(limit: 120),
        _sb.fetchEmployees(),
      ]);
      settings = results[0] as NfStoreSettings;
      activeShift = results[1] as NfActiveShift;
      inventory = results[2] as List<NfProduct>;
      transactions = results[3] as List<NfTransaction>;
      onlineOrders = results[4] as List<NfOnlineOrder>;
      parcelOrders = results[5] as List<NfParcelOrder>;
      employees = results[6] as List<NfEmployee>;
      _lastPendingOrdersCount = pendingOnlineOrdersCount;
    } finally {
      isSyncing = false;
      notifyListeners();
    }
  }

  void _setupRealtime() {
    _teardownRealtime();
    _channels.add(_sb.subscribeTable(
      table: 'nf_inventory',
      onChange: () async {
        inventory = await _sb.fetchInventory();
        notifyListeners();
      },
    ));
    _channels.add(_sb.subscribeTable(
      table: 'nf_online_orders',
      onChange: () async {
        onlineOrders = await _sb.fetchOnlineOrders(limit: 100);
        final nextPending = pendingOnlineOrdersCount;
        if (nextPending > _lastPendingOrdersCount) {
          SystemSound.play(SystemSoundType.alert);
        }
        _lastPendingOrdersCount = nextPending;
        notifyListeners();
      },
    ));
    _channels.add(_sb.subscribeTable(
      table: 'nf_parcel_orders',
      onChange: () async {
        parcelOrders = await _sb.fetchParcelOrders(limit: 120);
        notifyListeners();
      },
    ));
    _channels.add(_sb.subscribeTable(
      table: 'nf_transactions',
      onChange: () async {
        transactions = await _sb.fetchTransactions(limit: 150);
        notifyListeners();
      },
    ));
    _channels.add(_sb.subscribeTable(
      table: 'nf_settings',
      onChange: () async {
        activeShift = await _sb.fetchActiveShift();
        settings = await _sb.fetchStoreSettings();
        notifyListeners();
      },
    ));
  }

  void _teardownRealtime() {
    for (final ch in _channels) {
      _sb.client.removeChannel(ch);
    }
    _channels.clear();
  }

  // ---------- SHIFT ----------
  Future<void> openShift(double initialCash) async {
    final shift = NfActiveShift(
      status: 'open',
      shiftId: NfFormatters.generateId('SHF'),
      cashierName: session?.name ?? 'Kasir',
      initialCash: initialCash,
      openedAt: DateTime.now(),
    );
    await _sb.saveActiveShift(shift);
    activeShift = shift;
    notifyListeners();
  }

  Future<Map<String, dynamic>> closeShift({
    required double actualCash,
    required String note,
    bool bridgeDeposit = true,
  }) async {
    final opened = activeShift.openedAt ?? DateTime.now().subtract(const Duration(hours: 8));
    final cashSales = transactions
        .where((t) => !t.isVoid && t.paymentMethod == 'Tunai' && t.date.isAfter(opened))
        .fold<double>(0, (s, t) => s + t.total);
    final expectedCash = activeShift.initialCash + cashSales;
    final discrepancy = actualCash - expectedCash;
    final status = discrepancy == 0 ? 'PAS' : (discrepancy > 0 ? 'LEBIH' : 'KURANG');
    final shiftId = activeShift.shiftId.isEmpty
        ? NfFormatters.generateId('SHF')
        : activeShift.shiftId;

    final rec = {
      'id': shiftId,
      'cashierName': activeShift.cashierName.isEmpty
          ? (session?.name ?? 'Kasir')
          : activeShift.cashierName,
      'openedAt': opened.toIso8601String(),
      'closedAt': DateTime.now().toIso8601String(),
      'initialCash': activeShift.initialCash,
      'cashSales': cashSales,
      'cashExpenses': 0,
      'expectedCash': expectedCash,
      'actualCash': actualCash,
      'discrepancy': discrepancy,
      'status': status,
      'note': note.isEmpty ? '-' : note,
    };

    await _sb.saveShiftLog(rec);
    if (bridgeDeposit && actualCash > activeShift.initialCash) {
      final deposit = (actualCash - activeShift.initialCash).round();
      try {
        await _sb.bridgeShiftDepositToOffice(
          shiftId: shiftId,
          depositAmount: deposit,
          cashierName: rec['cashierName'].toString(),
          note: note,
        );
      } catch (_) {}
    }
    await _sb.saveActiveShift(NfActiveShift.closed());
    activeShift = NfActiveShift.closed();
    notifyListeners();
    return rec;
  }

  // ---------- CART OPERATIONS ----------
  void addOrUpdateCartItem(
    NfProduct product,
    int qty, {
    int? customNominal,
    String note = '',
  }) {
    if (qty <= 0) {
      cart.removeWhere((c) => c.product.id == product.id && c.linkedPoId == null);
    } else {
      final idx = cart.indexWhere((c) => c.product.id == product.id && c.linkedPoId == null);
      if (idx >= 0) {
        cart[idx].qty = qty;
        cart[idx].customNominal = customNominal;
        cart[idx].itemNote = note;
      } else {
        cart.add(NfCartItem(
          product: product,
          qty: qty,
          customNominal: customNominal,
          itemNote: note,
        ));
      }
    }
    notifyListeners();
  }

  void removeCartItemAt(int index) {
    if (index >= 0 && index < cart.length) {
      cart.removeAt(index);
      notifyListeners();
    }
  }

  void clearCart() {
    cart.clear();
    buyerMode = 'reguler';
    salesChannel = 'Offline / Toko';
    customerName = 'Pelanggan Umum';
    customerPhone = '';
    activeMemberDetails = null;
    pointsToRedeem = 0;
    overallDiscountRp = 0;
    linkedOnlineOrder = null;
    notifyListeners();
  }

  void setBuyerMode(String mode) {
    buyerMode = mode;
    if (mode != 'member') {
      activeMemberDetails = null;
      pointsToRedeem = 0;
    }
    notifyListeners();
  }

  Future<bool> lookupMember(String query) async {
    final res = await _sb.posGetMemberDetails(query);
    if (res != null && res['member'] is Map) {
      final m = Map<String, dynamic>.from(res['member'] as Map);
      activeMemberDetails = m;
      buyerMode = 'member';
      customerName = (m['name'] ?? 'Member').toString();
      customerPhone = (m['phone'] ?? '').toString();
      pointsToRedeem = 0;
      notifyListeners();
      return true;
    }
    return false;
  }

  void holdCurrentBill() {
    if (cart.isEmpty) return;
    heldBills.insert(0, {
      'savedAt': DateTime.now(),
      'customerName': customerName,
      'buyerMode': buyerMode,
      'items': List<NfCartItem>.from(cart),
      'total': cartGrandTotal,
    });
    clearCart();
  }

  void restoreHeldBill(int index) {
    if (index < 0 || index >= heldBills.length) return;
    final b = heldBills.removeAt(index);
    cart = List<NfCartItem>.from(b['items'] as List<NfCartItem>);
    customerName = (b['customerName'] ?? 'Pelanggan').toString();
    buyerMode = (b['buyerMode'] ?? 'reguler').toString();
    notifyListeners();
  }

  // ---------- ONLINE ORDER (SKEMA A) -> KASIR ----------
  List<String> loadOnlineOrderToCart(NfOnlineOrder ord) {
    cart.clear();
    final missing = <String>[];
    final sourceItems = ord.weighedItems.isNotEmpty ? ord.weighedItems : ord.items;

    for (final it in sourceItems) {
      final pid = (it['id'] ?? '').toString();
      final pname = (it['name'] ?? '').toString();
      NfProduct? found;
      for (final p in inventory) {
        if (p.id == pid || p.name.toLowerCase() == pname.toLowerCase()) {
          found = p;
          break;
        }
      }
      if (found == null || found.stock <= 0) {
        missing.add(pname.isEmpty ? 'Produk' : pname);
        continue;
      }
      final reqQty = ((it['requestedQty'] ?? it['qty'] ?? 1) as num).round();
      final clampedQty = reqQty.clamp(1, found.stock);
      final noteParts = [
        if (found.unit == 'Gram' && (it['weightPref'] ?? '').toString().isNotEmpty)
          it['weightPref'].toString(),
        if ((it['itemNote'] ?? '').toString().isNotEmpty) it['itemNote'].toString(),
      ];
      cart.add(NfCartItem(
        product: found,
        qty: clampedQty,
        originalRequestedQty: reqQty,
        itemNote: noteParts.join(' • '),
      ));
    }

    linkedOnlineOrder = ord;
    customerName = ord.customerName;
    customerPhone = ord.customerPhone;
    salesChannel = 'Online App';
    notifyListeners();
    return missing;
  }

  /// SKEMA A: Kasir kirim tagihan hasil timbang riil ke Aplikasi Pelanggan (tanpa wajib pindah WA)
  Future<void> sendSkemaABillToCustomer({double shippingFee = 0}) async {
    final ord = linkedOnlineOrder;
    if (ord == null || cart.isEmpty) return;
    final weighed = cart.map((c) => c.toTransactionItemJson(buyerMode)).toList();
    final finalTotal = cartGrandTotal + shippingFee.round();

    await _sb.updateOnlineOrder(
      ord,
      status: 'Menunggu Pembayaran',
      finalTotal: finalTotal.toDouble(),
      shippingFee: shippingFee,
      weighedItems: weighed,
    );
    onlineOrders = await _sb.fetchOnlineOrders(limit: 100);
    notifyListeners();
  }

  // ---------- PO PARSEL -> KASIR ----------
  void loadParcelOrderToCart(NfParcelOrder po) {
    final due = po.remainingAmount > 0 ? po.remainingAmount : po.totalAmount;
    final dummyProduct = NfProduct(
      id: 'PO-${po.id}',
      name: 'PO Parsel ${po.orderCode} (${po.customerName})',
      category: 'Parsel & Gift',
      unit: 'Paket',
      barcode: po.orderCode,
      price: due,
      cost: 0,
      stock: 99,
      minStock: 0,
      active: true,
      img: '',
      isObral: false,
      bundleQty: 0,
      bundlePrice: 0,
      employeePrice: 0,
      resellerPrice: 0,
      raw: const {},
    );
    cart.add(NfCartItem(
      product: dummyProduct,
      qty: 1,
      linkedPoId: po.id,
      skipStockDeduction: true,
      itemNote: po.dpAmount > 0
          ? 'Pelunasan PO (DP ${NfFormatters.rupiah(po.dpAmount)})'
          : 'Pembayaran PO Parsel',
    ));
    customerName = po.customerName;
    customerPhone = po.customerPhone;
    salesChannel = 'PO Parsel';
    notifyListeners();
  }

  // ---------- CHECKOUT & ATOMIC SETTLEMENT ----------
  Future<NfTransaction> processPayment({
    required String paymentMethod,
    required double cashReceived,
    String referenceNote = '-',
  }) async {
    if (cart.isEmpty) throw Exception('Keranjang masih kosong.');
    final now = DateTime.now();
    final trxId = NfFormatters.generateId('TRX');
    final receiptToken = NfFormatters.generateReceiptToken();
    final actor = session?.name ?? 'Kasir';

    // 1. Potong stok atomik di PostgreSQL (lewati item PO Parsel yang skipStockDeduction)
    final stockBatch = cart
        .where((c) => !c.skipStockDeduction)
        .map((c) => {
              'product_id': c.product.id,
              'delta_qty': -c.qty,
              'reason': 'Penjualan $trxId',
            })
        .toList();
    if (stockBatch.isNotEmpty) {
      await _sb.batchAdjustStockAtomic(
        items: stockBatch,
        reason: 'Transaksi Kasir $trxId',
        refId: trxId,
        actor: actor,
        preventNegative: true,
      );
    }

    // 2. Hitung poin Member
    final total = cartGrandTotal.toDouble();
    final subtotal = cartSubtotal.toDouble();
    final totalCost = cart.fold<double>(0, (s, c) => s + c.costTotal());
    final earnedPts = (buyerMode == 'member' && activeMemberDetails != null && settings.rpPerPoint > 0)
        ? (total ~/ settings.rpPerPoint)
        : 0;
    final ptsBefore = (activeMemberDetails?['points'] is num)
        ? (activeMemberDetails!['points'] as num).round()
        : 0;
    final ptsAfter = (ptsBefore - pointsToRedeem + earnedPts).clamp(0, 9999999);

    final processedItems = cart.map((c) => c.toTransactionItemJson(buyerMode)).toList();
    final change = paymentMethod == 'Tunai'
        ? (cashReceived - total).clamp(0, double.infinity)
        : 0.0;

    final txMap = <String, dynamic>{
      'id': trxId,
      'receiptToken': receiptToken,
      'linkedOnlineOrderId': linkedOnlineOrder?.id ?? '',
      'date': now.toIso8601String(),
      'cashier': actor,
      'salesChannel': salesChannel,
      'platformFee': 0,
      'buyerMode': buyerMode,
      'customerName': customerName.trim().isEmpty ? 'Pelanggan Umum' : customerName.trim(),
      'customerPhone': customerPhone,
      'paymentMethod': paymentMethod,
      'referenceNote': referenceNote.trim().isEmpty ? '-' : referenceNote.trim(),
      'items': processedItems,
      'subtotalItems': subtotal,
      'pointsRedeemed': pointsToRedeem,
      'pointsRedeemDiscount': pointsDiscountRp,
      'pointsEarned': earnedPts,
      'pointsBefore': ptsBefore,
      'pointsAfter': ptsAfter,
      'totalDiscount': overallDiscountRp + pointsDiscountRp,
      'total': total,
      'totalCost': totalCost,
      'grossProfit': total - totalCost,
      'cash': paymentMethod == 'Tunai' ? cashReceived : total,
      'change': change,
      'status': 'success',
      'returns': [],
    };

    await _sb.saveTransaction(txMap);

    // 3. Selesaikan poin Member secara atomik
    if (buyerMode == 'member' && customerPhone.isNotEmpty) {
      try {
        await _sb.posSettleMemberTx(
          memberPhone: customerPhone,
          memberName: customerName,
          txId: trxId,
          txTotal: total,
          pointsRedeemed: pointsToRedeem,
          pointsEarned: earnedPts,
          cashier: actor,
        );
      } catch (_) {}
    }

    // 4. Tandai Order Online / PO Parsel tertaut sebagai Selesai
    if (linkedOnlineOrder != null) {
      await _sb.updateOnlineOrder(
        linkedOnlineOrder!,
        status: 'Selesai',
        finalTotal: total,
        linkedTxId: trxId,
        weighedItems: processedItems,
      );
    }
    final linkedPoIds = cart.map((c) => c.linkedPoId).whereType<String>().toSet();
    for (final poId in linkedPoIds) {
      for (final po in parcelOrders) {
        if (po.id == poId) {
          await _sb.updateParcelOrderStatus(
            po,
            orderStatus: 'Selesai',
            paymentStatus: 'Lunas',
            dpAmount: po.totalAmount,
            linkedTxId: trxId,
          );
        }
      }
    }

    final savedTx = NfTransaction.fromRow({'id': trxId, 'data': txMap});
    clearCart();
    await syncAllData();
    return savedTx;
  }

  Future<void> voidTransaction(NfTransaction tx, String reason) async {
    final actor = session?.name ?? 'Owner';
    final restoreItems = tx.items
        .where((it) => it['skipStockDeduction'] != true)
        .map((it) => {
              'product_id': it['id'].toString(),
              'delta_qty': ((it['qty'] as num?) ?? 0).round(),
              'reason': 'VOID ${tx.id}: $reason',
            })
        .toList();
    if (restoreItems.isNotEmpty) {
      await _sb.batchAdjustStockAtomic(
        items: restoreItems,
        reason: 'VOID ${tx.id}',
        refId: tx.id,
        actor: actor,
        preventNegative: false,
      );
    }
    final nextRaw = Map<String, dynamic>.from(tx.raw);
    nextRaw['status'] = 'cancelled';
    nextRaw['voidReason'] = reason;
    await _sb.saveTransaction(nextRaw);
    await _sb.logAuditEvent(
      action: 'VOID_TRANSACTION',
      entityType: 'transaction',
      entityId: tx.id,
      summary: 'Pembatalan nota ${tx.id} (${NfFormatters.rupiah(tx.total)})',
      actorName: actor,
      reason: reason,
    );
    await syncAllData();
  }
}
