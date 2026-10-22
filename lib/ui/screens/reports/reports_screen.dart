import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat, toBeginningOfSentenceCase;
import 'package:tracepos/core/constants/app_constants.dart';
import 'package:tracepos/core/localization/app_localizations.dart';
import 'package:tracepos/core/localization/app_localizations_delegate.dart';
import 'package:tracepos/core/logging/pos_logger.dart';
import 'package:tracepos/core/money/money.dart';
import 'package:tracepos/domain/services/report_service.dart';
import 'package:tracepos/providers/app_providers.dart';
import 'package:tracepos/providers/auth_provider.dart';
import 'package:tracepos/ui/screens/reports/report_charts.dart';
import 'package:tracepos/ui/theme/app_design_tokens.dart';
import 'package:tracepos/ui/widgets/money_display.dart';

enum _Period { today, week, month, custom }

enum _Metric { net, profit, cost }

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  static const _blue = AppDesignTokens.info;
  static const _amber = Color(0xFFF59E0B);
  static const _purple = Color(0xFF8B5CF6);

  int _tab = 0;
  _Period _period = _Period.today;
  DateTimeRange? _custom;
  _Metric _metric = _Metric.net;

  SalesReportSummary? _sales;
  SalesReportSummary? _previous;
  List<TrendPoint> _trend = [];
  List<ClothingSizePerformance> _sizes = [];
  InventoryValuationReport? _valuation;
  String _storeName = '';
  bool _isLoading = true;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  /// Start/end (inclusive) of the analysed period.
  ({DateTime start, DateTime end}) get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime start;
    DateTime lastDay;
    switch (_period) {
      case _Period.today:
        start = today;
        lastDay = today;
      case _Period.week:
        start = today.subtract(const Duration(days: 6));
        lastDay = today;
      case _Period.month:
        start = today.subtract(const Duration(days: 29));
        lastDay = today;
      case _Period.custom:
        final r = _custom!;
        start = DateTime(r.start.year, r.start.month, r.start.day);
        lastDay = DateTime(r.end.year, r.end.month, r.end.day);
    }
    // Sub-second timestamps: end just before the next local midnight.
    final end = DateTime(lastDay.year, lastDay.month, lastDay.day + 1)
        .subtract(const Duration(microseconds: 1));
    return (start: start, end: end);
  }

  Future<void> _loadReports() async {
    final id = ++_requestId;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final service = ref.read(reportServiceProvider);
      final actorId = ref.read(authNotifierProvider).user?.id ?? '';
      final r = _range;
      final days = DateTime(r.end.year, r.end.month, r.end.day)
              .difference(DateTime(r.start.year, r.start.month, r.start.day))
              .inDays +
          1;
      final prevEnd = r.start.subtract(const Duration(microseconds: 1));
      final prevStart = r.start.subtract(Duration(days: days));

      final sales = await service.getSalesReport(
          actorId: actorId, startDate: r.start, endDate: r.end);
      final previous = await service.getSalesReport(
          actorId: actorId, startDate: prevStart, endDate: prevEnd);
      final trend = await service.getSalesTrend(
          actorId: actorId, startDate: r.start, endDate: r.end, hourly: days == 1);
      final sizes = await service.getSizePerformance(
          actorId: actorId, startDate: r.start, endDate: r.end);
      final valuation = await service.getInventoryValuation(actorId: actorId);
      final store = await (ref.read(databaseProvider).select(
            ref.read(databaseProvider).stores,
          )..limit(1))
          .getSingleOrNull();

      if (!mounted || id != _requestId) return;
      setState(() {
        _sales = sales;
        _previous = previous;
        _trend = trend;
        _sizes = sizes;
        _valuation = valuation;
        _storeName = store?.name ?? AppConstants.appName;
        _isLoading = false;
      });
    } catch (e) {
      PosLogger.instance.warning('Reports', 'Could not load reports: $e');
      if (!mounted || id != _requestId) return;
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _custom ??
          DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: AppDesignTokens.primary,
              ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _custom = picked;
      _period = _Period.custom;
    });
    _loadReports();
  }

  void _setPeriod(_Period p) {
    if (_period == p) return;
    setState(() => _period = p);
    _loadReports();
  }

  // ── helpers ─────────────────────────────────────────────────────────────

  static String _cap(String s) => toBeginningOfSentenceCase(s) ?? s;

  static double _tnd(Money m) => m.millimes / 1000;

  /// % change vs previous period, or null when there is nothing to compare.
  static double? _pct(num current, num previous) =>
      previous == 0 ? null : (current - previous) / previous.abs() * 100;

  BoxDecoration _cardDeco({Color? color, Color? border}) => BoxDecoration(
        color: color ?? AppDesignTokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border ?? AppDesignTokens.border),
        boxShadow: AppDesignTokens.shadowSm,
      );

  Widget _iconBadge(IconData icon, {Color color = AppDesignTokens.primary, double size = 40}) =>
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(size / 3),
        ),
        child: Icon(icon, color: color, size: size * 0.52),
      );

  Widget _deltaPill(double? pct, {bool invert = false, bool bare = false}) {
    if (pct == null) return const SizedBox.shrink();
    final up = pct >= 0;
    final good = invert ? !up : up;
    final color = good ? AppDesignTokens.primary : AppDesignTokens.danger;
    final text = '${pct.abs().toStringAsFixed(1)}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 13, color: color),
          const SizedBox(width: 2),
          Text(
            bare ? text : '${up ? '+' : '-'}$text',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  // ── build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    return Scaffold(
      backgroundColor: AppDesignTokens.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _header(loc),
            Expanded(
              child: _error != null
                  ? _errorState()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _tabBar(loc),
                          const SizedBox(height: 12),
                          _periodBar(loc),
                          const SizedBox(height: 16),
                          if (_isLoading || _sales == null)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 120),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else
                            [
                              _overview(loc),
                              _buildSizePerformanceView(loc),
                              _buildValuationView(loc),
                            ][_tab],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: AppDesignTokens.danger),
            const SizedBox(height: 12),
            Text(_error ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadReports, child: const Text('Réessayer')),
          ],
        ),
      );

  Widget _header(AppLocalizations loc) {
    final now = DateTime.now();
    final date = _cap(DateFormat('EEE d MMM y', 'fr').format(now));
    final alerts = (_valuation?.lowStockCount ?? 0) + (_valuation?.outOfStockCount ?? 0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth > 820;
          final title = Row(
            children: [
              _iconBadge(Icons.bar_chart_rounded, size: 52),
              const SizedBox(width: 14),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.reportsTitle,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Analysez vos ventes, marges, performances et stocks en temps réel.',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, color: AppDesignTokens.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          );
          final chips = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _headerChip(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_month_outlined, size: 20, color: AppDesignTokens.textSecondary),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(date, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        Text(DateFormat('HH:mm').format(now),
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(alerts == 0
                        ? 'Aucune alerte de stock.'
                        : '$alerts alerte(s) de stock : ${_valuation?.lowStockCount ?? 0} faible(s), ${_valuation?.outOfStockCount ?? 0} en rupture.'),
                  ),
                ),
                child: _headerChip(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.notifications_none_rounded, size: 24, color: AppDesignTokens.textPrimary),
                      if (alerts > 0)
                        Positioned(
                          right: 1,
                          top: 0,
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(color: AppDesignTokens.danger, shape: BoxShape.circle),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _headerChip(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _iconBadge(Icons.storefront_rounded, size: 32),
                    const SizedBox(width: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        _storeName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          if (wide) {
            return Row(children: [Expanded(child: title), const SizedBox(width: 16), chips]);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 12), SingleChildScrollView(scrollDirection: Axis.horizontal, child: chips)],
          );
        },
      ),
    );
  }

  Widget _headerChip({required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: _cardDeco(),
        child: child,
      );

  Widget _tabBar(AppLocalizations loc) {
    final items = [
      (Icons.account_balance_wallet_outlined, loc.salesAndMarginTab),
      (Icons.straighten, loc.sizePerformanceTab),
      (Icons.inventory_2_outlined, loc.stockValuationTab),
    ];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _tab = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _tab == i ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border(
                      bottom: BorderSide(
                        color: _tab == i ? AppDesignTokens.primary : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(items[i].$1, size: 22,
                          color: _tab == i ? AppDesignTokens.primary : AppDesignTokens.textSecondary),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          _cap(items[i].$2.toLowerCase()),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _tab == i ? AppDesignTokens.primary : AppDesignTokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _periodBar(AppLocalizations loc) {
    Widget chip(String label, _Period p) {
      final selected = _period == p;
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _setPeriod(p),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              color: selected ? AppDesignTokens.primarySoft : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppDesignTokens.primary : AppDesignTokens.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  const Icon(Icons.check_rounded, size: 18, color: AppDesignTokens.primary),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppDesignTokens.primary : AppDesignTokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final customSelected = _period == _Period.custom;
    final customLabel = customSelected && _custom != null
        ? '${DateFormat('dd/MM/yy').format(_custom!.start)} – ${DateFormat('dd/MM/yy').format(_custom!.end)}'
        : 'Personnaliser la période';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: _cardDeco(),
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > 900;
        Widget bar(List<Widget> kids) => wide
            ? Row(children: kids)
            : SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: kids));
        return bar(
          [
            Text(
              '${loc.analysisPeriod} ',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppDesignTokens.textSecondary),
            ),
            const SizedBox(width: 12),
            chip(loc.periodToday, _Period.today),
            chip(loc.periodWeek, _Period.week),
            chip(loc.periodMonth, _Period.month),
            if (wide) const Spacer() else const SizedBox(width: 40),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _pickCustomRange,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  color: customSelected ? AppDesignTokens.primarySoft : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: customSelected ? AppDesignTokens.primary : AppDesignTokens.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_month_outlined, size: 18),
                    const SizedBox(width: 10),
                    Text(customLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: loc.refreshTotals,
              onPressed: _loadReports,
              icon: const Icon(Icons.refresh, color: AppDesignTokens.textSecondary),
            ),
          ],
        );
      }),
    );
  }

  // ── overview tab ─────────────────────────────────────────────────────────

  Widget _overview(AppLocalizations loc) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 1000;
        final kpis = _kpiRow(loc, c.maxWidth);
        final detail = _detailCard(loc);
        final payments = _paymentsCard(loc, compact: !wide);
        final evolution = _evolutionCard();
        final bottomLeft = _sizePreview(loc);
        final bottomRight = _valuationPreview(loc);
        const gap = SizedBox(height: 16);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            kpis,
            gap,
            if (wide)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  Expanded(flex: 11, child: detail),
                  const SizedBox(width: 16),
                  Expanded(flex: 10, child: Column(children: [payments, gap, evolution])),
                  ],
                ),
              )
            else ...[detail, gap, payments, gap, evolution],
            gap,
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 11, child: bottomLeft),
                  const SizedBox(width: 16),
                  Expanded(flex: 13, child: bottomRight),
                ],
              )
            else ...[bottomLeft, gap, bottomRight],
          ],
        );
      },
    );
  }

  /// Hourly data is shown in 2-hour slots over the active hours, which
  /// reads as a smooth curve instead of a spike for every quiet hour.
  List<TrendPoint> get _displayTrend {
    if (_trend.length != 24) return _trend;
    final active = _trend.where((t) => t.net.millimes != 0 || t.cost.millimes != 0);
    final firstHour = active.isEmpty ? 8 : active.first.start.hour;
    final lastHour = active.isEmpty ? 20 : active.last.start.hour;
    final from = (firstHour - firstHour % 2).clamp(0, 22);
    final to = (lastHour - lastHour % 2 + 2).clamp(from + 2, 24);
    final out = <TrendPoint>[];
    for (var h = from; h < to; h += 2) {
      final slice = _trend.sublist(h, h + 2);
      out.add(TrendPoint(
        start: slice.first.start,
        net: Money.fromMillimes(slice.fold(0, (a, t) => a + t.net.millimes)),
        cost: Money.fromMillimes(slice.fold(0, (a, t) => a + t.cost.millimes)),
      ));
    }
    return out;
  }

  List<double> _series(double Function(TrendPoint) f) =>
      [for (final p in _displayTrend) f(p)];

  Widget _kpiRow(AppLocalizations loc, double width) {
    final r = _sales!;
    final p = _previous!;
    final cards = [
      _kpiCard(
        icon: Icons.bar_chart_rounded,
        color: AppDesignTokens.primary,
        title: loc.netSalesRevenue,
        value: r.netSales.format(),
        delta: _pct(r.netSales.millimes, p.netSales.millimes),
        series: _series((t) => _tnd(t.net)),
      ),
      _kpiCard(
        icon: Icons.pie_chart_rounded,
        color: AppDesignTokens.primary,
        title: loc.grossMargin,
        value: r.grossProfit.format(),
        delta: _pct(r.grossProfit.millimes, p.grossProfit.millimes),
        series: _series((t) => _tnd(t.profit)),
      ),
      _kpiCard(
        icon: Icons.shopping_bag_rounded,
        color: const Color(0xFF64748B),
        title: loc.purchaseCostGoods,
        value: r.totalCost.format(),
        delta: _pct(r.totalCost.millimes, p.totalCost.millimes),
        invert: true,
        series: _series((t) => _tnd(t.cost)),
        lineColor: const Color(0xFF94A3B8),
      ),
      _kpiCard(
        icon: Icons.percent_rounded,
        color: _amber,
        title: loc.marginRate,
        value: '${r.grossMarginPercent.toStringAsFixed(1)} %',
        delta: _pct(r.grossMarginPercent, p.grossMarginPercent),
        series: _series((t) => t.net.millimes > 0 ? t.profit.millimes / t.net.millimes * 100 : 0),
        lineColor: _amber,
      ),
    ];
    if (width >= 1000) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 14),
              Expanded(child: cards[i]),
            ],
          ],
        ),
      );
    }
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [for (final c in cards) SizedBox(width: (width - 14) / 2, child: c)],
    );
  }

  Widget _kpiCard({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required double? delta,
    required List<double> series,
    bool invert = false,
    Color? lineColor,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBadge(icon, color: color, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppDesignTokens.textSecondary),
                ),
              ),
              _deltaPill(delta, invert: invert),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 6,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'vs période précédente',
                      style: TextStyle(fontSize: 10.5, color: AppDesignTokens.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 38,
                      child: Sparkline(values: series, color: lineColor ?? AppDesignTokens.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardTitle(IconData icon, String title, {Widget? trailing}) => Row(
        children: [
          Icon(icon, color: AppDesignTokens.primary, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppDesignTokens.textPrimary),
            ),
          ),
          if (trailing != null) trailing,
        ],
      );

  Widget _detailRow(IconData icon, String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: AppDesignTokens.textSecondary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(label, style: const TextStyle(fontSize: 14.5, color: AppDesignTokens.textSecondary)),
                ),
                Text(
                  value,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color ?? AppDesignTokens.textPrimary),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _totalPanel(IconData icon, String label, String value, {double size = 18, Widget? trailing, bool strong = false}) => Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: strong ? 18 : 13),
        decoration: BoxDecoration(
          color: AppDesignTokens.primarySoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppDesignTokens.primarySoftBorder),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppDesignTokens.primary, size: strong ? 30 : 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: strong ? 17 : 15, fontWeight: FontWeight.w800, color: AppDesignTokens.textPrimary),
              ),
            ),
            Text(value, style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: AppDesignTokens.primary)),
            if (trailing != null) ...[const SizedBox(width: 12), trailing],
          ],
        ),
      );

  Widget _detailCard(AppLocalizations loc) {
    final r = _sales!;
    final p = _previous!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          _cardTitle(
            Icons.description_rounded,
            loc.financialDetailPeriod,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${r.totalSalesCount} ${r.totalSalesCount == 1 ? 'vente clôturée' : 'ventes clôturées'}',
                style: const TextStyle(fontSize: 12, color: AppDesignTokens.textSecondary),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _detailRow(Icons.format_list_bulleted_rounded, loc.totalCompletedSalesCount, '${r.totalSalesCount}'),
          _detailRow(Icons.trending_up_rounded, loc.totalSales, r.grossSales.format()),
          _detailRow(Icons.percent_rounded, loc.grantedDiscounts, r.totalDiscounts.format(),
              color: r.totalDiscounts > Money.zero ? AppDesignTokens.danger : null),
          _detailRow(Icons.assignment_return_outlined, loc.refundsAndReturns, r.totalRefunds.format(),
              color: r.totalRefunds > Money.zero ? AppDesignTokens.danger : null),
          const SizedBox(height: 8),
          _totalPanel(Icons.account_balance_wallet_outlined, loc.actualNetSales, r.netSales.format()),
          const SizedBox(height: 6),
          _detailRow(Icons.inventory_2_outlined, loc.costOfGoodsSold, r.totalCost.format()),
            ],
          ),
          const SizedBox(height: 10),
          _totalPanel(
            Icons.savings_rounded,
            loc.netGrossProfit,
            r.grossProfit.format(),
            size: 26,
            strong: true,
            trailing: _deltaPill(_pct(r.grossProfit.millimes, p.grossProfit.millimes), bare: true),
          ),
        ],
      ),
    );
  }

  Widget _paymentsCard(AppLocalizations loc, {required bool compact}) {
    final by = _sales!.salesByPaymentMethod;
    int of(String k) => by[k]?.millimes ?? 0;
    final cash = of(AppConstants.paymentCash);
    final card = of(AppConstants.paymentCard);
    final credit = of(AppConstants.paymentStoreCredit);
    final total = by.values.fold<int>(0, (a, m) => a + m.millimes);
    final other = total - cash - card - credit;
    final rows = [
      ('Espèces', cash, AppDesignTokens.primary),
      ('Carte bancaire', card, _blue),
      ('Avoir', credit, _amber),
      ('Autre', other, _purple),
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.credit_card_rounded, loc.paymentMethodBreakdown),
          const SizedBox(height: 14),
          Builder(
            builder: (context) {
              final donut = SizedBox(
                width: 170,
                height: 170,
                child: DonutChart(
                  thickness: 24,
                  slices: [for (final r in rows) DonutSlice(r.$2.toDouble(), r.$3)],
                  center: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Total', style: TextStyle(fontSize: 12, color: AppDesignTokens.textSecondary)),
                      Text(
                        Money.fromMillimes(total).format(includeCurrency: false),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const Text('TND', style: TextStyle(fontSize: 12, color: AppDesignTokens.textSecondary)),
                    ],
                  ),
                ),
              );
              final legend = Column(
                children: [
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          Container(width: 11, height: 11, decoration: BoxDecoration(color: r.$3, shape: BoxShape.circle)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(r.$1, style: const TextStyle(fontSize: 14, color: AppDesignTokens.textSecondary))),
                          Text(Money.fromMillimes(r.$2).format(),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                          SizedBox(
                            width: 52,
                            child: Text(
                              total > 0 ? '${(r.$2 / total * 100).round()}%' : '0%',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 13, color: AppDesignTokens.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
              if (compact) {
                return Column(children: [donut, const SizedBox(height: 12), legend]);
              }
              return Row(children: [donut, const SizedBox(width: 24), Expanded(child: legend)]);
            },
          ),
        ],
      ),
    );
  }

  Widget _evolutionCard() {
    final hourly = _trend.length == 24;
    final label = switch (_metric) {
      _Metric.net => "Chiffre d'affaires net",
      _Metric.profit => 'Bénéfice brut',
      _Metric.cost => "Coût d'achat",
    };
    double value(TrendPoint t) => _tnd(switch (_metric) {
          _Metric.net => t.net,
          _Metric.profit => t.profit,
          _Metric.cost => t.cost,
        });
    final trend = _displayTrend;
    final points = [
      for (final t in trend)
        TrendChartPoint(
          hourly ? '${t.start.hour.toString().padLeft(2, '0')}:00' : DateFormat('dd/MM').format(t.start),
          value(t),
        ),
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(
            Icons.show_chart_rounded,
            'Évolution des ventes',
            trailing: PopupMenuButton<_Metric>(
              tooltip: '',
              onSelected: (m) => setState(() => _metric = m),
              itemBuilder: (_) => const [
                PopupMenuItem(value: _Metric.net, child: Text("Chiffre d'affaires net")),
                PopupMenuItem(value: _Metric.profit, child: Text('Bénéfice brut')),
                PopupMenuItem(value: _Metric.cost, child: Text("Coût d'achat")),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppDesignTokens.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 210,
            child: points.length < 2
                ? const Center(child: Text('Pas assez de données', style: TextStyle(color: AppDesignTokens.textSecondary)))
                : TrendChart(
                    points: points,
                    format: (v) => Money.fromMillimes((v * 1000).round()).format(),
                    tooltipLabel: (i) => hourly
                        ? points[i].label
                        : DateFormat('EEE d MMM', 'fr').format(trend[i].start),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _previewHeader(IconData icon, String title, int goTo) => Row(
        children: [
          Icon(icon, color: AppDesignTokens.textSecondary, size: 24),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
          const SizedBox(width: 6),
          const Text('(Aperçu)', style: TextStyle(fontSize: 13, color: AppDesignTokens.textSecondary)),
          const Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _tab = goTo),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppDesignTokens.border),
              ),
              child: const Text('Voir plus', style: TextStyle(fontSize: 12.5, color: AppDesignTokens.textSecondary)),
            ),
          ),
        ],
      );

  Widget _sizePreview(AppLocalizations loc) {
    final top = ([..._sizes]..sort((a, b) => b.unitsSold.compareTo(a.unitsSold))).take(3).toList();
    final maxSold = top.isEmpty ? 1 : top.first.unitsSold.clamp(1, 1 << 30);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _previewHeader(Icons.straighten, loc.sizePerformanceTab.length > 22 ? 'Performance des tailles' : _cap(loc.sizePerformanceTab.toLowerCase()), 1),
          const SizedBox(height: 14),
          if (top.isEmpty)
            Text(loc.noSalesForSizeAnalysis, style: const TextStyle(color: AppDesignTokens.textSecondary))
          else
            for (final s in top)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(width: 70, child: Text(s.size, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: s.unitsSold / maxSold,
                          minHeight: 11,
                          backgroundColor: const Color(0xFFEEF2F6),
                          valueColor: const AlwaysStoppedAnimation(AppDesignTokens.primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    SizedBox(width: 70, child: Text(loc.nPieces(s.unitsSold), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                    SizedBox(width: 96, child: Text(s.revenue.format(), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _valuationPreview(AppLocalizations loc) {
    final v = _valuation!;
    Widget cell(IconData icon, Color color, String label, Money amount) => Expanded(
          child: Row(
            children: [
              _iconBadge(icon, color: color, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppDesignTokens.textSecondary)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(amount.format(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _previewHeader(Icons.inventory_2_outlined, 'Valorisation du stock', 2),
          const SizedBox(height: 18),
          Row(
            children: [
              cell(Icons.inventory_2_rounded, _amber, 'Valeur stock au coût', v.valuationAtCost),
              const SizedBox(width: 12),
              cell(Icons.storefront_rounded, AppDesignTokens.primary, 'Valeur stock à la vente', v.valuationAtRetail),
              const SizedBox(width: 12),
              cell(Icons.trending_up_rounded, AppDesignTokens.primary, 'Plus-value potentielle', v.potentialProfit),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSizePerformanceView(AppLocalizations loc) {
    if (_sizes.isEmpty) {
      return Center(
        child: Text(
          loc.noSalesForSizeAnalysis,
          style: const TextStyle(color: AppDesignTokens.textSecondary),
        ),
      );
    }

    final maxSold = _sizes
        .map((s) => s.unitsSold)
        .reduce((a, b) => a > b ? a : b);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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

            ..._sizes.map((s) {
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
    if (_valuation == null) return const SizedBox.shrink();
    final v = _valuation!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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

}
