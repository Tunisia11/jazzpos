// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/core/platform/app_paths.dart';
import 'package:tracepos/core/platform/export_diagnostic_report_service.dart';
import 'package:tracepos/hardware/hardware_manager.dart';

void main() {
  if (Platform.environment['RUN_LIVE_DB_TESTS'] != 'true') {
    test('Live database checks require explicit opt-in', () {}, skip: 'Set RUN_LIVE_DB_TESTS=true only on an approved disposable database.');
    return;
  }

  TestWidgetsFlutterBinding.ensureInitialized();
  final liveBaseDir = Directory('C:\\Users\\nourm\\AppData\\Roaming\\TracePOS\\Trace POS');
  final shouldRun = Platform.isWindows && liveBaseDir.existsSync();

  test('Export live diagnostic report from Windows machine', () async {
    await AppPaths.instance.initialize(
      customBaseDir: liveBaseDir,
    );
    HardwareManager.instance.initialize();

    print('Scanning hardware...');
    await HardwareManager.instance.runDiscoveryScan();

    print('Building sanitized diagnostic report...');
    final report = await ExportDiagnosticReportService.buildSanitizedReport();

    final jsonString = const JsonEncoder.withIndent('  ').convert(report);
    final outputFile = File('C:\\Users\\nourm\\Desktop\\tracepos\\release_audit\\live_windows_machine_diagnostic.json');
    await outputFile.writeAsString(jsonString);

    print('Diagnostic report saved to: ${outputFile.path}');
    expect(outputFile.existsSync(), isTrue);
    expect(outputFile.lengthSync(), greaterThan(0));

    // Verify sanitization: Ensure no sensitive keys exist
    final rawText = outputFile.readAsStringSync();
    expect(rawText.contains('pinHash'), isFalse);
    expect(rawText.contains('password'), isFalse);
  }, skip: !shouldRun ? 'Requires live Windows machine with local directory' : null);
}
