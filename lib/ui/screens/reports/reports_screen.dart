import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/localization/app_localizations.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/domain/services/report_service.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'package:jazzpos/ui/widgets/money_display.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _periodDays = 1; // 1 = today, 7 = week, 30 = month

  SalesReportSummary? _salesReport;
  List<ClothingSizePerformance> _sizeReport = [];
  InventoryValuationReport? _valuationReport;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadReports();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    setState(() => _isLoading = true);
    final reportService = ref.read(reportServiceProvider);

    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: _periodDays - 1));
    // Drift timestamps retain sub-second precision. Ending at 23:59:59 would
    // omit sales from the final fraction of the local day.
    final end = DateTime(
      now.year,
      now.month,
      now.day + 1,
    ).subtract(const Duration(microseconds: 1));

    final sales = await reportService.getSalesReport(
      startDate: start,
      endDate: end,
    );
    final sizes = await reportService.getSizePerformance(
      startDate: start,
      endDate: end,
    );
    final val = await reportService.getInventoryValuation();

    if (mounted) {
      setState(() {
        _salesReport = sales;
        _sizeReport = sizes;
        _valuationReport = val;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;

    return Scaffold(
      backgroundColor: AppDesignTokens.canvas,
      appBar: AppBar(
        title: Text(
          loc.reportsTitle,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        backgroundColor: AppDesignTokens.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppDesignTokens.textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(
            children: [
              TabBar(
                controller: _tabController,
                indicatorColor: AppDesignTokens.primary,
                labelColor: AppDesignTokens.primary,
                unselectedLabelColor: AppDesignTokens.textSecondary,
                indicatorWeight: 3,
                tabs: [
                  Tab(
                    icon: const Icon(Icons.analytics, size: 20),
                    text: loc.salesAndMarginTab.toUpperCase(),
                  ),
                  Tab(
                    icon: const Icon(Icons.straighten, size: 20),
                    text: loc.sizePerformanceTab.toUpperCase(),
                  ),
                  Tab(
                    icon: const Icon(Icons.account_balance_wallet, size: 20),
                    text: loc.stockValuationTab.toUpperCase(),
                  ),
                ],
              ),
              const Divider(height: 1, color: AppDesignTokens.border),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Period Selector Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              color: AppDesignTokens.surface,
              border: Border(bottom: BorderSide(color: AppDesignTokens.border)),
            ),
            child: Row(
              children: [
                Text(
                  loc.analysisPeriod,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                _buildPeriodChip(loc.periodToday, 1),
                const SizedBox(width: 8),
                _buildPeriodChip(loc.periodWeek, 7),
                const SizedBox(width: 8),
                _buildPeriodChip(loc.periodMonth, 30),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    Icons.refresh,
                    color: AppDesignTokens.textPrimary,
                  ),
                  onPressed: _loadReports,
                  tooltip: loc.refreshTotals,
                ),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Sales & Margin
                      _buildSalesReportView(loc),

                      // Tab 2: Size Performance
                      _buildSizePerformanceView(loc),

                      // Tab 3: Inventory Valuation
                      _buildValuationView(loc),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodChip(String label, int days) {
    final isSelected = _periodDays == days;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: AppDesignTokens.primary.withValues(alpha: 0.12),
      side: BorderSide(
        color: isSelected ? AppDesignTokens.primary : AppDesignTokens.border,
      ),
      labelStyle: TextStyle(
        color: isSelected
            ? AppDesignTokens.primary
            : AppDesignTokens.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      onSelected: (_) {
        setState(() => _periodDays = days);
        _loadReports();
      },
    );
  }

  Widget _buildSalesReportView(AppLocalizations loc) {
    if (_salesReport == null) return const SizedBox.shrink();
    final r = _salesReport!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row of Stat Cards
          Row(
            children: [
              _buildMetricCard(
                loc.netSalesRevenue,
                r.netSales,
                AppDesignTokens.success,
                Icons.trending_up,
              ),
              const SizedBox(width: 14),
              _buildMetricCard(
                loc.grossMargin,
                r.grossProfit,
                AppDesignTokens.primary,
                Icons.pie_chart,
              ),
              const SizedBox(width: 14),
              _buildMetricCard(
                loc.purchaseCostGoods,
                r.totalCost,
                AppDesignTokens.textSecondary,
                Icons.shopping_basket,
              ),
              const SizedBox(width: 14),
              _buildSimpleCard(
                loc.marginRate,
                '${r.grossMarginPercent.toStringAsFixed(1)} %',
                AppDesignTokens.warning,
                Icons.percent,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Detail Tables
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Breakdown Table
              Expanded(
                flex: 5,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppDesignTokens.surface,
                    borderRadius: BorderRadius.circular(
                      AppDesignTokens.radiusCard,
                    ),
                    border: Border.all(color: AppDesignTokens.border),
                    boxShadow: AppDesignTokens.shadowSm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.financialDetailPeriod,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildDetailRow(
                        loc.totalCompletedSalesCount,
                        '${r.totalSalesCount}',
                      ),
                      _buildDetailRowMoney(loc.totalSales, r.grossSales),
                      _buildDetailRowMoney(
                        loc.grantedDiscounts,
                        r.totalDiscounts,
                        color: AppDesignTokens.danger,
                      ),
                      _buildDetailRowMoney(
                        loc.refundsAndReturns,
                        r.totalRefunds,
                        color: AppDesignTokens.danger,
                      ),
                      const Divider(color: AppDesignTokens.border, height: 20),
                      _buildDetailRowMoney(
                        loc.actualNetSales,
                        r.netSales,
                        isBold: true,
                        color: AppDesignTokens.success,
                      ),
                      _buildDetailRowMoney(loc.costOfGoodsSold, r.totalCost),
                      const Divider(color: AppDesignTokens.border, height: 20),
                      _buildDetailRowMoney(
                        loc.netGrossProfit,
                        r.grossProfit,
                        isBold: true,
                        color: AppDesignTokens.primary,
                        fontSize: 18,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 20),

              // Payments breakdown
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppDesignTokens.surface,
                    borderRadius: BorderRadius.circular(
                      AppDesignTokens.radiusCard,
                    ),
                    border: Border.all(color: AppDesignTokens.border),
                    boxShadow: AppDesignTokens.shadowSm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.paymentMethodBreakdown,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (r.salesByPaymentMethod.isEmpty)
                        Text(
                          loc.noPaymentsInPeriod,
                          style: const TextStyle(
                            color: AppDesignTokens.textSecondary,
                          ),
                        )
                      else
                        ...r.salesByPaymentMethod.entries.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  entry.key.toUpperCase(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppDesignTokens.textPrimary,
                                  ),
                                ),
                                MoneyDisplay(amount: entry.value, fontSize: 15),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSizePerformanceView(AppLocalizations loc) {
    if (_sizeReport.isEmpty) {
      return Center(
        child: Text(
          loc.noSalesForSizeAnalysis,
          style: const TextStyle(color: AppDesignTokens.textSecondary),
        ),
      );
    }

    final maxSold = _sizeReport
        .map((s) => s.unitsSold)
        .reduce((a, b) => a > b ? a : b);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppDesignTokens.surface,
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
          border: Border.all(color: AppDesignTokens.border),
          boxShadow: AppDesignTokens.shadowSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc.salesByGarmentSize,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              loc.sizeDemandInsight,
              style: const TextStyle(
                color: AppDesignTokens.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),

            ..._sizeReport.map((s) {
              final ratio = maxSold > 0 ? (s.unitsSold / maxSold) : 0.0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: Text(
                        s.size,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 6,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 24,
                          backgroundColor: AppDesignTokens.surfaceElevated,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppDesignTokens.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 100,
                      child: Text(
                        loc.nPieces(s.unitsSold),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: MoneyDisplay(amount: s.revenue, fontSize: 14),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildValuationView(AppLocalizations loc) {
    if (_valuationReport == null) return const SizedBox.shrink();
    final v = _valuationReport!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              _buildMetricCard(
                loc.totalCostValue,
                v.valuationAtCost,
                AppDesignTokens.warning,
                Icons.inventory,
              ),
              const SizedBox(width: 14),
              _buildMetricCard(
                loc.totalRetailValue,
                v.valuationAtRetail,
                AppDesignTokens.success,
                Icons.store,
              ),
              const SizedBox(width: 14),
              _buildMetricCard(
                loc.potentialProfit,
                v.potentialProfit,
                AppDesignTokens.primary,
                Icons.auto_graph,
              ),
              const SizedBox(width: 14),
              _buildSimpleCard(
                loc.totalUnitsInStock,
                '${v.totalUnitsInStock}',
                AppDesignTokens.textPrimary,
                Icons.checkroom,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildSimpleCard(
                loc.lowStockAlertsCount,
                '${v.lowStockCount}',
                AppDesignTokens.warning,
                Icons.warning_amber,
              ),
              const SizedBox(width: 14),
              _buildSimpleCard(
                loc.outOfStockArticlesCount,
                '${v.outOfStockCount}',
                AppDesignTokens.danger,
                Icons.remove_shopping_cart,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    Money amount,
    Color color,
    IconData icon,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppDesignTokens.surface,
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
          border: Border.all(color: AppDesignTokens.border),
          boxShadow: AppDesignTokens.shadowSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppDesignTokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
              ],
            ),
            const SizedBox(height: 10),
            MoneyDisplay(amount: amount, fontSize: 20, color: color),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleCard(
    String title,
    String value,
    Color color,
    IconData icon,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppDesignTokens.surface,
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
          border: Border.all(color: AppDesignTokens.border),
          boxShadow: AppDesignTokens.shadowSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppDesignTokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppDesignTokens.textSecondary),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppDesignTokens.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRowMoney(
    String label,
    Money amount, {
    bool isBold = false,
    Color? color,
    double fontSize = 14,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isBold
                  ? AppDesignTokens.textPrimary
                  : AppDesignTokens.textSecondary,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          MoneyDisplay(amount: amount, fontSize: fontSize, color: color),
        ],
      ),
    );
  }
}
