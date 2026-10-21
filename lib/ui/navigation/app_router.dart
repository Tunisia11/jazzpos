import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/constants/permissions.dart';
import 'package:jazzpos/core/constants/roles.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import '../screens/auth/lock_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/catalog/product_list_screen.dart';
import '../screens/checkout/checkout_screen.dart';
import '../screens/inventory/inventory_screen.dart';
import '../screens/labels/label_studio_screen.dart';
import '../screens/reports/reports_screen.dart';
import '../screens/returns/returns_exchanges_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/shifts/shift_management_screen.dart';
import '../screens/mobile/owner_mobile_shell.dart';
import '../screens/mobile/owner_dashboard_view.dart';
import '../widgets/manager_override_dialog.dart';

enum AppNavDestination {
  checkout,
  dashboard,
  catalog,
  inventory,
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
      case AppNavDestination.dashboard:
      case AppNavDestination.reports:
        return AppPermissions.viewReports;
      case AppNavDestination.inventory:
        return AppPermissions.manageInventory;
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
      _temporaryOverrides.clear();
      return LoginScreen(
        onLoginSuccess: () {
          setState(() => _currentNav = AppNavDestination.checkout);
        },
      );
    }

    // 2. If session is locked -> Lock Screen
    if (authState.isLocked) {
      _temporaryOverrides.clear();
      return const LockScreen();
    }

    final isRtl = context.isRtl;

    // Responsive Mobile check: on compact mobile screens, present the Owner Mobile Shell ONLY for Owner / Manager!
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isOwnerOrManager = authState.user?.role == AppRoles.owner ||
        authState.user?.role == AppRoles.manager;
    if (screenWidth < 768 && isOwnerOrManager) {
      return const OwnerMobileShell();
    }

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
                // Brand (the checkout top bar owns the menu toggle there)
                Container(
                  height: 68,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: AlignmentDirectional.centerStart,
                  child: Row(
                    children: [
                      if (!_isDrawerOpen)
                        Expanded(
                          child: Center(
                            child: Image.asset(
                              'assets/images/trace_logo_mark.png',
                              width: 32,
                              height: 32,
                              fit: BoxFit.contain,
                            ),
                          ),
                        )
                      else ...[
                        const SizedBox(width: 6),
                        Image.asset(
                          'assets/images/trace_logo_mark.png',
                          width: 34,
                          height: 34,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            context.loc.appTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 21,
                              color: AppDesignTokens.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_currentNav != AppNavDestination.checkout)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: IconButton(
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
                  ),

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
                        AppNavDestination.dashboard,
                        Icons.dashboard_outlined,
                        'Tableau de bord',
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

                // Cashier card + sign out
                Container(
                  padding: const EdgeInsets.all(AppDesignTokens.space12),
                  child: Column(
                    children: [
                      if (_isDrawerOpen)
                        InkWell(
                          onTap: () =>
                              ref.read(authNotifierProvider.notifier).lock(),
                          borderRadius: BorderRadius.circular(
                            AppDesignTokens.radiusLg,
                          ),
                          child: Tooltip(
                            message: context.loc.lockRegister,
                            child: Container(
                              padding: const EdgeInsets.all(
                                AppDesignTokens.space12,
                              ),
                              decoration: BoxDecoration(
                                color: AppDesignTokens.surface,
                                borderRadius: BorderRadius.circular(
                                  AppDesignTokens.radiusLg,
                                ),
                                border: Border.all(
                                  color: AppDesignTokens.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  _userAvatar(authState, 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          authState.user?.displayName ?? '',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color:
                                                AppDesignTokens.textPrimary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          _formatRole(
                                            authState.user?.role,
                                            context,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color:
                                                AppDesignTokens.textSecondary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    size: 20,
                                    color: AppDesignTokens.textSecondary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        IconButton(
                          onPressed: () =>
                              ref.read(authNotifierProvider.notifier).lock(),
                          tooltip: context.loc.lockRegister,
                          icon: _userAvatar(authState, 16),
                        ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () =>
                            ref.read(authNotifierProvider.notifier).logout(),
                        borderRadius: BorderRadius.circular(
                          AppDesignTokens.radiusMd,
                        ),
                        child: Tooltip(
                          message: context.loc.logoutSession,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              mainAxisAlignment: _isDrawerOpen
                                  ? MainAxisAlignment.start
                                  : MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.logout,
                                  size: 20,
                                  color: AppDesignTokens.danger,
                                ),
                                if (_isDrawerOpen) ...[
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      context.loc.logoutSession,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: AppDesignTokens.danger,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
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

  Widget _userAvatar(AuthState authState, double radius) {
    final name = authState.user?.displayName ?? '';
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppDesignTokens.primarySoft,
      child: Text(
        name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'U',
        style: TextStyle(
          fontSize: radius * 0.8,
          color: AppDesignTokens.primary,
          fontWeight: FontWeight.bold,
        ),
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
      height: 48,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isSelected ? AppDesignTokens.primarySoft : Colors.transparent,
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
            size: 22,
          ),
          if (_isDrawerOpen) ...[
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
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

    const destinations = [
      AppNavDestination.checkout,
      AppNavDestination.dashboard,
      AppNavDestination.catalog,
      AppNavDestination.inventory,
      AppNavDestination.returns,
      AppNavDestination.labels,
      AppNavDestination.shifts,
      AppNavDestination.reports,
      AppNavDestination.settings,
    ];

    final index = destinations.indexOf(_currentNav);
    return IndexedStack(
      index: index >= 0 ? index : 0,
      children: [
        CheckoutScreen(
          onOpenMenu: () => setState(() => _isDrawerOpen = !_isDrawerOpen),
        ),
        const OwnerDashboardView(),
        const ProductListScreen(),
        const InventoryScreen(),
        const ReturnsExchangesScreen(),
        const LabelStudioScreen(),
        const ShiftManagementScreen(),
        const ReportsScreen(),
        const SettingsScreen(),
      ],
    );
  }
}
