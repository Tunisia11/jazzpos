import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat, toBeginningOfSentenceCase;
import 'package:tracepos/core/constants/app_constants.dart';
import 'package:tracepos/core/logging/pos_logger.dart';
import 'package:tracepos/core/money/money.dart';
import 'package:tracepos/domain/services/report_service.dart';
import 'package:tracepos/providers/app_providers.dart';
import 'package:tracepos/providers/auth_provider.dart';
import 'package:tracepos/ui/screens/dashboard/order_details_screen.dart';
import 'package:tracepos/ui/screens/dashboard/sale_labels.dart';
import 'package:tracepos/ui/theme/app_design_tokens.dart';
import 'package:tracepos/ui/widgets/common/product_thumbnail.dart';

/// Desktop owner dashboard: today's revenue, payment split, hourly sales and
/// the latest transactions.
class DashboardScreen extends ConsumerStatefulWidget {
  /// Called with the typed text when the user searches (opens the POS).
  final ValueChanged<String>? onSearch;

  /// Opens the full sales/reports screen.
  final VoidCallback? onViewSales;

  /// Opens the stock screen (from the alert card).
  final VoidCallback? onViewStock;

  const DashboardScreen({
    super.key,
    this.onSearch,
    this.onViewSales,
    this.onViewStock,
  });

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  static const _green = AppDesignTokens.primary;
  static const _greenDark = Color(0xFF0F5132);

  DashboardSummary? _data;
  bool _loading = true;
  String? _error;
  int _days = 1;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final actor = ref.read(authNotifierProvider).user?.id ?? '';
      final data = await ref
          .read(reportServiceProvider)
          .getDashboardSummary(actorId: actor, days: _days);
      if (mounted) setState(() => _data = data);
    } catch (e) {
      PosLogger.instance.warning('Dashboard', 'Could not load dashboard: $e');
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  String _fmt(Money m) => m.format();

  /// Percent change vs the previous period, or null when it has no basis.
  double? _delta(num current, num previous) =>
      previous == 0 ? null : (current - previous) / previous * 100;

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return ColoredBox(
      color: AppDesignTokens.background,
      child: Column(
        children: [
          _topBar(context),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : (data == null
                      ? _errorState()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                            children: [
                              _hero(data),
                              const SizedBox(height: 16),
                              _paymentRow(data),
                              const SizedBox(height: 16),
                              _chartsRow(data),
                              const SizedBox(height: 16),
                              _transactions(data),
                            ],
                          ),
                        )),
          ),
        ],
      ),
    );
  }

  Widget _errorState() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.lock_outline,
          size: 44,
          color: AppDesignTokens.textMuted,
        ),
        const SizedBox(height: 12),
        Text(
          _error ?? 'Données indisponibles',
          style: const TextStyle(color: AppDesignTokens.textSecondary),
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _load, child: const Text('Réessayer')),
      ],
    ),
  );

  // ── top bar ──────────────────────────────────────────────────────────────

  Widget _topBar(BuildContext context) {
    String date;
    try {
      date = DateFormat('EEEE, d MMMM y', 'fr').format(DateTime.now());
    } catch (_) {
      date = DateFormat('EEEE, d MMMM y').format(DateTime.now());
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
              constraints: const BoxConstraints(maxWidth: 780),
              decoration: BoxDecoration(
                color: AppDesignTokens.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppDesignTokens.border),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  const Icon(
                    Icons.search,
                    size: 20,
                    color: AppDesignTokens.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onSubmitted: (v) => widget.onSearch?.call(v.trim()),
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        hintText:
                            'Rechercher un produit, un code-barres ou une transaction...',
                        hintStyle: TextStyle(
                          color: AppDesignTokens.textSecondary,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppDesignTokens.surfaceHighlight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Entrée',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          const Icon(
            Icons.calendar_today_outlined,
            size: 18,
            color: AppDesignTokens.textSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            toBeginningOfSentenceCase(date),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _load,
            icon: const Icon(
              Icons.refresh,
              color: AppDesignTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ── hero ─────────────────────────────────────────────────────────────────

  Widget _hero(DashboardSummary d) {
    final revenue = d.current.netSales;
    final revDelta = _delta(
      d.current.netSales.millimes,
      d.previous.netSales.millimes,
    );
    final basketDelta = _delta(
      d.averageBasket.millimes,
      d.previous.totalSalesCount == 0
          ? 0
          : d.previous.netSales.millimes / d.previous.totalSalesCount,
    );
    final marginDelta = d.previous.netSales.millimes == 0
        ? null
        : d.current.grossMarginPercent - d.previous.grossMarginPercent;
    final label = _days == 1 ? "aujourd'hui" : 'sur $_days jours';

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_greenDark, Color(0xFF1A7A47)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -60,
              top: -80,
              child: _circle(300, 0.06),
            ),
            Positioned(
              right: 160,
              bottom: -120,
              child: _circle(260, 0.05),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 26),
              child: LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth > 900;
                  final left = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "CHIFFRE D'AFFAIRES ${_days == 1 ? "AUJOURD'HUI" : 'SUR $_days JOURS'}",
                        style: const TextStyle(
                          color: Color(0xFFA7E3BE),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _fmt(revenue),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 46,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (revDelta != null)
                        _trendPill(revDelta, 'par rapport à ${_days == 1 ? 'hier' : 'la période précédente'}'),
                    ],
                  );
                  final stats = Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _heroStat(
                        Icons.shopping_bag_outlined,
                        'Ventes',
                        '${d.current.totalSalesCount}',
                        sub: label,
                      ),
                      _vDivider(),
                      _heroStat(
                        Icons.bar_chart,
                        'Panier Moyen',
                        _fmt(d.averageBasket),
                        delta: basketDelta,
                      ),
                      _vDivider(),
                      _heroStat(
                        Icons.pie_chart_outline,
                        'Marge',
                        '${d.current.grossMarginPercent.toStringAsFixed(1)}%',
                        delta: marginDelta,
                        deltaIsPoints: true,
                      ),
                    ],
                  );
                  return wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(flex: 5, child: left),
                            Expanded(flex: 6, child: Align(
                              alignment: Alignment.centerRight,
                              child: stats,
                            )),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [left, const SizedBox(height: 20), stats],
                        );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circle(double size, double alpha) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: alpha),
    ),
  );

  Widget _vDivider() => Container(
    width: 1,
    height: 92,
    margin: const EdgeInsets.symmetric(horizontal: 28),
    color: Colors.white.withValues(alpha: 0.18),
  );

  Widget _trendPill(double pct, String suffix) {
    final up = pct >= 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                up ? Icons.trending_up : Icons.trending_down,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                '${up ? '+' : ''}${pct.toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            suffix,
            style: const TextStyle(color: Color(0xFFD2F0DE), fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _heroStat(
    IconData icon,
    String label,
    String value, {
    String? sub,
    double? delta,
    bool deltaIsPoints = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(color: Color(0xFFD2F0DE), fontSize: 14),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (sub != null)
          Text(
            sub,
            style: const TextStyle(color: Color(0xFFD2F0DE), fontSize: 13),
          ),
        if (delta != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${delta >= 0 ? '↗ +' : '↘ '}${delta.toStringAsFixed(delta.abs() < 10 ? 1 : 0)}${deltaIsPoints ? ' pts' : '%'}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── payment cards + stock alert ──────────────────────────────────────────

  Widget _paymentRow(DashboardSummary d) {
    final total = d.current.netSales.millimes;
    Money by(String m) => d.current.salesByPaymentMethod[m] ?? Money.zero;
    int pct(Money m) {
      final sum = d.current.salesByPaymentMethod.values.fold<int>(
        0,
        (a, b) => a + b.millimes,
      );
      return sum == 0 ? 0 : (m.millimes * 100 / sum).round();
    }

    final cash = by(AppConstants.paymentCash);
    final card = by(AppConstants.paymentCard);
    final out = d.stock.outOfStockCount;
    final low = d.stock.lowStockCount;
    final alert = out + low > 0;
    final hasRevenue = total != 0;
    return LayoutBuilder(
      builder: (context, c) {
        final cards = [
          _payCard(Icons.payments_outlined, 'Espèces', cash, hasRevenue ? pct(cash) : 0),
          _payCard(Icons.credit_card, 'Carte / TPE', card, hasRevenue ? pct(card) : 0),
          _stockCard(alert, out, low),
        ];
        if (c.maxWidth < 900) {
          return Column(
            children: [
              for (final w in cards) ...[w, const SizedBox(height: 12)],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 5, child: cards[0]),
              const SizedBox(width: 16),
              Expanded(flex: 5, child: cards[1]),
              const SizedBox(width: 16),
              Expanded(flex: 6, child: cards[2]),
            ],
          ),
        );
      },
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding, Color? color, Color? border, VoidCallback? onTap}) {
    return Material(
      color: color ?? AppDesignTokens.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: padding ?? const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border ?? AppDesignTokens.border),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _payCard(IconData icon, String label, Money amount, int pct) {
    return _card(
      onTap: widget.onViewSales,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppDesignTokens.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: _green, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppDesignTokens.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _fmt(amount),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppDesignTokens.primarySoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '$pct%',
              style: const TextStyle(
                color: _green,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: AppDesignTokens.textSecondary),
        ],
      ),
    );
  }

  Widget _stockCard(bool alert, int out, int low) {
    final color = alert ? AppDesignTokens.danger : _green;
    return _card(
      onTap: widget.onViewStock,
      color: alert ? const Color(0xFFFEF2F2) : AppDesignTokens.primarySoft,
      border: alert ? const Color(0xFFFECACA) : AppDesignTokens.primarySoftBorder,
      child: Row(
        children: [
          Icon(
            alert ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            color: color,
            size: 36,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert
                      ? '$out rupture(s) et $low stock(s) critique(s) détectés.'
                      : 'Stocks en bon état.',
                  style: TextStyle(
                    color: alert ? const Color(0xFF991B1B) : const Color(0xFF166534),
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  alert
                      ? 'Vérifiez vos stocks pour éviter les ruptures.'
                      : 'Aucune rupture ni stock critique.',
                  style: const TextStyle(
                    color: AppDesignTokens.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: color),
        ],
      ),
    );
  }

  // ── charts ───────────────────────────────────────────────────────────────

  Widget _chartsRow(DashboardSummary d) {
    final bars = _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            Icons.bar_chart,
            'Ventes de la journée',
            _periodPicker(_days, (v) {
              setState(() => _days = v);
              _load();
            }),
          ),
          const SizedBox(height: 14),
          SizedBox(height: 230, child: _BarChart(buckets: d.buckets)),
        ],
      ),
    );
    final donut = _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            Icons.pie_chart,
            'Répartition des paiements',
            Text(
              _days == 1 ? "Aujourd'hui" : '$_days jours',
              style: const TextStyle(
                fontSize: 13,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(height: 230, child: _paymentDonut(d)),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 1000) {
          return Column(children: [bars, const SizedBox(height: 16), donut]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: bars),
            const SizedBox(width: 16),
            Expanded(flex: 4, child: donut),
          ],
        );
      },
    );
  }

  Widget _cardHeader(IconData icon, String title, Widget trailing) => Row(
    children: [
      Icon(icon, color: _green, size: 24),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppDesignTokens.textPrimary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing,
    ],
  );

  Widget _periodPicker(int value, ValueChanged<int> onChanged) {
    return PopupMenuButton<int>(
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => const [
        PopupMenuItem(value: 1, child: Text("Aujourd'hui")),
        PopupMenuItem(value: 7, child: Text('7 jours')),
        PopupMenuItem(value: 30, child: Text('30 jours')),
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
            Text(
              value == 1 ? "Aujourd'hui" : '$value jours',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_down, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _paymentDonut(DashboardSummary d) {
    final entries = d.current.salesByPaymentMethod.entries
        .where((e) => e.value.millimes > 0)
        .toList();
    final sum = entries.fold<int>(0, (a, e) => a + e.value.millimes);
    final palette = [_green, const Color(0xFF9BDDB5), const Color(0xFF2563EB), const Color(0xFFF59E0B)];
    return Row(
      children: [
        SizedBox(
          width: 190,
          height: 190,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(190, 190),
                painter: _DonutPainter(
                  values: [for (final e in entries) e.value.millimes.toDouble()],
                  colors: palette,
                  emptyColor: AppDesignTokens.primarySoft,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    d.current.netSales.format(includeCurrency: false),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const Text('TND', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: entries.isEmpty
              ? const Text('Aucune vente', style: TextStyle(color: AppDesignTokens.textSecondary))
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < entries.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: palette[i % palette.length],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                paymentMethodLabel(entries[i].key),
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              _fmt(entries[i].value),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 40,
                              child: Text(
                                '${(entries[i].value.millimes * 100 / sum).round()}%',
                                textAlign: TextAlign.end,
                                style: const TextStyle(fontSize: 13, color: AppDesignTokens.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  // ── transactions ─────────────────────────────────────────────────────────

  Widget _transactions(DashboardSummary d) {
    const head = TextStyle(fontSize: 13, color: AppDesignTokens.textSecondary);
    return _card(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long, color: _green, size: 24),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Dernières Transactions',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              OutlinedButton(
                onPressed: widget.onViewSales,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: const BorderSide(color: AppDesignTokens.border),
                  foregroundColor: AppDesignTokens.textPrimary,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Voir toutes les ventes'),
                    SizedBox(width: 6),
                    Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppDesignTokens.surfaceSecondary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                SizedBox(width: 96),
                Expanded(flex: 4, child: Text('# Reçu', style: head)),
                Expanded(flex: 2, child: Text('Heure', style: head)),
                Expanded(flex: 2, child: Text('Articles', style: head)),
                Expanded(flex: 3, child: Text('Méthode de paiement', style: head)),
                Expanded(flex: 3, child: Text('Montant', style: head)),
                Expanded(flex: 3, child: Text('Statut', style: head)),
                SizedBox(width: 20),
              ],
            ),
          ),
          if (d.recent.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  'Aucune transaction pour le moment.',
                  style: TextStyle(color: AppDesignTokens.textSecondary),
                ),
              ),
            )
          else
            for (final t in d.recent) _txRow(t),
        ],
      ),
    );
  }

  Widget _txRow(DashboardTransaction t) {
    final refunded = t.status == AppConstants.saleRefunded ||
        t.status == AppConstants.salePartiallyRefunded;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OrderDetailsScreen(saleId: t.saleId),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppDesignTokens.borderSubtle),
          ),
        ),
        child: Row(
          children: [
            SizedBox(width: 96, child: _thumbs(t.imageUrls)),
            Expanded(
              flex: 4,
              child: Text(
                t.receiptNumber,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                DateFormat('HH:mm').format(t.time),
                style: const TextStyle(
                  color: AppDesignTokens.textSecondary,
                  fontSize: 14,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '${t.itemCount} article${t.itemCount > 1 ? 's' : ''}',
                style: const TextStyle(
                  color: AppDesignTokens.textSecondary,
                  fontSize: 14,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Icon(paymentMethodIcon(t.paymentMethod), size: 18, color: _green),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      paymentMethodLabel(t.paymentMethod),
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                '${t.total.isNegative ? '' : '+'}${_fmt(t.total)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: refunded ? AppDesignTokens.danger : _green,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SaleStatusChip(t.status),
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
    );
  }

  /// Up to three overlapping product photos, with a "+n" badge for the rest.
  Widget _thumbs(List<String?> urls) {
    const size = 40.0, overlap = 24.0;
    final shown = urls.take(3).toList();
    final extra = urls.length - shown.length;
    return SizedBox(
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * overlap,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ProductThumbnail(
                    imageUrl: shown[i],
                    size: size - 4,
                    borderRadius: 0,
                  ),
                ),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * overlap + 2,
              top: 10,
              child: Text(
                '+$extra',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── charts ───────────────────────────────────────────────────────────────────

class _BarChart extends StatelessWidget {
  final List<DashboardBucket> buckets;
  const _BarChart({required this.buckets});

  @override
  Widget build(BuildContext context) {
    final maxV = buckets.fold<int>(0, (a, b) => math.max(a, b.millimes));
    return CustomPaint(
      painter: _BarPainter(buckets: buckets, maxValue: maxV),
      child: const SizedBox.expand(),
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<DashboardBucket> buckets;
  final int maxValue;
  _BarPainter({required this.buckets, required this.maxValue});

  /// A tidy axis ceiling (1, 2, 5 × 10^n) in TND.
  double _niceMax(double v) {
    if (v <= 0) return 100;
    final pow10 = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final m in [1, 2, 2.5, 5, 10]) {
      if (v <= m * pow10) return m * pow10;
    }
    return 10 * pow10;
  }

  String _tick(double tnd) => tnd >= 1000 ? '${(tnd / 1000).toStringAsFixed(tnd % 1000 == 0 ? 0 : 1)}K' : tnd.toStringAsFixed(0);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 46.0, bottom = 26.0;
    final plot = Rect.fromLTWH(left, 4, size.width - left, size.height - bottom - 4);
    final top = _niceMax(maxValue / 1000);
    final grid = Paint()
      ..color = AppDesignTokens.border
      ..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    const ticks = 3;
    for (var i = 0; i <= ticks; i++) {
      final y = plot.bottom - plot.height * i / ticks;
      // dashed gridline
      for (var x = plot.left; x < plot.right; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, plot.right), y), grid);
      }
      tp.text = TextSpan(
        text: _tick(top * i / ticks),
        style: const TextStyle(fontSize: 11, color: AppDesignTokens.textSecondary),
      );
      tp.layout();
      tp.paint(canvas, Offset(left - 8 - tp.width, y - tp.height / 2));
    }
    if (buckets.isEmpty) return;
    final slot = plot.width / buckets.length;
    final barW = math.min(slot * 0.55, 26.0);
    final paint = Paint()..color = const Color(0xFF8FD6AC);
    final every = buckets.length > 16 ? (buckets.length / 8).ceil() : (buckets.length > 9 ? 2 : 1);
    for (var i = 0; i < buckets.length; i++) {
      final h = plot.height * (buckets[i].millimes / 1000) / top;
      final cx = plot.left + slot * i + slot / 2;
      if (h > 0) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(cx - barW / 2, plot.bottom - h, barW, h),
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3),
          ),
          paint,
        );
      }
      if (i % every == 0) {
        tp.text = TextSpan(
          text: buckets[i].label,
          style: const TextStyle(fontSize: 11, color: AppDesignTokens.textSecondary),
        );
        tp.layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, plot.bottom + 8));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.buckets != buckets || old.maxValue != maxValue;
}

class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final Color emptyColor;
  _DonutPainter({required this.values, required this.colors, required this.emptyColor});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 22.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) {
      canvas.drawArc(rect, 0, math.pi * 2, false, base..color = emptyColor);
      return;
    }
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      canvas.drawArc(rect, start, sweep, false, base..color = colors[i % colors.length]);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.values != values;
}
