// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/open.dart';
import 'package:jazzpos/core/platform/app_paths.dart';
import 'package:jazzpos/core/platform/export_diagnostic_report_service.dart';
import 'package:jazzpos/hardware/hardware_manager.dart';

void main() async {
  final dllPath = Platform.environment['SQLITE_DLL_PATH'] ??
      'C:\\Users\\nourm\\Desktop\\jazzpos\\build\\windows\\x64\\runner\\Release\\sqlite3.dll';
  open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(dllPath));

  await AppPaths.instance.initialize();
  HardwareManager.instance.initialize();

  // Run hardware discovery
  print('Running hardware discovery...');
  await HardwareManager.instance.runDiscoveryScan();

  print('Building sanitized diagnostic report...');
  final report = await ExportDiagnosticReportService.buildSanitizedReport();

  final jsonString = const JsonEncoder.withIndent('  ').convert(report);
  final outputFile = File('C:\\Users\\nourm\\Desktop\\jazzpos\\release_audit\\live_windows_machine_diagnostic.json');
  await outputFile.writeAsString(jsonString);

  print('Diagnostic report saved to: ${outputFile.path}');
  print('Report Summary:');
  print('  OS: ${report['system']['os']} (${report['system']['edition']})');
  print('  Architecture: ${report['system']['architecture']}');
  print('  Discovered Printers: ${(report['discoveredPeripherals']['printers'] as List).length}');
  print('  Discovered USB Devices: ${(report['discoveredPeripherals']['usbDevices'] as List).length}');
  print('  Discovered Serial Ports: ${(report['discoveredPeripherals']['serialPorts'] as List).length}');
  print('  Discovered Displays: ${(report['discoveredPeripherals']['displays'] as List).length}');
}
