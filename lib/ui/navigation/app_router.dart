import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import '../screens/auth/lock_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/catalog/product_list_screen.dart';
import '../screens/checkout/checkout_screen.dart';
import '../screens/inventory/inventory_screen.dart';
import '../screens/labels/label_studio_screen.dart';
import '../screens/purchasing/purchase_orders_screen.dart';
import '../screens/reports/reports_screen.dart';
import '../screens/returns/returns_exchanges_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/shifts/shift_management_screen.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';

enum AppNavDestination {
  checkout,
  catalog,
  inventory,
  purchasing,
  returns,
  labels,
  shifts,
  reports,
  settings,
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  AppNavDestination _currentNav = AppNavDestination.checkout;
  bool _isDrawerOpen = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    // 1. If not authenticated -> Login Screen
    if (!authState.isAuthenticated) {
      return LoginScreen(
        onLoginSuccess: () {
          setState(() => _currentNav = AppNavDestination.checkout);
        },
      );
    }

    // 2. If session is locked -> Lock Screen
    if (authState.isLocked) {
      return const LockScreen();
    }

    // 3. Authenticated and active -> Show Shell with Drawer / Navigation Rail
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Row(
        children: [
          // Collapsible Navigation Rail
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _isDrawerOpen ? 230 : 68,
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(right: BorderSide(color: AppTheme.border)),
            ),
            child: Column(
              children: [
                // Top Brand & Toggle
                Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(_isDrawerOpen ? Icons.menu_open : Icons.menu, color: Colors.white),
                        onPressed: () => setState(() => _isDrawerOpen = !_isDrawerOpen),
                        tooltip: _isDrawerOpen ? 'Réduire le menu' : 'Agrandir le menu',
                      ),
                      if (_isDrawerOpen) ...[
                        const SizedBox(width: 8),
                        const Text(
                          'JAZZ POS',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white, letterSpacing: 1),
                        ),
                      ],
                    ],
                  ),
                ),

                const Divider(color: AppTheme.border, height: 1),

                // Navigation Items
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      _buildNavItem(AppNavDestination.checkout, Icons.point_of_sale, 'Caisse (POS)'),
                      _buildNavItem(AppNavDestination.catalog, Icons.checkroom, 'Articles & Tailles'),
                      _buildNavItem(AppNavDestination.inventory, Icons.inventory_2, 'Stocks & Inventaire'),
                      _buildNavItem(AppNavDestination.purchasing, Icons.local_shipping, 'Achats & Réception'),
                      _buildNavItem(AppNavDestination.returns, Icons.swap_horiz, 'Retours & Échanges'),
                      _buildNavItem(AppNavDestination.labels, Icons.qr_code, 'Étiquettes Code-Barres'),
                      _buildNavItem(AppNavDestination.shifts, Icons.account_balance_wallet, 'Caisse & Z-Report'),
                      _buildNavItem(AppNavDestination.reports, Icons.analytics, 'Rapports Financiers'),
                      _buildNavItem(AppNavDestination.settings, Icons.settings, 'Paramètres & Matériel'),
                    ],
                  ),
                ),

                const Divider(color: AppTheme.border, height: 1),

                // Cashier info & Lock button at bottom
                Container(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      if (_isDrawerOpen)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: AppTheme.primary,
                                child: Text(
                                  authState.user?.displayName.substring(0, 1).toUpperCase() ?? 'U',
                                  style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  authState.user?.displayName ?? '',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.lock_outline, size: 20, color: AppTheme.textSecondary),
                            onPressed: () => ref.read(authNotifierProvider.notifier).lock(),
                            tooltip: 'Verrouiller la caisse',
                          ),
                          IconButton(
                            icon: const Icon(Icons.logout, size: 20, color: AppTheme.error),
                            onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
                            tooltip: 'Déconnexion session',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main View Content
          Expanded(
            child: _buildCurrentScreen(),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(AppNavDestination dest, IconData icon, String label) {
    final isSelected = _currentNav == dest;

    return InkWell(
      onTap: () => setState(() => _currentNav = dest),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 48,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.primary : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? AppTheme.primaryLight : AppTheme.textSecondary,
              size: 22,
            ),
            if (_isDrawerOpen) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_currentNav) {
      case AppNavDestination.checkout:
        return CheckoutScreen(
          onOpenMenu: () => setState(() => _isDrawerOpen = !_isDrawerOpen),
        );
      case AppNavDestination.catalog:
        return const ProductListScreen();
      case AppNavDestination.inventory:
        return const InventoryScreen();
      case AppNavDestination.purchasing:
        return const PurchaseOrdersScreen();
      case AppNavDestination.returns:
        return const ReturnsExchangesScreen();
      case AppNavDestination.labels:
        return const LabelStudioScreen();
      case AppNavDestination.shifts:
        return const ShiftManagementScreen();
      case AppNavDestination.reports:
        return const ReportsScreen();
      case AppNavDestination.settings:
        return const SettingsScreen();
    }
  }
}
