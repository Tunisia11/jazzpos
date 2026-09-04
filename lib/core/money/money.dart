import 'package:intl/intl.dart';

/// Canonical Money value object representing Tunisian Dinar (TND).
///
/// Internally stored in integer millimes (1 TND = 1000 millimes).
/// Calculations NEVER use floating point math for financial ledger accuracy.
/// All displays format strictly to 3 decimal places (e.g. 12.500 TND).
class Money implements Comparable<Money> {
  final int millimes;

  const Money._(this.millimes);

  /// Create Money from integer millimes
  const Money.fromMillimes(this.millimes);

  /// Create Money from whole TND (int or double) and optional millimes
  factory Money.fromTnd(num tnd, [int millimes = 0]) {
    if (tnd is int) {
      assert(millimes >= 0 && millimes < 1000, 'Millimes must be between 0 and 999');
      return Money.fromMillimes(tnd * 1000 + millimes);
    }
    return Money.fromMillimes((tnd * 1000).round() + millimes);
  }

  /// Create Money from a double representation of TND
  factory Money.fromDouble(double tnd) {
    return Money.fromMillimes((tnd * 1000).round());
  }

  /// Zero money constant
  static const Money zero = Money._(0);

  /// Parse user input or string into Money.
  /// Handles "12.500", "12.5", "12", "12,500", "12.500 TND", "12.500 DT"
  static Money parse(String input) {
    final cleaned = input
        .trim()
        .replaceAll('TND', '')
        .replaceAll('DT', '')
        .replaceAll('tnd', '')
        .replaceAll('dt', '')
        .replaceAll(' ', '')
        .replaceAll(',', '.');

    if (cleaned.isEmpty) {
      return Money.zero;
    }

    final isNeg = cleaned.startsWith('-');
    final absStr = isNeg ? cleaned.substring(1) : cleaned;

    final parts = absStr.split('.');
    final wholeStr = parts[0];
    final whole = int.tryParse(wholeStr) ?? 0;

    int milli = 0;
    if (parts.length > 1) {
      var fraction = parts[1];
      if (fraction.length > 3) {
        fraction = fraction.substring(0, 3);
      } else {
        fraction = fraction.padRight(3, '0');
      }
      milli = int.tryParse(fraction) ?? 0;
    }

    final total = whole * 1000 + milli;
    return Money.fromMillimes(isNeg ? -total : total);
  }

  /// Try parsing, return null on failure
  static Money? tryParse(String? input) {
    if (input == null || input.trim().isEmpty) return null;
    try {
      return parse(input);
    } catch (_) {
      return null;
    }
  }

  Money operator +(Money other) => Money.fromMillimes(millimes + other.millimes);

  Money operator -(Money other) => Money.fromMillimes(millimes - other.millimes);

  Money operator -() => Money.fromMillimes(-millimes);

  /// Multiply by integer or scalar with integer millimes half-up rounding
  Money operator *(num multiplier) {
    return Money.fromMillimes((millimes * multiplier).round());
  }

  /// Integer division
  Money operator ~/(int divisor) {
    return Money.fromMillimes(millimes ~/ divisor);
  }

  /// Division with rounding
  Money operator /(num divisor) {
    return Money.fromMillimes((millimes / divisor).round());
  }

  /// Calculate percentage discount (e.g. 20 for 20%) with integer rounding
  Money percentageDiscount(num percent) {
    final discountMillimes = ((millimes * percent) / 100).round();
    return Money.fromMillimes(discountMillimes);
  }

  /// Apply percentage discount and return remaining amount
  Money applyPercentageDiscount(num percent) {
    return this - percentageDiscount(percent);
  }

  bool get isZero => millimes == 0;
  bool get isNegative => millimes < 0;
  bool get isPositive => millimes > 0;

  Money get abs => Money.fromMillimes(millimes.abs());

  double toTndDouble() => millimes / 1000.0;

  /// Strict 3-decimal TND formatting: "12.500 TND"
  String format({bool includeCurrency = true, bool useGrouping = true}) {
    final absMillimes = millimes.abs();
    final whole = absMillimes ~/ 1000;
    final milli = absMillimes % 1000;
    final sign = millimes < 0 ? '-' : '';

    String wholeStr;
    if (useGrouping) {
      final formatter = NumberFormat('#,##0', 'en_US');
      wholeStr = formatter.format(whole);
    } else {
      wholeStr = whole.toString();
    }

    final milliStr = milli.toString().padLeft(3, '0');
    final formatted = '$sign$wholeStr.$milliStr';

    return includeCurrency ? '$formatted TND' : formatted;
  }

  @override
  int compareTo(Money other) => millimes.compareTo(other.millimes);

  bool operator <(Money other) => millimes < other.millimes;
  bool operator <=(Money other) => millimes <= other.millimes;
  bool operator >(Money other) => millimes > other.millimes;
  bool operator >=(Money other) => millimes >= other.millimes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Money && runtimeType == other.runtimeType && millimes == other.millimes;

  @override
  int get hashCode => millimes.hashCode;

  @override
  String toString() => format();
}
