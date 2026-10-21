import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/money/money.dart';

/// Helper to simulate the exact numpad logic used in PaymentDialog
class KeypadSimulator {
  final StringBuffer _buffer = StringBuffer();

  String get text => _buffer.toString();

  void press(String char) {
    final cur = _buffer.toString();
    final normalized = char == ',' ? '.' : char;

    // 1. Decimal point validation
    if (normalized == '.') {
      if (cur.contains('.')) {
        return; // Reject duplicate decimal point
      }
      if (cur.isEmpty) {
        _buffer.write('0.');
      } else {
        _buffer.write('.');
      }
      return;
    }

    // 2. Double-zero '00' validation
    if (normalized == '00') {
      if (cur.contains('.')) {
        final parts = cur.split('.');
        final decimals = parts.length > 1 ? parts[1] : '';
        if (decimals.length >= 3) return;
        if (decimals.length == 2) {
          _buffer.write('0');
          return;
        }
        if (decimals.length <= 1) {
          _buffer.write('00');
          return;
        }
      } else {
        if (cur.isNotEmpty && cur != '0') {
          _buffer.write('00');
        }
      }
      return;
    }

    // 3. Numeric digits (0-9)
    if (RegExp(r'^[0-9]$').hasMatch(normalized)) {
      if (cur == '0' && normalized != '0') {
        _buffer.clear();
        _buffer.write(normalized);
        return;
      }
      if (cur == '0' && normalized == '0') {
        return; // Prevent multiple leading zeros
      }
      if (cur.contains('.')) {
        final parts = cur.split('.');
        if (parts.length > 1 && parts[1].length >= 3) {
          return; // Max 3 decimal places for TND millimes
        }
      }
      _buffer.write(normalized);
    }
  }

  void backspace() {
    if (_buffer.isNotEmpty) {
      final cur = _buffer.toString();
      _buffer.clear();
      _buffer.write(cur.substring(0, cur.length - 1));
    }
  }

  void clear() {
    _buffer.clear();
  }

  Money tenderedAmount(Money totalAmount) {
    final t = _buffer.toString().trim();
    if (t.isEmpty) return totalAmount;
    final parsed = Money.tryParse(t);
    if (parsed != null) return parsed;
    if (t == '.' || t == ',') return Money.zero;
    if (t.endsWith('.') || t.endsWith(',')) {
      final stripped = t.substring(0, t.length - 1);
      return Money.tryParse(stripped) ?? Money.zero;
    }
    return Money.zero;
  }
}

void main() {
  group('Payment Keypad & Safe Money Parsing Tests', () {
    test('Money.tryParse never throws on malformed input strings', () {
      expect(Money.tryParse('.'), Money.zero);
      expect(Money.tryParse('..'), isNull);
      expect(Money.tryParse('1..2'), isNull);
      expect(Money.tryParse('1.2.3'), isNull);
      expect(Money.tryParse('1.2345'), isNull);
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse('   '), isNull);
    });

    test('Money.tryParse correctly parses valid TND currency amounts', () {
      expect(Money.tryParse('12.500')?.millimes, 12500);
      expect(Money.tryParse('12.5')?.millimes, 12500);
      expect(Money.tryParse('12.05')?.millimes, 12050);
      expect(Money.tryParse('12')?.millimes, 12000);
      expect(Money.tryParse('0.005')?.millimes, 5);
      expect(Money.tryParse('100')?.millimes, 100000);
    });

    test('Pressing decimal on empty buffer produces "0."', () {
      final keypad = KeypadSimulator();
      keypad.press('.');
      expect(keypad.text, '0.');
      expect(keypad.tenderedAmount(const Money.fromMillimes(10000)), Money.zero);
    });

    test('Duplicate decimal points are rejected', () {
      final keypad = KeypadSimulator();
      keypad.press('1');
      keypad.press('.');
      keypad.press('.');
      keypad.press('2');
      keypad.press('.');
      expect(keypad.text, '1.2');
      expect(keypad.tenderedAmount(const Money.fromMillimes(10000)).millimes, 1200);
    });

    test('Comma is normalized to decimal point', () {
      final keypad = KeypadSimulator();
      keypad.press('5');
      keypad.press(',');
      keypad.press('5');
      expect(keypad.text, '5.5');
      expect(keypad.tenderedAmount(const Money.fromMillimes(10000)).millimes, 5500);
    });

    test('Multiple leading zeros are prevented', () {
      final keypad = KeypadSimulator();
      keypad.press('0');
      keypad.press('0');
      keypad.press('0');
      expect(keypad.text, '0');

      keypad.press('5');
      expect(keypad.text, '5');
    });

    test('Decimals are capped at exactly 3 digits for TND millimes', () {
      final keypad = KeypadSimulator();
      keypad.press('1');
      keypad.press('2');
      keypad.press('.');
      keypad.press('3');
      keypad.press('4');
      keypad.press('5');
      expect(keypad.text, '12.345');

      // Attempt to type a 4th decimal digit
      keypad.press('6');
      expect(keypad.text, '12.345', reason: '4th decimal digit must be rejected');
      expect(keypad.tenderedAmount(const Money.fromMillimes(10000)).millimes, 12345);
    });

    test('Double-zero key caps correctly at 3 decimals', () {
      final keypad = KeypadSimulator();
      keypad.press('1');
      keypad.press('.');
      keypad.press('5');
      keypad.press('00');
      expect(keypad.text, '1.500');

      // Attempting '00' when already at 3 decimals does nothing
      keypad.press('00');
      expect(keypad.text, '1.500');
    });

    test('Backspace and clear work as expected', () {
      final keypad = KeypadSimulator();
      keypad.press('5');
      keypad.press('0');
      expect(keypad.text, '50');

      keypad.backspace();
      expect(keypad.text, '5');

      keypad.clear();
      expect(keypad.text, '');
      // When empty, defaults to totalAmount
      expect(keypad.tenderedAmount(const Money.fromMillimes(25000)).millimes, 25000);
    });
  });
}
