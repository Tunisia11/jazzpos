import 'dart:convert';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/platform/environment_diagnostics_service.dart';
import 'package:jazzpos/hardware/hardware_manager.dart';

/// Generates and exports sanitized technical diagnostic reports for remote support.
/// Strictly excludes customer personal data, PINs, passwords, and transaction records.
class ExportDiagnosticReportService {
  /// Generate a clean, sanitized technical report map
  static Future<Map<String, dynamic>> buildSanitizedReport({
    EnvironmentDiagnosticReport? envReport,
  }) async {
    final hw = HardwareManager.instance;
    hw.initialize();
    final env =
        envReport ?? await EnvironmentDiagnosticsService().inspectEnvironment();

    return {
      'jazzposVersion': '1.0.0+1',
      'generatedAt': DateTime.now().toIso8601String(),
      'system': {
        'os': env.osName,
        'edition': env.osEdition,
        'version': env.osVersion,
        'build': env.osBuild,
        'architecture': env.architecture,
        'cpu': env.cpuModel,
        'ramTotalMb': env.totalRamMb,
        'ramFreeMb': env.freeRamMb,
        'diskTotalMb': env.totalDiskMb,
        'diskFreeMb': env.freeDiskMb,
        'isElevatedAdmin': env.isElevatedAdmin,
        'hostname': env.hostname,
        'locale': env.locale,
        'language': env.systemLanguage,
        'timeZone': env.timeZone,
        'vcRuntimeAvailable': env.vcRuntimeAvailable,
        'networkAvailable': env.networkAvailable,
        'isSupportedWindows': env.isSupportedWindows,
      },
      'storageAndDatabase': {
        'appDirectory': env.appDirectory,
        'dataDirectory': env.dataDirectory,
        'dataDirWritable': env.dataDirWritable,
        'backupDirWritable': env.backupDirWritable,
        'sqliteAccessible': env.sqliteAccessible,
        'sqliteIntegrityHealthy': env.sqliteIntegrityHealthy,
        'sqliteDetails': env.sqliteDetails,
        'schemaVersion': 2,
      },
      'hardware': {
        'receiptPrinter': {
          'name': hw.receiptPrinter.name,
          'connectionType': hw.receiptPrinter.connectionType,
          'status': hw.printerStatus.value,
          'profile': hw.receiptPrinter.profile.id,
          'fingerprint': hw.receiptPrinter.fingerprint?.toCanonicalKey(),
        },
        'barcodeScanner': {
          'name': hw.barcodeScanner.name,
          'status': hw.scannerStatus.value,
          'mode': 'KEYBOARD_WEDGE',
        },
        'cashDrawer': {
          'name': hw.cashDrawer.name,
          'mode': hw.cashDrawer.mode.value,
          'status': hw.drawerStatus.value,
          'isTested': hw.cashDrawer.isTested,
        },
        'customerDisplay': {
          'name': hw.customerDisplay.name,
          'mode': hw.customerDisplay.mode.value,
          'status': hw.displayStatus.value,
        },
      },
      'discoveredPeripherals': {
        'printers':
            hw.latestDiscovery?.printers.map((p) => p.toJson()).toList() ?? [],
        'usbDevices':
            hw.latestDiscovery?.usbDevices.map((u) => u.toJson()).toList() ??
            [],
        'serialPorts':
            hw.latestDiscovery?.serialPorts.map((s) => s.toJson()).toList() ??
            [],
        'displays':
            hw.latestDiscovery?.displays.map((d) => d.toJson()).toList() ?? [],
      },
      'recommendations': hw.latestRecommendations?.toJson(),
    };
  }

  /// Prompts operator to save the diagnostic report as a JSON file
  static Future<String?> exportReportToFile({
    EnvironmentDiagnosticReport? envReport,
  }) async {
    try {
      final reportMap = await buildSanitizedReport(envReport: envReport);
      final jsonString = const JsonEncoder.withIndent('  ').convert(reportMap);

      final dateStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'jazzpos_diagnostic_report_$dateStr.json';

      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON Document', extensions: ['json']),
        ],
      );

      if (location == null) return null;

      final xfile = XFile.fromData(
        Uint8List.fromList(utf8.encode(jsonString)),
        name: fileName,
        mimeType: 'application/json',
      );
      await xfile.saveTo(location.path);

      PosLogger.instance.info(
        'Diagnostics',
        'Exported sanitized diagnostic report to ${location.path}',
      );
      return location.path;
    } catch (e) {
      PosLogger.instance.error(
        'Diagnostics',
        'Failed to export diagnostic report: $e',
      );
      rethrow;
    }
  }
}
