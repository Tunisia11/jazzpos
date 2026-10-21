import 'package:jazzpos/providers/auth_provider.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/report_service.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'package:jazzpos/ui/widgets/common/app_card.dart';

class OwnerDashboardView extends ConsumerStatefulWidget {
  const OwnerDashboardView({super.key});

  @override
  ConsumerState<OwnerDashboardView> createState() => _OwnerDashboardViewState();
}

class _OwnerDashboardViewState extends ConsumerState<OwnerDashboardView> {
  bool _isLoading = true;
  SalesReportSummary? _summary;
  List<Sale> _recentSales = [];
  int _lowStockCount = 0;
  int _outOfStockCount = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

      final reportService = ref.read(reportServiceProvider);
      final db = ref.read(databaseProvider);

      final actorId = ref.read(authNotifierProvider).user?.id ?? '';
      final summary = await reportService.getSalesReport(
        actorId: actorId,
        startDate: startOfDay,
        endDate: endOfDay,
      );

      final recent = await (db.select(db.sales)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
            ..limit(8))
          .get();

      final valuation = await reportService.getInventoryValuation(actorId: actorId);

      if (mounted) {
        setState(() {
          _summary = summary;
          _recentSales = recent;
          _lowStockCount = valuation.lowStockCount;
          _outOfStockCount = valuation.outOfStockCount;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final gross = _summary?.netSales ?? Money.zero;
    final salesCount = _summary?.totalSalesCount ?? 0;
    final avgBasket = salesCount > 0
        ? Money.fromMillimes(gross.millimes ~/ salesCount)
        : Money.zero;
    final cashSales = _summary?.salesByPaymentMethod[AppConstants.paymentCash] ?? Money.zero;
    final cardSales = _summary?.salesByPaymentMethod[AppConstants.paymentCard] ?? Money.zero;

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      color: AppDesignTokens.primary,
      child: ListView(
        padding: const EdgeInsets.all(AppDesignTokens.space16),
        children: [
          // ── Hero Revenue Card ──
          Container(
            padding: const EdgeInsets.all(AppDesignTokens.space20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppDesignTokens.radiusXl),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'CHIFFRE D’AFFAIRES AUJOURD’HUI',
                        style: TextStyle(
                          color: Color(0xFF93C5FD),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        DateFormat('dd/MM/yyyy').format(DateTime.now()),
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  gross.formatted,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildHeroMetric('Ventes', '$salesCount'),
                    Container(height: 24, width: 1, color: Colors.white24),
                    _buildHeroMetric('Panier Moyen', avgBasket.formatted),
                    Container(height: 24, width: 1, color: Colors.white24),
                    _buildHeroMetric(
                      'Marge',
                      '${(_summary?.grossMarginPercent ?? 0.0).toStringAsFixed(1)}%',
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Payment Methods Pill Breakdown ──
          Row(
            children: [
              Expanded(
                child: AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.payments_outlined, color: AppDesignTokens.success, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Espèces', style: TextStyle(fontSize: 11, color: AppDesignTokens.textSecondary)),
                            Text(cashSales.formatted, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.credit_card, color: AppDesignTokens.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Carte / TPE', style: TextStyle(fontSize: 11, color: AppDesignTokens.textSecondary)),
                            Text(cardSales.formatted, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Stock Alerts Quick Summary ──
          if (_lowStockCount > 0 || _outOfStockCount > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _outOfStockCount > 0
                    ? AppDesignTokens.danger.withValues(alpha: 0.08)
                    : AppDesignTokens.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppDesignTokens.radiusMd),
                border: Border.all(
                  color: _outOfStockCount > 0
                      ? AppDesignTokens.danger.withValues(alpha: 0.3)
                      : AppDesignTokens.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: _outOfStockCount > 0 ? AppDesignTokens.danger : AppDesignTokens.warning,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$_outOfStockCount rupture(s) et $_lowStockCount stock(s) critique(s) détectés.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _outOfStockCount > 0 ? AppDesignTokens.dangerText : AppDesignTokens.warningText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Recent Sales Header ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Dernières Transactions',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppDesignTokens.textPrimary),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Aujourd’hui',
                style: TextStyle(fontSize: 12, color: AppDesignTokens.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_recentSales.isEmpty)
            AppCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: const [
                      Icon(Icons.receipt_long_outlined, size: 36, color: AppDesignTokens.textMuted),
                      SizedBox(height: 8),
                      Text('Aucune vente enregistrée pour le moment', style: TextStyle(color: AppDesignTokens.textSecondary)),
                    ],
                  ),
                ),
              ),
            )
          else
            ..._recentSales.map((s) => _buildSaleItem(s)),
        ],
      ),
    );
  }

  Widget _buildHeroMetric(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Color(0xFFBFDBFE), fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSaleItem(Sale s) {
    final timeStr = DateFormat('HH:mm').format(s.createdAt);
    final total = Money.fromMillimes(s.totalMillimes);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppDesignTokens.surface,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput),
        border: Border.all(color: AppDesignTokens.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppDesignTokens.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shopping_bag_outlined, color: AppDesignTokens.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.receiptNumber,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppDesignTokens.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  'Heure: $timeStr • ${s.offlineSynced ? "Synchronisé" : "Local"}',
                  style: TextStyle(
                    fontSize: 11,
                    color: s.offlineSynced ? AppDesignTokens.success : AppDesignTokens.warningText,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '+${total.formatted} DT',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: AppDesignTokens.successText,
            ),
          ),
        ],
      ),
    );
  }
}
