import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/ui/widgets/common/code128_barcode.dart';

void main() {
  test('every pattern is 11 modules wide and the table is complete', () {
    expect(Code128.patterns, hasLength(106));
    for (final p in Code128.patterns) {
      expect(p.length, 6);
      expect(p.split('').map(int.parse).reduce((a, b) => a + b), 11, reason: p);
    }
    expect(Code128.patterns.toSet(), hasLength(106));
  });

  test('checksum is (start + sum of value*position) mod 103', () {
    // 104 + 48*1 + 42*2 + 42*3 + 17*4 + 18*5 + 19*6 + 35*7 = 879; 879 % 103 = 55.
    expect(Code128.symbols('PJJ123C').last, 55);
  });

  test('encoded width: 11 per symbol plus 13 for the stop', () {
    final m = Code128.modules('REC-1');
    expect(m.reduce((a, b) => a + b), 11 * (1 + 5 + 1) + 13);
  });

  test('rejects non-ASCII', () {
    expect(Code128.canEncode('é'), isFalse);
    expect(Code128.canEncode('REC-20261022-70825'), isTrue);
  });
}
