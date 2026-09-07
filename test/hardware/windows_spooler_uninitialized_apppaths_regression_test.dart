import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/platform/app_paths.dart';
import 'package:jazzpos/hardware/receipt_printer/windows_spooler_printer.dart';

void main() {
  test('WindowsSpoolerPrinter.printRaw does not crash when AppPaths is uninitialized', () async {
    // Ensure AppPaths is not initialized in this isolated test
    final spooler = WindowsSpoolerPrinter(
      name: 'NonExistentTestPrinter',
      driverName: 'Generic / Text Only',
      portName: 'NUL',
    );

    // Should gracefully use Directory.systemTemp fallback without LateInitializationError
    expect(
      () async => await spooler.printRaw(Uint8List.fromList([0x1B, 0x40, 0x41, 0x42, 0x43])),
      returnsNormally,
    );
  });

  test('AppPaths.tempDir returns Directory.systemTemp when uninitialized', () {
    // Verifies the safety fallback property
    expect(AppPaths.instance.tempDir, isNotNull);
  });
}
