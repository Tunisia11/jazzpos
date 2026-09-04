import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/domain/services/report_service.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';
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
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);

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
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Rapports & Statistiques Financières'),
        backgroundColor: AppTheme.surface,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(icon: Icon(Icons.analytics), text: 'VENTES & MARGE BRUTE'),
            Tab(icon: Icon(Icons.straighten), text: 'PERFORMANCE DES TAILLES'),
            Tab(
              icon: Icon(Icons.account_balance_wallet),
              text: 'VALORISATION STOCK',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Period Selector Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: const Color(0xFF161F2E),
            child: Row(
              children: [
                const Text(
                  'Période d\'analyse :',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('Aujourd\'hui'),
                  selected: _periodDays == 1,
                  onSelected: (_) {
                    setState(() => _periodDays = 1);
                    _loadReports();
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('7 Derniers Jours'),
                  selected: _periodDays == 7,
                  onSelected: (_) {
                    setState(() => _periodDays = 7);
                    _loadReports();
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Ce Mois (30j)'),
                  selected: _periodDays == 30,
                  onSelected: (_) {
                    setState(() => _periodDays = 30);
                    _loadReports();
                  },
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadReports,
                  tooltip: 'Actualiser',
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
                      _buildSalesReportView(),

                      // Tab 2: Size Performance
                      _buildSizePerformanceView(),

                      // Tab 3: Inventory Valuation
                      _buildValuationView(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesReportView() {
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
                'Chiffre d\'Affaires Net',
                r.netSales,
                AppTheme.success,
                Icons.trending_up,
              ),
              const SizedBox(width: 14),
              _buildMetricCard(
                'Marge Brute Réalisée',
                r.grossProfit,
                Colors.blueAccent,
                Icons.pie_chart,
              ),
              const SizedBox(width: 14),
              _buildMetricCard(
                'Coût d\'Achat Marchandises',
                r.totalCost,
                AppTheme.textSecondary,
                Icons.shopping_basket,
              ),
              const SizedBox(width: 14),
              _buildSimpleCard(
                'Taux de Marge Brute',
                '${r.grossMarginPercent.toStringAsFixed(1)} %',
                Colors.amber,
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
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Détail Financier de la Période',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildDetailRow(
                        'Nombre total de ventes clôturées',
                        '${r.totalSalesCount}',
                      ),
                      _buildDetailRowMoney(
                        'Chiffre d\'affaires brut',
                        r.grossSales,
                      ),
                      _buildDetailRowMoney(
                        'Remises accordées (-)',
                        r.totalDiscounts,
                        color: AppTheme.error,
                      ),
                      _buildDetailRowMoney(
                        'Remboursements et retours (-)',
                        r.totalRefunds,
                        color: AppTheme.error,
                      ),
                      const Divider(color: AppTheme.border, height: 20),
                      _buildDetailRowMoney(
                        'Chiffre d\'Affaires Net Réel',
                        r.netSales,
                        isBold: true,
                        color: AppTheme.success,
                      ),
                      _buildDetailRowMoney(
                        'Coût des marchandises vendues (COGS)',
                        r.totalCost,
                      ),
                      const Divider(color: AppTheme.border, height: 20),
                      _buildDetailRowMoney(
                        'Bénéfice Brut Net',
                        r.grossProfit,
                        isBold: true,
                        color: Colors.blueAccent,
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
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Répartition par Mode de Paiement',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (r.salesByPaymentMethod.isEmpty)
                        const Text(
                          'Aucun paiement sur la période',
                          style: TextStyle(color: AppTheme.textSecondary),
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

  Widget _buildSizePerformanceView() {
    if (_sizeReport.isEmpty) {
      return const Center(
        child: Text(
          'Aucune vente enregistrée sur cette période pour analyser les tailles',
          style: TextStyle(color: AppTheme.textSecondary),
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
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ventes par Taille de Vêtement',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Identifiez les tailles les plus demandées pour optimiser vos réassorts :',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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
                          color: Colors.white,
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
                          backgroundColor: const Color(0xFF161F2E),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppTheme.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 100,
                      child: Text(
                        '${s.unitsSold} pièces',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
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

  Widget _buildValuationView() {
    if (_valuationReport == null) return const SizedBox.shrink();
    final v = _valuationReport!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              _buildMetricCard(
                'Valeur au Coût d\'Achat',
                v.valuationAtCost,
                AppTheme.warning,
                Icons.inventory,
              ),
              const SizedBox(width: 14),
              _buildMetricCard(
                'Valeur Vente (Prix de détail)',
                v.valuationAtRetail,
                AppTheme.success,
                Icons.store,
              ),
              const SizedBox(width: 14),
              _buildMetricCard(
                'Bénéfice Potentiel Stock',
                v.potentialProfit,
                Colors.blueAccent,
                Icons.auto_graph,
              ),
              const SizedBox(width: 14),
              _buildSimpleCard(
                'Pièces Totales en Stock',
                '${v.totalUnitsInStock}',
                Colors.white,
                Icons.checkroom,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildSimpleCard(
                'Alertes Stock Faible (≤ 2)',
                '${v.lowStockCount}',
                AppTheme.warning,
                Icons.warning_amber,
              ),
              const SizedBox(width: 14),
              _buildSimpleCard(
                'Articles en Rupture (0)',
                '${v.outOfStockCount}',
                AppTheme.error,
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
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
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
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                Icon(icon, size: 16, color: color),
              ],
            ),
            const SizedBox(height: 8),
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
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
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
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                Icon(icon, size: 16, color: color),
              ],
            ),
            const SizedBox(height: 8),
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
          Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
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
              color: isBold ? Colors.white : AppTheme.textSecondary,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          MoneyDisplay(amount: amount, fontSize: fontSize, color: color),
        ],
      ),
    );
  }
}
