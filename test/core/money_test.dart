import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/money/money.dart';

void main() {
  group('Money Value Object Tests', () {
    test('Construct from millimes and TND correctly', () {
      final m1 = Money.fromMillimes(12500);
      expect(m1.millimes, 12500);
      expect(m1.format(), '12.500 TND');

      final m2 = Money.fromTnd(39, 900);
      expect(m2.millimes, 39900);
      expect(m2.format(), '39.900 TND');

      final m3 = Money.fromTnd(120);
      expect(m3.millimes, 120000);
      expect(m3.format(), '120.000 TND');

      final m4 = Money.fromMillimes(500);
      expect(m4.millimes, 500);
      expect(m4.format(), '0.500 TND');
    });

    test(
      'Strict 3 decimal string formatting without floating point errors',
      () {
        expect(Money.fromMillimes(0).format(), '0.000 TND');
        expect(Money.fromMillimes(5).format(), '0.005 TND');
        expect(Money.fromMillimes(50).format(), '0.050 TND');
        expect(Money.fromMillimes(500).format(), '0.500 TND');
        expect(Money.fromMillimes(1000).format(), '1.000 TND');
        expect(Money.fromMillimes(1542500).format(), '1,542.500 TND');
        expect(Money.fromMillimes(-2500).format(), '-2.500 TND');
      },
    );

    test('Parsing user inputs accurately', () {
      expect(Money.parse('12.500').millimes, 12500);
      expect(Money.parse('12.5').millimes, 12500);
      expect(Money.parse('12.05').millimes, 12050);
      expect(Money.parse('12').millimes, 12000);
      expect(Money.parse('12,500 TND').millimes, 12500);
      expect(Money.parse('39.900 DT').millimes, 39900);
      expect(Money.parse('0.5').millimes, 500);
      expect(Money.parse('-10.250').millimes, -10250);
      expect(Money.parse('').millimes, 0);
    });

    test('Arithmetic operations preserve exact integer millimes', () {
      final a = Money.fromMillimes(12500);
      final b = Money.fromMillimes(39900);

      expect((a + b).millimes, 52400);
      expect((b - a).millimes, 27400);
      expect((a * 3).millimes, 37500);
      expect((b * 2).millimes, 79800);
    });

    test('Discount percentage calculation with half-up rounding', () {
      // 100.000 TND with 20% discount = 20.000 TND discount
      final price = Money.fromMillimes(100000);
      final discount = price.percentageDiscount(20);
      expect(discount.millimes, 20000);
      expect(price.applyPercentageDiscount(20).millimes, 80000);

      // 39.900 TND with 15% discount: 39900 * 0.15 = 5985 millimes
      final p2 = Money.fromMillimes(39900);
      expect(p2.percentageDiscount(15).millimes, 5985);
      expect(p2.applyPercentageDiscount(15).millimes, 33915);
      expect(p2.applyPercentageDiscount(15).format(), '33.915 TND');

      // Odd rounding check: 10.005 TND with 33.333%
      final p3 = Money.fromMillimes(10005);
      final disc3 = p3.percentageDiscount(33.333);
      expect(disc3.millimes, 3335);
    });

    test('Comparison and equality operators', () {
      final m1 = Money.fromMillimes(10000);
      final m2 = Money.fromMillimes(10000);
      final m3 = Money.fromMillimes(20000);

      expect(m1 == m2, isTrue);
      expect(m1 < m3, isTrue);
      expect(m3 > m1, isTrue);
      expect(m1 <= m2, isTrue);
      expect(m1 >= m2, isTrue);
      expect(m1.compareTo(m3), -1);
      expect(m3.compareTo(m1), 1);
      expect(m1.compareTo(m2), 0);
    });
  });
}
