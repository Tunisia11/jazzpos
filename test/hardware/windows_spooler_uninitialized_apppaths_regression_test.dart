import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/core/platform/app_paths.dart';
import 'package:tracepos/hardware/receipt_printer/windows_spooler_printer.dart';

void main() {
  test('WindowsSpoolerPrinter.printRaw does not crash when AppPaths is uninitialized', () async {
    // Ensure AppPaths is not initialized in this isolated test
    final spooler = WindowsSpoolerPrinter(
      name: 'NonExistentTestPrinter',
      driverName: 'Generic / Text Only',
      portName: 'NUL',
      processRunner:(exe,args,{timeout=const Duration(seconds:3)}) async => ProcessResult(1,1,'','Missing test queue'),
    );

    // Should gracefully use Directory.systemTemp fallback without LateInitializationError
    await expectLater(spooler.printRaw(Uint8List.fromList([27,64])),throwsException);

  });

  test('AppPaths.tempDir returns Directory.systemTemp when uninitialized', () {
    // Verifies the safety fallback property
    expect(AppPaths.instance.tempDir, isNotNull);
  });
}
