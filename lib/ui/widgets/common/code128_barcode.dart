import 'package:flutter/material.dart';

/// Code 128 (set B) encoder: printable ASCII 32..126.
class Code128 {
  const Code128._();

  /// Bar/space widths for symbols 0..102, Start A/B/C (103..105).
  static const List<String> patterns = [
    '212222', '222122', '222221', '121223', '121322', '131222', '122213',
    '122312', '132212', '221213', '221312', '231212', '112232', '122132',
    '122231', '113222', '123122', '123221', '223211', '221132', '221231',
    '213212', '223112', '312131', '311222', '321122', '321221', '312212',
    '322112', '322211', '212123', '212321', '232121', '111323', '131123',
    '131321', '112313', '132113', '132311', '211313', '231113', '231311',
    '112133', '112331', '132131', '113123', '113321', '133121', '313121',
    '211331', '231131', '213113', '213311', '213131', '311123', '311321',
    '331121', '312113', '312311', '332111', '314111', '221411', '431111',
    '111224', '111422', '121124', '121421', '141122', '141221', '112214',
    '112412', '122114', '122411', '142112', '142211', '241211', '221114',
    '413111', '241112', '134111', '111242', '121142', '121241', '114212',
    '124112', '124211', '411212', '421112', '421211', '212141', '214121',
    '412121', '111143', '111341', '131141', '114113', '114311', '411113',
    '411311', '113141', '114131', '311141', '411131', '211412', '211214',
    '211232',
  ];
  static const String stop = '2331112';
  static const int startB = 104;

  /// Whether [data] can be encoded.
  static bool canEncode(String data) =>
      data.isNotEmpty && data.codeUnits.every((c) => c >= 32 && c <= 126);

  /// Symbol values including start, checksum and stop-less data.
  static List<int> symbols(String data) {
    final values = [startB, for (final c in data.codeUnits) c - 32];
    var sum = startB;
    for (var i = 1; i < values.length; i++) {
      sum += values[i] * i;
    }
    return [...values, sum % 103];
  }

  /// Alternating bar/space module widths, starting with a bar.
  static List<int> modules(String data) {
    final out = <int>[];
    for (final s in symbols(data)) {
      out.addAll(patterns[s].split('').map(int.parse));
    }
    out.addAll(stop.split('').map(int.parse));
    return out;
  }
}

/// Draws a scannable Code 128 barcode filling its box.
class Code128Barcode extends StatelessWidget {
  const Code128Barcode({
    super.key,
    required this.data,
    this.height = 56,
    this.color = const Color(0xFF111827),
  });

  final String data;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (!Code128.canEncode(data)) return SizedBox(height: height);
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _Code128Painter(Code128.modules(data), color),
        size: Size.infinite,
      ),
    );
  }
}

class _Code128Painter extends CustomPainter {
  _Code128Painter(this.modules, this.color);

  final List<int> modules;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final total = modules.fold<int>(0, (a, b) => a + b);
    final unit = size.width / total;
    final paint = Paint()..color = color;
    var x = 0.0;
    for (var i = 0; i < modules.length; i++) {
      final w = modules[i] * unit;
      if (i.isEven) {
        canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), paint);
      }
      x += w;
    }
  }

  @override
  bool shouldRepaint(_Code128Painter old) =>
      old.modules != modules || old.color != color;
}
