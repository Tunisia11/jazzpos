import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tracepos/ui/theme/app_design_tokens.dart';

/// Small filled line used inside KPI cards.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _SparkPainter(values, color), size: Size.infinite);
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final span = hi - lo == 0 ? 1.0 : hi - lo;
    Offset at(int i) => Offset(
      size.width * i / (values.length - 1),
      size.height - 3 - (size.height - 6) * ((values[i] - lo) / span),
    );
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      final a = at(i - 1);
      final b = at(i);
      final mid = (a.dx + b.dx) / 2;
      line.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values != values || old.color != color;
}

/// One slice of the payment donut.
class DonutSlice {
  const DonutSlice(this.value, this.color);
  final double value;
  final Color color;
}

class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    this.thickness = 22,
    this.center,
  });

  final List<DonutSlice> slices;
  final double thickness;
  final Widget? center;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DonutPainter(slices, thickness),
    child: Center(child: center),
  );
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices, this.thickness);

  final List<DonutSlice> slices;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final box = rect.deflate(thickness / 2);
    final total = slices.fold<double>(0, (a, s) => a + s.value);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..color = AppDesignTokens.primarySoft;
    if (total <= 0) {
      canvas.drawArc(box, 0, math.pi * 2, false, base);
      return;
    }
    var angle = -math.pi / 2;
    for (final s in slices.where((s) => s.value > 0)) {
      final sweep = s.value / total * math.pi * 2;
      canvas.drawArc(
        box,
        angle,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness
          ..color = s.color,
      );
      angle += sweep;
    }
    // Thin separators so adjacent slices read clearly.
    if (slices.where((s) => s.value > 0).length > 1) {
      angle = -math.pi / 2;
      for (final s in slices.where((s) => s.value > 0)) {
        final r1 = box.width / 2 - thickness / 2;
        final r2 = box.width / 2 + thickness / 2;
        final c = box.center;
        canvas.drawLine(
          c + Offset(math.cos(angle), math.sin(angle)) * r1,
          c + Offset(math.cos(angle), math.sin(angle)) * r2,
          Paint()
            ..color = Colors.white
            ..strokeWidth = 2,
        );
        angle += s.value / total * math.pi * 2;
      }
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.slices != slices || old.thickness != thickness;
}

/// One x-axis point of [TrendChart].
class TrendChartPoint {
  const TrendChartPoint(this.label, this.value);
  final String label;
  final double value; // TND
}

/// Smooth area line chart with y-axis labels and a hover tooltip.
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.points,
    required this.format,
    this.tooltipLabel,
  });

  final List<TrendChartPoint> points;

  /// Formats a value for the tooltip (e.g. "145.000 TND").
  final String Function(double) format;

  /// Longer label for the tooltip header; defaults to the point label.
  final String Function(int index)? tooltipLabel;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  int? _hover;

  int get _peak {
    var best = 0;
    for (var i = 1; i < widget.points.length; i++) {
      if (widget.points[i].value > widget.points[best].value) best = i;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    if (pts.length < 2) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        final geo = _ChartGeometry(pts, Size(c.maxWidth, c.maxHeight));
        final shown = _hover ?? _peak;
        final p = geo.offsetOf(shown);
        return MouseRegion(
          onHover: (e) => setState(() => _hover = geo.nearest(e.localPosition.dx)),
          onExit: (_) => setState(() => _hover = null),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _TrendPainter(geo, shown)),
              ),
              Positioned(
                left: (p.dx - 62).clamp(0.0, math.max(0.0, c.maxWidth - 124)),
                top: math.max(0.0, p.dy - 56),
                child: IgnorePointer(
                  child: Container(
                    width: 124,
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.format(pts[shown].value),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.tooltipLabel?.call(shown) ?? pts[shown].label,
                          style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChartGeometry {
  _ChartGeometry(this.points, this.size) {
    final values = points.map((p) => p.value);
    final hi = values.reduce(math.max);
    final lo = math.min(0.0, values.reduce(math.min));
    final step = _niceStep((hi - lo) <= 0 ? 1 : (hi - lo) / 4);
    top = (hi / step).ceil() * step;
    if (top <= lo) top = lo + step;
    bottom = lo;
    plot = Rect.fromLTRB(46, 46, size.width - 8, size.height - 26);
    ticks = [
      for (var v = bottom; v <= top + step / 2; v += step) v,
    ];
  }

  final List<TrendChartPoint> points;
  final Size size;
  late final double top;
  late final double bottom;
  late final Rect plot;
  late final List<double> ticks;

  static double _niceStep(double raw) {
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final n = raw / mag;
    final nice = n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10;
    return nice * mag;
  }

  double x(int i) => plot.left + plot.width * i / (points.length - 1);
  double y(double v) =>
      plot.bottom - plot.height * ((v - bottom) / (top - bottom));
  Offset offsetOf(int i) => Offset(x(i), y(points[i].value));

  int nearest(double dx) {
    final t = ((dx - plot.left) / plot.width).clamp(0.0, 1.0);
    return (t * (points.length - 1)).round();
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.g, this.selected);

  final _ChartGeometry g;
  final int selected;

  static String _short(double v) {
    final a = v.abs();
    if (a >= 1000000) return '${(v / 1000000).toStringAsFixed(a % 1000000 == 0 ? 0 : 1)}M';
    if (a >= 1000) return '${(v / 1000).toStringAsFixed(a % 1000 == 0 ? 0 : 1)}K';
    return v.toStringAsFixed(0);
  }

  void _text(Canvas canvas, String s, Offset at, {TextAlign align = TextAlign.right}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: const TextStyle(fontSize: 10.5, color: AppDesignTokens.textSecondary),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = align == TextAlign.right ? at.dx - tp.width : at.dx - tp.width / 2;
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..strokeWidth = 1;
    for (final t in g.ticks) {
      final y = g.y(t);
      canvas.drawLine(Offset(g.plot.left, y), Offset(g.plot.right, y), grid);
      _text(canvas, _short(t), Offset(g.plot.left - 8, y));
    }
    final n = g.points.length;
    final every = math.max(1, (n / 7).ceil());
    for (var i = 0; i < n; i += every) {
      _text(canvas, g.points[i].label, Offset(g.x(i), g.plot.bottom + 14),
          align: TextAlign.center);
    }

    final line = Path()..moveTo(g.x(0), g.y(g.points[0].value));
    for (var i = 1; i < n; i++) {
      final a = g.offsetOf(i - 1);
      final b = g.offsetOf(i);
      final mid = (a.dx + b.dx) / 2;
      line.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    final area = Path.from(line)
      ..lineTo(g.x(n - 1), g.y(math.max(0, g.bottom)))
      ..lineTo(g.x(0), g.y(math.max(0, g.bottom)))
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppDesignTokens.primary.withValues(alpha: 0.28),
            AppDesignTokens.primary.withValues(alpha: 0.02),
          ],
        ).createShader(g.plot),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = AppDesignTokens.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    // Dots every few points, plus the selected one with a guide line.
    final dot = Paint()..color = AppDesignTokens.primary;
    final ring = Paint()..color = Colors.white;
    for (var i = 0; i < n; i += every) {
      final o = g.offsetOf(i);
      canvas.drawCircle(o, 4, ring);
      canvas.drawCircle(o, 3, dot);
    }
    final s = g.offsetOf(selected);
    canvas.drawLine(
      Offset(s.dx, s.dy),
      Offset(s.dx, g.plot.bottom),
      Paint()
        ..color = AppDesignTokens.primary.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(s, 6, ring);
    canvas.drawCircle(s, 4.5, dot);
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.g != g || old.selected != selected;
}
