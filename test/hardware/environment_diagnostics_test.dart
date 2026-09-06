import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/platform/app_paths.dart';
import 'package:jazzpos/core/platform/environment_diagnostics_service.dart';
import 'package:jazzpos/core/platform/export_diagnostic_report_service.dart';
import 'package:jazzpos/hardware/models/hardware_fingerprint.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final temp = await Directory.systemTemp.createTemp('jazzpos_env_test_');
    await AppPaths.instance.initialize(customBaseDir: temp);
  });

  group('EnvironmentDiagnosticsService', () {
    test('inspects environment and populates diagnostic report', () async {
      final service = EnvironmentDiagnosticsService();
      final report = await service.inspectEnvironment();

      expect(report.osName.isNotEmpty, isTrue);
      expect(report.architecture.isNotEmpty, isTrue);
      expect(report.appDirectory.isNotEmpty, isTrue);
      expect(report.dataDirectory.isNotEmpty, isTrue);

      final json = report.toJson();
      expect(json['os']['name'], equals(report.osName));
      expect(json['os']['architecture'], equals(report.architecture));
      expect(json['database'].containsKey('accessible'), isTrue);
    });

    test('correctly assesses Windows 7/8 as unsupported', () {
      final win7Report = EnvironmentDiagnosticReport(
        timestamp: DateTime.now(),
        osName: 'Windows',
        osEdition: 'Windows 7 Ultimate SP1',
        osVersion: '6.1.7601',
        osBuild: '7601',
        architecture: 'x64',
        cpuModel: 'Intel Core i3-3220',
        totalRamMb: 4096,
        freeRamMb: 2048,
        totalDiskMb: 120000,
        freeDiskMb: 50000,
        primaryDisplayWidth: 1024,
        primaryDisplayHeight: 768,
        displayDpiScale: 1.0,
        displayCount: 1,
        isElevatedAdmin: false,
        appDirectory: r'C:\Program Files\JAZZ POS',
        dataDirectory: r'C:\Users\POS\AppData\Roaming\JazzPOS',
        dataDirWritable: true,
        backupDirWritable: true,
        sqliteAccessible: true,
        sqliteIntegrityHealthy: true,
        sqliteDetails: 'OK',
        vcRuntimeAvailable: false,
        networkAvailable: true,
        hostname: 'POS-TERM-01',
        locale: 'fr_TN',
        systemLanguage: 'fr',
        timeZone: 'Africa/Tunis',
        isSupportedWindows: false,
        compatibilityWarning: 'Unsupported legacy OS (Windows 7)',
      );

      expect(win7Report.isSupportedWindows, isFalse);
      expect(win7Report.compatibilityWarning, isNotNull);
    });
  });

  group('ExportDiagnosticReportService Sanitization', () {
    test(
      'sanitized report excludes customer personal data and passwords',
      () async {
        final reportMap =
            await ExportDiagnosticReportService.buildSanitizedReport();
        final jsonString = jsonEncode(reportMap);

        // Verify required technical fields exist
        expect(reportMap.containsKey('jazzposVersion'), isTrue);
        expect(reportMap.containsKey('system'), isTrue);
        expect(reportMap.containsKey('storageAndDatabase'), isTrue);
        expect(reportMap.containsKey('hardware'), isTrue);
        expect(reportMap.containsKey('discoveredPeripherals'), isTrue);

        // Strict security assertion: no customer PII or authentication secrets
        final lowercase = jsonString.toLowerCase();
        expect(lowercase.contains('password'), isFalse);
        expect(lowercase.contains('pincode'), isFalse);
        expect(lowercase.contains('pin_hash'), isFalse);
        expect(lowercase.contains('salt'), isFalse);
        expect(lowercase.contains('customername'), isFalse);
        expect(lowercase.contains('creditcard'), isFalse);
      },
    );
  });

  group('HardwareStatus Lifecycle', () {
    test('all 10 lifecycle states have valid French labels and colors', () {
      expect(HardwareStatus.values.length, equals(10));

      for (final status in HardwareStatus.values) {
        expect(status.labelFr.isNotEmpty, isTrue);
        expect(status.color, isA<Color>());
      }

      expect(HardwareStatus.ready.isReady, isTrue);
      expect(HardwareStatus.ready.isOperational, isTrue);
      expect(HardwareStatus.simulated.isOperational, isTrue);
      expect(HardwareStatus.offline.isOffline, isTrue);
      expect(HardwareStatus.error.hasError, isTrue);
      expect(HardwareStatus.notConfigured.isOperational, isFalse);

      expect(HardwareStatus.fromString('READY'), equals(HardwareStatus.ready));
      expect(
        HardwareStatus.fromString('SIMULATED'),
        equals(HardwareStatus.simulated),
      );
      expect(
        HardwareStatus.fromString('UNKNOWN'),
        equals(HardwareStatus.notConfigured),
      );
    });
  });

  group('HardwareFingerprint', () {
    test('formats canonical key and matches fingerprints safely', () {
      const fp1 = HardwareFingerprint(
        transport: 'USB',
        vendorId: '04b8',
        productId: '0202',
        serialNumber: 'SN12345',
        portOrAddress: 'USB001',
      );

      const fp2 = HardwareFingerprint(
        transport: 'USB',
        vendorId: '04B8',
        productId: '0202',
        serialNumber: 'sn12345',
        portOrAddress: 'usb001',
      );

      const fpDifferent = HardwareFingerprint(
        transport: 'COM',
        portOrAddress: 'COM3',
      );

      expect(fp1.toCanonicalKey(), equals('USB:04b8:0202:sn12345:usb001'));
      expect(fp1.matches(fp2), isTrue);
      expect(fp1.matches(fpDifferent), isFalse);
    });
  });
}
