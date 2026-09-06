import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/hardware/barcode_scanner/keyboard_barcode_scanner.dart';

void main() {
  test('rapid scanner burst completes on Enter', () {
    final input = BarcodeInputAccumulator();
    final start = DateTime(2026, 9, 6, 10);
    for (var index = 0; index < 13; index++) {
      input.addCharacter(
        '6191234567890'[index],
        start.add(Duration(milliseconds: index * 10)),
      );
    }
    expect(
      input.complete(start.add(const Duration(milliseconds: 135))),
      '6191234567890',
    );
  });

  test('ordinary typing is not misreported as a barcode scan', () {
    final input = BarcodeInputAccumulator();
    final start = DateTime(2026, 9, 6, 10);
    input.addCharacter('a', start);
    input.addCharacter('b', start.add(const Duration(milliseconds: 140)));
    input.addCharacter('c', start.add(const Duration(milliseconds: 280)));
    expect(
      input.complete(start.add(const Duration(milliseconds: 300))),
      isNull,
    );
  });

  test('short or unterminated bursts are rejected and cleared', () {
    final input = BarcodeInputAccumulator();
    final start = DateTime(2026, 9, 6, 10);
    input.addCharacter('1', start);
    input.addCharacter('2', start.add(const Duration(milliseconds: 10)));
    expect(input.complete(start.add(const Duration(milliseconds: 20))), isNull);
    expect(input.complete(start.add(const Duration(milliseconds: 30))), isNull);
  });
}
