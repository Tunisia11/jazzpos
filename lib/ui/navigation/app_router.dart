import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/constants/permissions.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
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
import '../widgets/manager_override_dialog.dart';

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
  bool _isDrawerOpen = true;
  final Set<AppNavDestination> _temporaryOverrides = {};

  String? _permissionForDest(AppNavDestination dest) {
    switch (dest) {
      case AppNavDestination.inventory:
        return AppPermissions.manageInventory;
      case AppNavDestination.purchasing:
        return AppPermissions.manageSuppliers;
      case AppNavDestination.reports:
        return AppPermissions.viewReports;
      case AppNavDestination.settings:
        return AppPermissions.manageSettings;
      default:
        return null;
    }
  }

  bool _isDestinationAllowed(AppNavDestination dest, AuthState authState) {
    final requiredPerm = _permissionForDest(dest);
    if (requiredPerm == null) return true;
    if (_temporaryOverrides.contains(dest)) return true;
    return authState.hasPermission(requiredPerm);
  }

  String _formatRole(String? role, BuildContext context) {
    if (role == null) return context.loc.roleCashier;
    switch (role.toUpperCase()) {
      case 'OWNER':
        return context.loc.roleOwner;
      case 'MANAGER':
        return context.loc.roleManager;
      case 'INVENTORY':
        return context.loc.roleInventory;
      case 'CASHIER':
      default:
        return context.loc.roleCashier;
    }
  }

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

    final isRtl = context.isRtl;

    // 3. Authenticated and active -> Show Shell with Directional Navigation Rail
    return Scaffold(
      backgroundColor: AppDesignTokens.background,
      body: Row(
        children: [
          // Collapsible Directional Navigation Rail
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _isDrawerOpen ? 240 : 72,
            decoration: const BoxDecoration(
              color: AppDesignTokens.surface,
              border: BorderDirectional(
                end: BorderSide(color: AppDesignTokens.border, width: 1),
              ),
            ),
            child: Column(
              children: [
                // Top Brand & Toggle
                Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: AlignmentDirectional.centerStart,
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _isDrawerOpen
                              ? (isRtl ? Icons.menu : Icons.menu_open)
                              : Icons.menu,
                          color: AppDesignTokens.textSecondary,
                        ),
                        onPressed: () =>
                            setState(() => _isDrawerOpen = !_isDrawerOpen),
                        tooltip: _isDrawerOpen
                            ? context.loc.collapseMenu
                            : context.loc.expandMenu,
                      ),
                      if (_isDrawerOpen) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppDesignTokens.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.storefront,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.loc.appTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppDesignTokens.textPrimary,
                              letterSpacing: 0.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const Divider(color: AppDesignTokens.border, height: 1),

                // Navigation Items
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      _buildNavItem(
                        AppNavDestination.checkout,
                        Icons.point_of_sale,
                        context.loc.navPos,
                        authState,
                      ),
                      _buildNavItem(
                        AppNavDestination.catalog,
                        Icons.checkroom,
                        context.loc.navCatalog,
                        authState,
                      ),
                      _buildNavItem(
                        AppNavDestination.inventory,
                        Icons.inventory_2,
                        context.loc.navInventory,
                        authState,
                      ),
                      _buildNavItem(
                        AppNavDestination.purchasing,
                        Icons.local_shipping,
                        context.loc.navPurchasing,
                        authState,
                      ),
                      _buildNavItem(
                        AppNavDestination.returns,
                        Icons.swap_horiz,
                        context.loc.navReturns,
                        authState,
                      ),
                      _buildNavItem(
                        AppNavDestination.labels,
                        Icons.qr_code,
                        context.loc.navLabels,
                        authState,
                      ),
                      _buildNavItem(
                        AppNavDestination.shifts,
                        Icons.account_balance_wallet,
                        context.loc.navShifts,
                        authState,
                      ),
                      _buildNavItem(
                        AppNavDestination.reports,
                        Icons.analytics,
                        context.loc.navReports,
                        authState,
                      ),
                      _buildNavItem(
                        AppNavDestination.settings,
                        Icons.settings,
                        context.loc.navSettings,
                        authState,
                      ),
                    ],
                  ),
                ),

                const Divider(color: AppDesignTokens.border, height: 1),

                // Cashier info & Lock/Logout controls
                Container(
                  padding: const EdgeInsets.all(AppDesignTokens.space12),
                  child: Column(
                    children: [
                      if (_isDrawerOpen)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(AppDesignTokens.space8),
                          decoration: BoxDecoration(
                            color: AppDesignTokens.surfaceSecondary,
                            borderRadius: BorderRadius.circular(
                              AppDesignTokens.radiusMd,
                            ),
                            border: Border.all(color: AppDesignTokens.border),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 15,
                                backgroundColor: const Color(0xFFDBEAFE),
                                child: Text(
                                  authState.user?.displayName.isNotEmpty == true
                                      ? authState.user!.displayName
                                            .substring(0, 1)
                                            .toUpperCase()
                                      : 'U',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppDesignTokens.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      authState.user?.displayName ?? '',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppDesignTokens.textPrimary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      _formatRole(
                                        authState.user?.role,
                                        context,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppDesignTokens.textSecondary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.lock_outline,
                              size: 19,
                              color: AppDesignTokens.textSecondary,
                            ),
                            onPressed: () =>
                                ref.read(authNotifierProvider.notifier).lock(),
                            tooltip: context.loc.lockRegister,
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.logout,
                              size: 19,
                              color: AppDesignTokens.danger,
                            ),
                            onPressed: () => ref
                                .read(authNotifierProvider.notifier)
                                .logout(),
                            tooltip: context.loc.logoutSession,
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
          Expanded(child: _buildCurrentScreen(authState)),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    AppNavDestination dest,
    IconData icon,
    String label,
    AuthState authState,
  ) {
    final isSelected = _currentNav == dest;
    final isAllowed = _isDestinationAllowed(dest, authState);
    final requiredPerm = _permissionForDest(dest);

    Widget navContent = Container(
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFEFF6FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusMd),
        border: BorderDirectional(
          start: isSelected
              ? const BorderSide(color: AppDesignTokens.primary, width: 3)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: isSelected
                ? AppDesignTokens.primary
                : (!isAllowed
                      ? AppDesignTokens.textMuted
                      : AppDesignTokens.textSecondary),
            size: 20,
          ),
          if (_isDrawerOpen) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? AppDesignTokens.primary
                      : (!isAllowed
                            ? AppDesignTokens.textMuted
                            : AppDesignTokens.textPrimary),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!isAllowed)
              const Icon(
                Icons.lock_outline,
                size: 14,
                color: AppDesignTokens.textMuted,
              ),
          ],
        ],
      ),
    );

    if (!_isDrawerOpen) {
      navContent = Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 350),
        child: navContent,
      );
    }

    return InkWell(
      onTap: () async {
        if (isAllowed) {
          setState(() => _currentNav = dest);
        } else {
          final mgr = await ManagerOverrideDialog.show(
            context,
            actionTitle: '${context.loc.managerOverrideTitle} : $label',
            reason: context.loc.managerOverrideReason,
            requiredPermission: requiredPerm ?? '',
          );
          if (mgr != null && mounted) {
            setState(() {
              _temporaryOverrides.add(dest);
              _currentNav = dest;
            });
          }
        }
      },
      borderRadius: BorderRadius.circular(AppDesignTokens.radiusMd),
      child: navContent,
    );
  }

  Widget _buildCurrentScreen(AuthState authState) {
    if (!_isDestinationAllowed(_currentNav, authState)) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(AppDesignTokens.space32),
          decoration: BoxDecoration(
            color: AppDesignTokens.surface,
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusLg),
            border: Border.all(color: AppDesignTokens.border),
            boxShadow: AppDesignTokens.shadowMd,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.shield_outlined,
                size: 56,
                color: AppDesignTokens.warning,
              ),
              const SizedBox(height: AppDesignTokens.space16),
              Text(
                context.loc.managerOverrideTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              const SizedBox(height: AppDesignTokens.space8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Text(
                  context.loc.managerOverrideReason,
                  style: const TextStyle(
                    color: AppDesignTokens.textSecondary,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppDesignTokens.space24),
              ElevatedButton.icon(
                onPressed: () async {
                  final mgr = await ManagerOverrideDialog.show(
                    context,
                    actionTitle: context.loc.managerOverrideTitle,
                    reason: context.loc.managerOverrideReason,
                  );
                  if (mgr != null && mounted) {
                    setState(() => _temporaryOverrides.add(_currentNav));
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppDesignTokens.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                icon: const Icon(
                  Icons.admin_panel_settings,
                  color: Colors.white,
                ),
                label: Text(
                  context.loc.authorizeAction,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

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
