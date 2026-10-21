import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'owner_dashboard_view.dart';
import 'owner_catalog_view.dart';
import 'owner_stock_alerts_view.dart';
import 'owner_sync_view.dart';

class OwnerMobileShell extends ConsumerStatefulWidget {
  const OwnerMobileShell({super.key});

  @override
  ConsumerState<OwnerMobileShell> createState() => _OwnerMobileShellState();
}

class _OwnerMobileShellState extends ConsumerState<OwnerMobileShell> {
  int _currentIndex = 0;
  String _storeName = 'JazzPOS';

  @override
  void initState() {
    super.initState();
    _loadStoreInfo();
  }

  Future<void> _loadStoreInfo() async {
    try {
      final boutiqueService = ref.read(boutiqueSettingsServiceProvider);
      final settings = await boutiqueService.loadSettings();
      if (mounted && settings.name.isNotEmpty) {
        setState(() => _storeName = settings.name);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    final titles = [
      'Aperçu Boutique',
      'Catalogue & Prix',
      'Alertes d\'Inventaire',
      'Synchronisation Cloud',
    ];

    return Scaffold(
      backgroundColor: AppDesignTokens.background,
      appBar: AppBar(
        backgroundColor: AppDesignTokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: AppDesignTokens.space16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _storeName,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: AppDesignTokens.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              '${titles[_currentIndex]}${authState.user?.displayName != null ? " • ${authState.user!.displayName}" : ""}',
              style: const TextStyle(fontSize: 11, color: AppDesignTokens.textSecondary),
            ),
          ],
        ),
        actions: [
          // Lock Session Button
          IconButton(
            icon: const Icon(Icons.lock_outline, size: 20, color: AppDesignTokens.textSecondary),
            tooltip: 'Verrouiller la session',
            onPressed: () {
              ref.read(authNotifierProvider.notifier).lockSession();
            },
          ),
          // Logout Button
          IconButton(
            icon: const Icon(Icons.logout, size: 20, color: AppDesignTokens.danger),
            tooltip: 'Déconnexion',
            onPressed: () {
              ref.read(authNotifierProvider.notifier).logout();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          OwnerDashboardView(),
          OwnerCatalogView(),
          OwnerStockAlertsView(),
          OwnerSyncView(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        backgroundColor: AppDesignTokens.surface,
        indicatorColor: AppDesignTokens.primary.withValues(alpha: 0.12),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: AppDesignTokens.primary),
            label: 'Aperçu',
          ),
          NavigationDestination(
            icon: Icon(Icons.sell_outlined),
            selectedIcon: Icon(Icons.sell, color: AppDesignTokens.primary),
            label: 'Catalogue',
          ),
          NavigationDestination(
            icon: Icon(Icons.warning_amber_outlined),
            selectedIcon: Icon(Icons.warning, color: AppDesignTokens.warning),
            label: 'Alertes',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud_sync_outlined),
            selectedIcon: Icon(Icons.cloud_sync, color: AppDesignTokens.primary),
            label: 'Synchro',
          ),
        ],
      ),
    );
  }
}
