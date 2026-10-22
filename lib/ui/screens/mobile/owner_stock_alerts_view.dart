import 'package:jazzpos/providers/auth_provider.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/report_service.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'package:jazzpos/ui/widgets/common/app_card.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';

class OwnerStockAlertsView extends ConsumerStatefulWidget {
  const OwnerStockAlertsView({super.key});

  @override
  ConsumerState<OwnerStockAlertsView> createState() => _OwnerStockAlertsViewState();
}

class _AlertItem {
  final Product product;
  final ProductVariant variant;
  final int currentStock;
  final int minAlert;

  const _AlertItem({
    required this.product,
    required this.variant,
    required this.currentStock,
    required this.minAlert,
  });

  bool get isOutOfStock => currentStock <= 0;
}

class _OwnerStockAlertsViewState extends ConsumerState<OwnerStockAlertsView> {
  bool _isLoading = true;
  InventoryValuationReport? _valuation;
  List<_AlertItem> _alerts = [];
  String _filter = 'ALL'; // ALL, OUT, LOW

  @override
  void initState() {
    super.initState();
    _loadStockAlerts();
  }

  Future<void> _loadStockAlerts() async {
    setState(() => _isLoading = true);
    try {
      final reportService = ref.read(reportServiceProvider);
      final db = ref.read(databaseProvider);

      final val = await reportService.getInventoryValuation(
        actorId: ref.read(authNotifierProvider).user?.id ?? '',
      );
      final variants = await (db.select(db.productVariants)
            ..where((t) => t.isActive.equals(true) & t.deletedAt.isNull()))
          .get();

      final products = await (db.select(db.products)
            ..where((t) => t.deletedAt.isNull()))
          .get();
      final productsMap = {for (final p in products) p.id: p};

      final stockLevels = await db.select(db.stockLevels).get();

      final items = <_AlertItem>[];
      for (final v in variants) {
        final lvls = stockLevels.where((s) => s.variantId == v.id);
        final qty = lvls.fold(0, (sum, s) => sum + s.quantity);

        if (qty <= v.minStockAlert) {
          final prod = productsMap[v.productId];
          if (prod != null) {
            items.add(_AlertItem(
              product: prod,
              variant: v,
              currentStock: qty,
              minAlert: v.minStockAlert,
            ));
          }
        }
      }

      // Sort: out-of-stock first, then lowest stock
      items.sort((a, b) => a.currentStock.compareTo(b.currentStock));

      if (mounted) {
        setState(() {
          _valuation = val;
          _alerts = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      PosLogger.instance.warning('owner_stock_alerts_view', 'Ignored error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final outOfStockCount = _valuation?.outOfStockCount ?? 0;
    final lowStockCount = _valuation?.lowStockCount ?? 0;
    final totalUnits = _valuation?.totalUnitsInStock ?? 0;
    final retailVal = _valuation?.valuationAtRetail ?? Money.zero;

    final filtered = _alerts.where((a) {
      if (_filter == 'OUT') return a.isOutOfStock;
      if (_filter == 'LOW') return !a.isOutOfStock;
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadStockAlerts,
      color: AppDesignTokens.primary,
      child: ListView(
        padding: const EdgeInsets.all(AppDesignTokens.space16),
        children: [
          // ── Valuation Summary Cards ──
          Row(
            children: [
              Expanded(
                child: AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Unités en Magasin', style: TextStyle(fontSize: 11, color: AppDesignTokens.textSecondary)),
                      const SizedBox(height: 4),
                      Text('$totalUnits pièces', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Valeur au Prix Public', style: TextStyle(fontSize: 11, color: AppDesignTokens.textSecondary)),
                      const SizedBox(height: 4),
                      Text(retailVal.formatted, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppDesignTokens.primary)),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Filter Segmented Controls ──
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'ALL',
                label: Text('Toutes (${_alerts.length})'),
              ),
              ButtonSegment(
                value: 'OUT',
                icon: const Icon(Icons.cancel, size: 16, color: AppDesignTokens.danger),
                label: Text('Ruptures ($outOfStockCount)'),
              ),
              ButtonSegment(
                value: 'LOW',
                icon: const Icon(Icons.warning, size: 16, color: AppDesignTokens.warning),
                label: Text('Critiques ($lowStockCount)'),
              ),
            ],
            selected: {_filter},
            onSelectionChanged: (set) => setState(() => _filter = set.first),
          ),

          const SizedBox(height: 16),

          // ── Alerts List ──
          if (filtered.isEmpty)
            AppCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: const [
                      Icon(Icons.check_circle_outline, size: 40, color: AppDesignTokens.success),
                      SizedBox(height: 10),
                      Text('Aucun stock critique pour ce filtre !', style: TextStyle(fontWeight: FontWeight.bold, color: AppDesignTokens.textPrimary)),
                      SizedBox(height: 4),
                      Text('Tous les niveaux d\'inventaire sont optimaux.', style: TextStyle(fontSize: 12, color: AppDesignTokens.textSecondary)),
                    ],
                  ),
                ),
              ),
            )
          else
            ...filtered.map((item) {
              final isZero = item.isOutOfStock;
              final badgeColor = isZero ? AppDesignTokens.danger : AppDesignTokens.warning;
              final badgeBg = isZero ? AppDesignTokens.danger.withValues(alpha: 0.1) : AppDesignTokens.warning.withValues(alpha: 0.1);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppDesignTokens.surface,
                  borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
                  border: Border.all(color: isZero ? AppDesignTokens.danger.withValues(alpha: 0.3) : AppDesignTokens.border),
                  boxShadow: AppDesignTokens.shadowSm,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: badgeBg, shape: BoxShape.circle),
                      child: Icon(
                        isZero ? Icons.remove_shopping_cart : Icons.inventory,
                        color: badgeColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.product.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'SKU: ${item.variant.sku} • Seuil min: ${item.minAlert}',
                            style: const TextStyle(fontSize: 11, color: AppDesignTokens.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        isZero ? '0 EN STOCK' : '${item.currentStock} RESTANTS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: badgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
