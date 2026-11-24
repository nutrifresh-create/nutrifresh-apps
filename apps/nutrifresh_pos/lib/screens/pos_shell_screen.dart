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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 840;
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: NfColors.lightBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.storefront_rounded, color: NfColors.greenDark, size: 20),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('NutriFresh POS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    Text(
                      '${c.session?.name ?? '-'} • ${c.session?.role ?? '-'}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: c.activeShift.isOpen ? NfColors.lightBg : const Color(0xFFFEF2F2),
                  foregroundColor: c.activeShift.isOpen ? NfColors.greenDark : NfColors.danger,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) => c.activeShift.isOpen
                        ? CloseShiftDialog(controller: c)
                        : OpenShiftDialog(controller: c),
                  );
                },
                icon: Icon(c.activeShift.isOpen ? Icons.lock_open_rounded : Icons.lock_rounded, size: 16),
                label: Text(
                  c.activeShift.isOpen ? 'Shift BUKA' : 'Kasir TUTUP',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Sinkronkan Cloud',
                onPressed: c.isSyncing ? null : () => c.syncAllData(),
                icon: c.isSyncing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: isDesktop
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _tabIndex,
                      onDestinationSelected: (i) => setState(() => _tabIndex = i),
                      labelType: NavigationRailLabelType.all,
                      backgroundColor: Colors.white,
                      indicatorColor: NfColors.lightBg,
                      destinations: [
                        const NavigationRailDestination(
                          icon: Icon(Icons.point_of_sale_rounded),
                          label: Text('Kasir'),
                        ),
                        NavigationRailDestination(
                          icon: Badge(
                            isLabelVisible: c.pendingOnlineOrdersCount > 0,
                            label: Text('${c.pendingOnlineOrdersCount}'),
                            child: const Icon(Icons.shopping_bag_rounded),
                          ),
                          label: const Text('Order'),
                        ),
                        NavigationRailDestination(
                          icon: Badge(
                            isLabelVisible: c.pendingParcelOrdersCount > 0,
                            label: Text('${c.pendingParcelOrdersCount}'),
                            child: const Icon(Icons.card_giftcard_rounded),
                          ),
                          label: const Text('PO Parsel'),
                        ),
                        const NavigationRailDestination(
                          icon: Icon(Icons.inventory_2_rounded),
                          label: Text('Stok'),
                        ),
                        const NavigationRailDestination(
                          icon: Icon(Icons.bar_chart_rounded),
                          label: Text('Laporan'),
                        ),
                        const NavigationRailDestination(
                          icon: Icon(Icons.settings_rounded),
                          label: Text('Atur'),
                        ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: pages[_tabIndex]),
                  ],
                )
              : pages[_tabIndex],
          bottomNavigationBar: isDesktop
              ? null
              : NavigationBar(
                  selectedIndex: _tabIndex,
                  onDestinationSelected: (i) => setState(() => _tabIndex = i),
                  destinations: [
                    const NavigationDestination(icon: Icon(Icons.point_of_sale_rounded), label: 'Kasir'),
                    NavigationDestination(
                      icon: Badge(
                        isLabelVisible: c.pendingOnlineOrdersCount > 0,
                        label: Text('${c.pendingOnlineOrdersCount}'),
                        child: const Icon(Icons.shopping_bag_rounded),
                      ),
                      label: 'Order',
                    ),
                    NavigationDestination(
                      icon: Badge(
                        isLabelVisible: c.pendingParcelOrdersCount > 0,
                        label: Text('${c.pendingParcelOrdersCount}'),
                        child: const Icon(Icons.card_giftcard_rounded),
                      ),
                      label: 'PO',
                    ),
                    const NavigationDestination(icon: Icon(Icons.inventory_2_rounded), label: 'Stok'),
                    const NavigationDestination(icon: Icon(Icons.bar_chart_rounded), label: 'Laporan'),
                    const NavigationDestination(icon: Icon(Icons.settings_rounded), label: 'Atur'),
                  ],
                ),
        );
      },
    );
  }
}
