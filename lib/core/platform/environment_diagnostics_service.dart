import 'dart:ffi';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/platform/app_paths.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/database_integrity_service.dart';

/// Structured environment diagnostics result.
class EnvironmentDiagnosticReport {
  final DateTime timestamp;
  final String osName;
  final String osEdition;
  final String osVersion;
  final String osBuild;
  final String architecture; // x64, arm64, x86, unknown
  final String cpuModel;
  final int? totalRamMb;
  final int? freeRamMb;
  final int? totalDiskMb;
  final int? freeDiskMb;
  final int primaryDisplayWidth;
  final int primaryDisplayHeight;
  final double displayDpiScale;
  final int displayCount;
  final String locale;
  final String systemLanguage;
  final String timeZone;
  final bool isElevatedAdmin;
  final String appDirectory;
  final String dataDirectory;
  final bool dataDirWritable;
  final bool backupDirWritable;
  final bool sqliteAccessible;
  final bool sqliteIntegrityHealthy;
  final String? sqliteDetails;
  final bool vcRuntimeAvailable;
  final bool networkAvailable;
  final String hostname;
  final bool isSupportedWindows;
  final String? compatibilityWarning;

  const EnvironmentDiagnosticReport({
    required this.timestamp,
    required this.osName,
    required this.osEdition,
    required this.osVersion,
    required this.osBuild,
    required this.architecture,
    required this.cpuModel,
    this.totalRamMb,
    this.freeRamMb,
    this.totalDiskMb,
    this.freeDiskMb,
    required this.primaryDisplayWidth,
    required this.primaryDisplayHeight,
    required this.displayDpiScale,
    required this.displayCount,
    required this.locale,
    required this.systemLanguage,
    required this.timeZone,
    required this.isElevatedAdmin,
    required this.appDirectory,
    required this.dataDirectory,
    required this.dataDirWritable,
    required this.backupDirWritable,
    required this.sqliteAccessible,
    required this.sqliteIntegrityHealthy,
    this.sqliteDetails,
    required this.vcRuntimeAvailable,
    required this.networkAvailable,
    required this.hostname,
    required this.isSupportedWindows,
    this.compatibilityWarning,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'os': {
      'name': osName,
      'edition': osEdition,
      'version': osVersion,
      'build': osBuild,
      'architecture': architecture,
      'cpuModel': cpuModel,
      'isSupportedWindows': isSupportedWindows,
      'compatibilityWarning': compatibilityWarning,
    },
    'memory': {'totalMb': totalRamMb, 'freeMb': freeRamMb},
    'storage': {
      'totalDiskMb': totalDiskMb,
      'freeDiskMb': freeDiskMb,
      'appDirectory': appDirectory,
      'dataDirectory': dataDirectory,
      'dataDirWritable': dataDirWritable,
      'backupDirWritable': backupDirWritable,
    },
    'display': {
      'primaryWidth': primaryDisplayWidth,
      'primaryHeight': primaryDisplayHeight,
      'dpiScale': displayDpiScale,
      'displayCount': displayCount,
    },
    'environment': {
      'locale': locale,
      'language': systemLanguage,
      'timeZone': timeZone,
      'isElevatedAdmin': isElevatedAdmin,
      'vcRuntimeAvailable': vcRuntimeAvailable,
      'networkAvailable': networkAvailable,
      'hostname': hostname,
    },
    'database': {
      'accessible': sqliteAccessible,
      'integrityHealthy': sqliteIntegrityHealthy,
      'details': sqliteDetails,
    },
  };
}

/// Service that performs non-intrusive, offline diagnostics of the host Windows environment.
class EnvironmentDiagnosticsService {
  final AppDatabase? _database;

  EnvironmentDiagnosticsService({AppDatabase? database}) : _database = database;

  /// Inspect the host system and return a structured diagnostic report.
  Future<EnvironmentDiagnosticReport> inspectEnvironment() async {
    PosLogger.instance.info(
      'Diagnostics',
      'Starting environment inspection...',
    );

    final now = DateTime.now();
    final osName = Platform.operatingSystem;
    final osVersionString = Platform.operatingSystemVersion;
    final hostname = Platform.localHostname;

    // 1. Windows edition, build & architecture
    final windowsInfo = await _inspectWindowsDetails(osVersionString);

    // 2. RAM & Disk
    final ram = await _inspectMemory();
    final disk = await _inspectDiskSpace();

    // 3. Displays & DPI
    final displayInfo = _inspectDisplays();

    // 4. Locales & Timezone
    final locale = Platform.localeName;
    final systemLanguage = locale.split(RegExp(r'[-_]')).first;
    final timeZone = DateTime.now().timeZoneName;

    // 5. Admin elevation
    final isElevated = await _checkElevation();

    // 6. Paths & Writability
    final appDir = File(Platform.resolvedExecutable).parent.path;
    String dataDir;
    bool dataWritable = false;
    bool backupWritable = false;
    try {
      if (!AppPaths.instance.isInitialized) {
        await AppPaths.instance.initialize();
      }
      dataDir = AppPaths.instance.baseDir.path;
      final storageHealth = await AppPaths.instance.verifyStorageHealth();
      dataWritable = storageHealth['database'] ?? false;
      backupWritable = storageHealth['backups'] ?? false;
    } catch (_) {
      dataDir = Directory.current.path;
    }

    // 7. SQLite & Database health
    bool sqliteOk = false;
    bool integrityOk = false;
    String? sqliteSummary;
    if (_database != null) {
      try {
        final integrityService = DatabaseIntegrityService(_database);
        final report = await integrityService.runDiagnostics();
        sqliteOk = true;
        integrityOk = report.isHealthy;
        sqliteSummary =
            'Sales: ${report.totalSales}, Products: ${report.totalProducts}, Issues: ${report.issues.length}';
      } catch (e) {
        sqliteSummary = 'Diagnostics error: $e';
      }
    } else {
      // Direct SQLite file check
      final dbFile = File(AppPaths.instance.databaseFilePath);
      sqliteOk = await dbFile.exists();
      integrityOk = sqliteOk;
    }

    // 8. Visual C++ runtime
    final vcRuntime = await _checkVisualCRuntime();

    // 9. Network availability (offline check: active interfaces without loopback)
    final networkOk = await _checkNetworkInterfaces();

    // 10. Windows compatibility evaluation
    final isSupported = windowsInfo.isSupported;
    final warning = windowsInfo.warning;

    final report = EnvironmentDiagnosticReport(
      timestamp: now,
      osName: osName,
      osEdition: windowsInfo.edition,
      osVersion: windowsInfo.version,
      osBuild: windowsInfo.build,
      architecture: windowsInfo.architecture,
      cpuModel: windowsInfo.cpuModel,
      totalRamMb: ram.totalMb,
      freeRamMb: ram.freeMb,
      totalDiskMb: disk.totalMb,
      freeDiskMb: disk.freeMb,
      primaryDisplayWidth: displayInfo.width,
      primaryDisplayHeight: displayInfo.height,
      displayDpiScale: displayInfo.scale,
      displayCount: displayInfo.count,
      locale: locale,
      systemLanguage: systemLanguage,
      timeZone: timeZone,
      isElevatedAdmin: isElevated,
      appDirectory: appDir,
      dataDirectory: dataDir,
      dataDirWritable: dataWritable,
      backupDirWritable: backupWritable,
      sqliteAccessible: sqliteOk,
      sqliteIntegrityHealthy: integrityOk,
      sqliteDetails: sqliteSummary,
      vcRuntimeAvailable: vcRuntime,
      networkAvailable: networkOk,
      hostname: hostname,
      isSupportedWindows: isSupported,
      compatibilityWarning: warning,
    );

    PosLogger.instance.info(
      'Diagnostics',
      'Environment inspected: ${report.osEdition} (${report.architecture}), RAM: ${report.totalRamMb ?? 'N/A'}MB, VC++: ${report.vcRuntimeAvailable}, Supported: ${report.isSupportedWindows}',
    );

    return report;
  }

  /// Evaluates OS version, build, architecture, and compatibility.
  Future<_WindowsDetails> _inspectWindowsDetails(String osVersionRaw) async {
    if (!Platform.isWindows) {
      return _WindowsDetails(
        edition:
            '${Platform.operatingSystem} (${Platform.operatingSystemVersion})',
        version: Platform.operatingSystemVersion,
        build: 'N/A',
        architecture: Abi.current().toString(),
        cpuModel: '${Platform.numberOfProcessors} cores',
        isSupported: true,
        warning: null,
      );
    }

    String edition = 'Windows';
    String version = '';
    String build = '';
    String arch = 'x64';
    String cpu = '${Platform.numberOfProcessors} cores';
    bool isSupported = true;
    String? warning;

    // Detect CPU arch from environment variables
    final procArch =
        Platform.environment['PROCESSOR_ARCHITECTURE']?.toUpperCase() ?? '';
    if (procArch.contains('ARM64')) {
      arch = 'Arm64';
      isSupported =
          false; // Arm64 not certified production-ready for this stack
      warning =
          'Windows Arm64 detected: experimental runtime target. Hardware drivers and FFI plugins may require specific validation.';
    } else if (procArch.contains('AMD64') || procArch.contains('X64')) {
      arch = 'x64';
    } else if (procArch.contains('X86')) {
      arch = 'x86 (32-bit)';
      isSupported = false;
      warning =
          '32-bit Windows detected. JAZZ POS requires a 64-bit operating system.';
    }

    try {
      // Query Windows registry for precise release & build info
      final result = await Process.run('reg', [
        'query',
        r'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion',
        '/v',
        'ProductName',
      ]);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');
        for (final line in lines) {
          if (line.contains('ProductName')) {
            edition = line.split('REG_SZ').last.trim();
            break;
          }
        }
      }

      final buildResult = await Process.run('reg', [
        'query',
        r'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion',
        '/v',
        'CurrentBuild',
      ]);
      if (buildResult.exitCode == 0) {
        final lines = (buildResult.stdout as String).split('\n');
        for (final line in lines) {
          if (line.contains('CurrentBuild')) {
            build = line.split('REG_SZ').last.trim();
            break;
          }
        }
      }
    } catch (_) {}

    // Fallback if reg query is restricted
    if (edition == 'Windows') {
      edition = osVersionRaw;
    }

    // Windows version checking logic:
    // Windows 10 is build >= 10240, Windows 11 is build >= 22000.
    // Windows 7 is version 6.1 (build 7600/7601). Windows 8 is 6.2/6.3.
    final buildNumber = int.tryParse(build) ?? 0;
    if (edition.contains('Windows 7') ||
        osVersionRaw.contains(' 6.1') ||
        (buildNumber > 0 && buildNumber <= 7601)) {
      isSupported = false;
      warning =
          'JAZZ POS detected Windows 7. This version of Windows is outside the supported runtime target for this JAZZ POS build. Do not modify or delete your database. Use a compatible JAZZ POS legacy build or upgrade Windows.';
    } else if (edition.contains('Windows 8') ||
        osVersionRaw.contains(' 6.2') ||
        osVersionRaw.contains(' 6.3') ||
        (buildNumber > 0 && buildNumber < 10240)) {
      isSupported = false;
      warning =
          'JAZZ POS detected Windows 8 / 8.1. This version of Windows is outside the supported target. Please upgrade to Windows 10 or Windows 11.';
    }

    return _WindowsDetails(
      edition: edition,
      version: version.isNotEmpty ? version : osVersionRaw,
      build: build.isNotEmpty ? build : 'Build $buildNumber',
      architecture: arch,
      cpuModel: cpu,
      isSupported: isSupported,
      warning: warning,
    );
  }

  /// Check system RAM
  Future<({int? totalMb, int? freeMb})> _inspectMemory() async {
    if (Platform.isWindows) {
      try {
        final result = await Process.run('wmic', [
          'OS',
          'get',
          'TotalVisibleMemorySize,FreePhysicalMemory',
          '/value',
        ]);
        if (result.exitCode == 0) {
          final text = result.stdout as String;
          int? totalKb;
          int? freeKb;
          for (final line in text.split('\n')) {
            final parts = line.split('=');
            if (parts.length == 2) {
              final key = parts[0].trim();
              final val = int.tryParse(parts[1].trim());
              if (key == 'TotalVisibleMemorySize') totalKb = val;
              if (key == 'FreePhysicalMemory') freeKb = val;
            }
          }
          if (totalKb != null) {
            return (
              totalMb: totalKb ~/ 1024,
              freeMb: freeKb != null ? freeKb ~/ 1024 : null,
            );
          }
        }
      } catch (_) {}
    }
    return (totalMb: null, freeMb: null);
  }

  /// Check available disk space on data path volume
  Future<({int? totalMb, int? freeMb})> _inspectDiskSpace() async {
    if (Platform.isWindows) {
      try {
        final driveLetter = AppPaths.instance.baseDir.path.split(':').first;
        final result = await Process.run('wmic', [
          'logicaldisk',
          'where',
          'DeviceID="$driveLetter:"',
          'get',
          'Size,FreeSpace',
          '/value',
        ]);
        if (result.exitCode == 0) {
          final text = result.stdout as String;
          int? totalBytes;
          int? freeBytes;
          for (final line in text.split('\n')) {
            final parts = line.split('=');
            if (parts.length == 2) {
              final key = parts[0].trim();
              final val = int.tryParse(parts[1].trim());
              if (key == 'Size') totalBytes = val;
              if (key == 'FreeSpace') freeBytes = val;
            }
          }
          if (totalBytes != null) {
            return (
              totalMb: totalBytes ~/ (1024 * 1024),
              freeMb: freeBytes != null ? freeBytes ~/ (1024 * 1024) : null,
            );
          }
        }
      } catch (_) {}
    }
    return (totalMb: null, freeMb: null);
  }

  /// Query displays attached to the system
  ({int width, int height, double scale, int count}) _inspectDisplays() {
    try {
      final dispatcher = WidgetsBinding.instance.platformDispatcher;
      final displays = dispatcher.displays.toList();
      if (displays.isNotEmpty) {
        final primary = displays.first;
        final size = primary.size;
        return (
          width: size.width.round(),
          height: size.height.round(),
          scale: primary.devicePixelRatio,
          count: displays.length,
        );
      }
    } catch (_) {}
    return (width: 1920, height: 1080, scale: 1.0, count: 1);
  }

  /// Check if the application runs as elevated administrator
  Future<bool> _checkElevation() async {
    if (!Platform.isWindows) return false;
    try {
      // 'net session' exits with 0 only if running as Administrator
      final result = await Process.run('net', ['session']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Check Visual C++ 2015-2022 redistributable availability
  Future<bool> _checkVisualCRuntime() async {
    if (!Platform.isWindows) return true;
    try {
      // 1. Registry check for Visual Studio 2015-2022 VC++ x64 runtime
      final regCheck = await Process.run('reg', [
        'query',
        r'HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
        '/v',
        'Installed',
      ]);
      if (regCheck.exitCode == 0 &&
          (regCheck.stdout as String).contains('0x1')) {
        return true;
      }

      // 2. Direct DLL check in System32
      final vcRuntime140 = File(r'C:\Windows\System32\vcruntime140.dll');
      final msvcp140 = File(r'C:\Windows\System32\msvcp140.dll');
      if (await vcRuntime140.exists() && await msvcp140.exists()) {
        return true;
      }
      return false;
    } catch (_) {
      return true;
    }
  }

  /// Check if any non-loopback network interface is active (offline-compatible)
  Future<bool> _checkNetworkInterfaces() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.any,
      );
      return interfaces.any((i) => i.addresses.isNotEmpty);
    } catch (_) {
      return false;
    }
  }
}

class _WindowsDetails {
  final String edition;
  final String version;
  final String build;
  final String architecture;
  final String cpuModel;
  final bool isSupported;
  final String? warning;

  const _WindowsDetails({
    required this.edition,
    required this.version,
    required this.build,
    required this.architecture,
    required this.cpuModel,
    required this.isSupported,
    this.warning,
  });
}
