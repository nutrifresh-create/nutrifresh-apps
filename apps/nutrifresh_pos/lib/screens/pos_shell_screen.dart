import 'package:flutter/material.dart';
import 'package:nf_core/nf_core.dart';
import '../state/pos_controller.dart';
import '../widgets/shift_dialog.dart';
import 'cashier_screen.dart';
import 'online_orders_screen.dart';
import 'parcel_orders_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'stock_screen.dart';

class PosShellScreen extends StatefulWidget {
  final PosController controller;
  const PosShellScreen({super.key, required this.controller});

  @override
  State<PosShellScreen> createState() => _PosShellScreenState();
}

class _PosShellScreenState extends State<PosShellScreen> {
  int _tabIndex = 0;

  String _cleanRoleLine(NfStaffSession? s) {
    if (s == null) return 'Portal Kasir';
    final name = s.name.trim();
    final role = s.role.trim();
    if (name.isEmpty) return role.isEmpty ? 'Staf POS' : role;
    if (role.isEmpty || name.toLowerCase() == role.toLowerCase()) {
      return name;
    }
    return '$name • $role';
  }

  Future<void> _quickAddExpense() async {
    final descCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    final ok = await showNfGlassModal<bool>(
      context: context,
      style: widget.controller.uiStyle,
      title: 'Catat Kas Keluar Laci',
      subtitle: 'Pengeluaran operasional cepat dari kasir',
      icon: Icons.money_off_rounded,
      headerGradient: const [Color(0xFFB45309), Color(0xFFF59E0B)],
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: descCtrl, autofocus: true, decoration: const InputDecoration(labelText: 'Keperluan (misal: Es Batu / Plastik) *')),
          const SizedBox(height: 10),
          TextField(controller: amtCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nominal (Rp) *')),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal'))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Simpan Kas Keluar'))),
            ],
          ),
        ],
      ),
    );
    if (ok == true) {
      final amt = double.tryParse(amtCtrl.text.trim()) ?? 0;
      if (amt > 0 && descCtrl.text.trim().isNotEmpty) {
        await NfSupabaseService.instance.addExpense(
          id: NfFormatters.generateId('EXP'),
          cashier: widget.controller.session?.name ?? 'Kasir',
          desc: descCtrl.text.trim(),
          amount: amt,
        );
        await widget.controller.syncAllData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kas keluar tercatat di server.')),
          );
        }
      }
    }
    descCtrl.dispose();
    amtCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final pages = [
      CashierScreen(
        key: const ValueKey('tab_kasir'),
        controller: c,
        onOpenOnlineOrders: () => setState(() => _tabIndex = 1),
      ),
      OnlineOrdersScreen(
        key: const ValueKey('tab_order'),
        controller: c,
        onLoadedToCashier: () => setState(() => _tabIndex = 0),
      ),
      ParcelOrdersScreen(
        key: const ValueKey('tab_po'),
        controller: c,
        onLoadedToCashier: () => setState(() => _tabIndex = 0),
      ),
      StockScreen(
        key: const ValueKey('tab_stok'),
        controller: c,
      ),
      ReportsScreen(
        key: const ValueKey('tab_laporan'),
        controller: c,
      ),
      SettingsScreen(
        key: const ValueKey('tab_atur'),
        controller: c,
      ),
    ];

    final dockItems = [
      const NfDockItem(
        icon: Icons.point_of_sale_rounded,
        label: 'Kasir',
        activeColor: Color(0xFF15803D),
        softBg: Color(0xFFDCFCE7),
      ),
      NfDockItem(
        icon: Icons.shopping_bag_rounded,
        label: 'Order',
        activeColor: const Color(0xFF0D9488),
        softBg: const Color(0xFFCCFBF1),
        badgeCount: c.pendingOnlineOrdersCount,
      ),
      NfDockItem(
        icon: Icons.card_giftcard_rounded,
        label: 'PO',
        activeColor: const Color(0xFFD97706),
        softBg: const Color(0xFFFEF3C7),
        badgeCount: c.pendingParcelOrdersCount,
      ),
      const NfDockItem(
        icon: Icons.inventory_2_rounded,
        label: 'Stok',
        activeColor: Color(0xFF2563EB),
        softBg: Color(0xFFDBEAFE),
      ),
      const NfDockItem(
        icon: Icons.bar_chart_rounded,
        label: 'Laporan',
        activeColor: Color(0xFF7C3AED),
        softBg: Color(0xFFEDE9FE),
      ),
      const NfDockItem(
        icon: Icons.tune_rounded,
        label: 'Atur',
        activeColor: Color(0xFF334155),
        softBg: Color(0xFFE2E8F0),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        final safeTop = MediaQuery.of(context).padding.top;

        final animatedPage = AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.02),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: pages[_tabIndex],
        );

        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.only(top: safeTop + 64),
                  child: isDesktop
                      ? Row(
                          children: [
                            _buildDesktopGlassSidebar(c, dockItems),
                            Expanded(child: animatedPage),
                          ],
                        )
                      : animatedPage,
                ),
              ),

              // Floating Capsule Top Header (Berwarna & Informatif seperti pos.html!)
              Positioned(
                top: safeTop + 7,
                left: 10,
                right: 10,
                child: NfGlassSurface(
                  style: c.uiStyle,
                  borderRadius: 999,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: Row(
                    children: [
                      const NfBrandLogoPill(height: 38, compact: true),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'NutriFresh POS',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13.5,
                                    color: Color(0xFF0F172A),
                                    height: 1.1,
                                  ),
                                ),
                                if (isDesktop) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFECFCCB),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: const Color(0xFFBEF264)),
                                    ),
                                    child: Text(
                                      'Portal Toko • ${NfSupabaseService.instance.branchId}',
                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: NfColors.greenDark),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              _cleanRoleLine(c.session),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (isDesktop) ...[
                        _topActionChip(
                          icon: Icons.sync_rounded,
                          label: c.isSyncing ? 'Sinkron...' : 'Sinkron',
                          bg: const Color(0xFFEFF6FF),
                          border: const Color(0xFFBFDBFE),
                          fg: const Color(0xFF1D4ED8),
                          onTap: c.isSyncing ? null : () => c.syncAllData(),
                        ),
                        const SizedBox(width: 6),
                        _topActionChip(
                          icon: Icons.money_off_rounded,
                          label: 'Kas Keluar',
                          bg: const Color(0xFFFFFBEB),
                          border: const Color(0xFFFDE68A),
                          fg: const Color(0xFFB45309),
                          onTap: _quickAddExpense,
                        ),
                        const SizedBox(width: 6),
                      ],
                      _topActionChip(
                        icon: c.activeShift.isOpen ? Icons.lock_open_rounded : Icons.lock_rounded,
                        label: c.activeShift.isOpen ? 'BUKA' : 'TUTUP',
                        bg: c.activeShift.isOpen ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                        border: c.activeShift.isOpen ? const Color(0xFF86EFAC) : const Color(0xFFFECACA),
                        fg: c.activeShift.isOpen ? const Color(0xFF166534) : NfColors.danger,
                        onTap: () {
                          if (c.activeShift.isOpen) {
                            showCloseShiftGlassModal(context: context, controller: c);
                          } else {
                            showOpenShiftGlassModal(context: context, controller: c);
                          }
                        },
                      ),
                      if (!isDesktop) ...[
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: c.isSyncing ? null : () => c.syncAllData(),
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFBFDBFE)),
                            ),
                            child: Center(
                              child: c.isSyncing
                                  ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.sync_rounded, size: 17, color: Color(0xFF2563EB)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: isDesktop
              ? null
              : NfFloatingDock(
                  style: c.uiStyle,
                  items: dockItems,
                  selectedIndex: _tabIndex,
                  onSelected: (i) => setState(() => _tabIndex = i),
                ),
        );
      },
    );
  }

  Widget _topActionChip({
    required IconData icon,
    required String label,
    required Color bg,
    required Color border,
    required Color fg,
    VoidCallback? onTap,
  }) {
    return NfPressScale(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: fg)),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopGlassSidebar(PosController c, List<NfDockItem> items) {
    final opened = c.activeShift.openedAt ?? DateTime.now().subtract(const Duration(hours: 8));
    final cashSales = c.activeShift.isOpen
        ? c.transactions
            .where((t) => !t.isVoid && t.paymentMethod == 'Tunai' && t.date.isAfter(opened))
            .fold<double>(0, (s, t) => s + t.total)
        : 0.0;
    final drawerEst = c.activeShift.initialCash + cashSales;

    return Container(
      width: 214,
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 12),
      child: NfGlassSurface(
        style: c.uiStyle,
        borderRadius: 24,
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kartu Kas Laci Persis pos.html!
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: c.activeShift.isOpen
                      ? const [Color(0xFFF0FDF4), Color(0xFFDCFCE7)]
                      : const [Color(0xFFFEF2F2), Color(0xFFFEE2E2)],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: c.activeShift.isOpen ? const Color(0xFF86EFAC) : const Color(0xFFFECACA),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.activeShift.isOpen ? const Color(0xFF16A34A) : NfColors.danger,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        c.activeShift.isOpen ? 'KAS LACI • BUKA' : 'KASIR TUTUP',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          color: c.activeShift.isOpen ? const Color(0xFF166534) : NfColors.danger,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  NfAnimatedRupiah(
                    value: c.activeShift.isOpen ? drawerEst : 0,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _quickAddExpense,
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: const Color(0xFFFCD34D)),
                            ),
                            child: const Text('Kas Out', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF92400E))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            if (c.activeShift.isOpen) {
                              showCloseShiftGlassModal(context: context, controller: c);
                            } else {
                              showOpenShiftGlassModal(context: context, controller: c);
                            }
                          },
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: c.activeShift.isOpen ? const Color(0xFF1E293B) : NfColors.greenDark,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              c.activeShift.isOpen ? 'Tutup' : 'Buka',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 5),
                itemBuilder: (_, i) {
                  final it = items[i];
                  final active = i == _tabIndex;
                  return NfPressScale(
                    onTap: () => setState(() => _tabIndex = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: active ? it.activeColor : Colors.transparent,
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: it.activeColor.withAlpha(65),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: active ? Colors.white.withAlpha(55) : it.softBg,
                            ),
                            child: Icon(
                              it.icon,
                              size: 16,
                              color: active ? Colors.white : it.activeColor,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              it.label,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                                color: active ? Colors.white : const Color(0xFF334155),
                              ),
                            ),
                          ),
                          if (it.badgeCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2),
                              decoration: BoxDecoration(
                                color: active ? Colors.white : NfColors.danger,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${it.badgeCount}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: active ? it.activeColor : Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
