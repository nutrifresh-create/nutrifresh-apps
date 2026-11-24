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

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final pages = [
      CashierScreen(
        controller: c,
        onOpenOnlineOrders: () => setState(() => _tabIndex = 1),
      ),
      OnlineOrdersScreen(
        controller: c,
        onLoadedToCashier: () => setState(() => _tabIndex = 0),
      ),
      ParcelOrdersScreen(
        controller: c,
        onLoadedToCashier: () => setState(() => _tabIndex = 0),
      ),
      StockScreen(controller: c),
      ReportsScreen(controller: c),
      SettingsScreen(controller: c),
    ];

    final dockItems = [
      const NfDockItem(icon: Icons.point_of_sale_rounded, label: 'Kasir', activeColor: NfColors.greenDark),
      NfDockItem(
        icon: Icons.shopping_bag_rounded,
        label: 'Order',
        activeColor: const Color(0xFF059669),
        badgeCount: c.pendingOnlineOrdersCount,
      ),
      NfDockItem(
        icon: Icons.card_giftcard_rounded,
        label: 'PO',
        activeColor: const Color(0xFFD97706),
        badgeCount: c.pendingParcelOrdersCount,
      ),
      const NfDockItem(icon: Icons.inventory_2_rounded, label: 'Stok', activeColor: Color(0xFF0F766E)),
      const NfDockItem(icon: Icons.bar_chart_rounded, label: 'Laporan', activeColor: Color(0xFF2563EB)),
      const NfDockItem(icon: Icons.tune_rounded, label: 'Atur', activeColor: Color(0xFF334155)),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 880;
        final safeTop = MediaQuery.of(context).padding.top;

        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: Stack(
            children: [
              // Konten utama (memberi ruang atas untuk Floating Header & bawah untuk Floating Dock)
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.only(top: safeTop + 66),
                  child: isDesktop
                      ? Row(
                          children: [
                            _buildDesktopGlassSidebar(c, dockItems),
                            Expanded(child: pages[_tabIndex]),
                          ],
                        )
                      : pages[_tabIndex],
                ),
              ),

              // Floating Capsule Top Header (ala pos.html iOS 26 Liquid Glass)
              Positioned(
                top: safeTop + 8,
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
                      InkWell(
                        onTap: () {
                          if (c.activeShift.isOpen) {
                            showCloseShiftGlassModal(context: context, controller: c);
                          } else {
                            showOpenShiftGlassModal(context: context, controller: c);
                          }
                        },
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          height: 34,
                          padding: const EdgeInsets.symmetric(horizontal: 11),
                          decoration: BoxDecoration(
                            color: c.activeShift.isOpen
                                ? const Color(0xFFDCFCE7)
                                : const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: c.activeShift.isOpen
                                  ? const Color(0xFF86EFAC)
                                  : const Color(0xFFFECACA),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                c.activeShift.isOpen
                                    ? Icons.lock_open_rounded
                                    : Icons.lock_rounded,
                                size: 13,
                                color: c.activeShift.isOpen
                                    ? const Color(0xFF166534)
                                    : NfColors.danger,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                c.activeShift.isOpen ? 'BUKA' : 'TUTUP',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  color: c.activeShift.isOpen
                                      ? const Color(0xFF166534)
                                      : NfColors.danger,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: c.isSyncing ? null : () => c.syncAllData(),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(220),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Center(
                            child: c.isSyncing
                                ? const SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.sync_rounded, size: 18, color: NfColors.greenDark),
                          ),
                        ),
                      ),
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

  Widget _buildDesktopGlassSidebar(PosController c, List<NfDockItem> items) {
    return Container(
      width: 215,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 14),
      child: NfGlassSurface(
        style: c.uiStyle,
        borderRadius: 26,
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.activeShift.isOpen ? NfColors.lightBg : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: c.activeShift.isOpen
                      ? const Color(0xFFBBF7D0)
                      : const Color(0xFFFECACA),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.activeShift.isOpen ? 'SHIFT KASIR BUKA' : 'LACI KASIR TUTUP',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: c.activeShift.isOpen ? NfColors.greenDark : NfColors.danger,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    c.activeShift.isOpen
                        ? 'Modal: ${NfFormatters.rupiah(c.activeShift.initialCash)}'
                        : 'Klik Buka Shift untuk mulai',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 5),
                itemBuilder: (_, i) {
                  final it = items[i];
                  final active = i == _tabIndex;
                  return InkWell(
                    onTap: () => setState(() => _tabIndex = i),
                    borderRadius: BorderRadius.circular(999),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: active
                            ? const LinearGradient(colors: [Color(0xFF8BC34A), Color(0xFF558B2F)])
                            : null,
                        color: active ? null : Colors.transparent,
                      ),
                      child: Row(
                        children: [
                          Icon(it.icon, size: 19, color: active ? Colors.white : it.activeColor),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              it.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                                color: active ? Colors.white : const Color(0xFF334155),
                              ),
                            ),
                          ),
                          if (it.badgeCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: active ? Colors.white : NfColors.danger,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${it.badgeCount}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: active ? NfColors.greenDark : Colors.white,
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
