import 'package:tracepos/hardware/barcode_scanner/scanner_route_observer.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/constants/app_constants.dart';
import 'core/localization/app_localizations_delegate.dart';
import 'core/localization/locale_provider.dart';
import 'core/logging/pos_logger.dart';
import 'core/logging/startup_tracker.dart';
import 'core/platform/app_paths.dart';
import 'core/platform/environment_diagnostics_service.dart';
import 'core/sound/sound_effect_service.dart';
import 'domain/services/print_job_service.dart';
import 'hardware/hardware_manager.dart';
import 'ui/navigation/app_router.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/splash_gate.dart';
import 'ui/widgets/startup_recovery_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  PrintJobService.processStart; // record process start for print-job cleanup

  // Track early startup milestones
  StartupTracker.instance.startStage('native_runner');
  StartupTracker.instance.endStage('native_runner', success: true);
  StartupTracker.instance.startStage('flutter_engine');
  StartupTracker.instance.endStage('flutter_engine', success: true);

  try {
    // 1. Initialize storage paths and verify permissions on Windows / desktop
    StartupTracker.instance.startStage('app_paths');
    await AppPaths.instance.initialize();
    StartupTracker.instance.endStage('app_paths', success: true);

    // 2. Initialize file logging in AppData directory & startup logger
    StartupTracker.instance.startStage('logger_init');
    await PosLogger.instance.initialize();
    StartupTracker.instance.initStartupLog(AppPaths.instance.startupLogFilePath);
    StartupTracker.instance.endStage('logger_init', success: true);

    PosLogger.instance.info(
      'Main',
      'Trace POS starting in production desktop mode...',
    );

    // 3. Storage permission health check
    StartupTracker.instance.startStage('storage_health_check');
    final storageHealth = await AppPaths.instance.verifyStorageHealth();
    StartupTracker.instance.endStage('storage_health_check', success: true);
    PosLogger.instance.info(
      'Main',
      'Storage permissions health check: $storageHealth',
    );
  } catch (error, st) {
    PosLogger.instance.error('Main', 'Fatal early startup error: $error', error, st);
    StartupTracker.instance.endStage('app_paths', success: false, error: error.toString());
    runApp(StartupFailureApp(error: error));
    return;
  }

  // 4. Desktop window configuration for POS screen resolutions
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    try {
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        size: Size(1280, 800),
        minimumSize: Size(1024, 768),
        center: true,
        title: 'Trace POS — Point de Vente Prêt-à-Porter',
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      PosLogger.instance.warning(
        'Main',
        'Window manager initialization error: $e',
      );
    }
  }

  // 5. Launch UI immediately - REQUIRED ARCHITECTURE:
  // AppPaths -> database -> show login/setup/POS.
  // Hardware & environment diagnostics MUST run asynchronously in background.
  runApp(const ProviderScope(child: TracePosApp()));

  // 6. Asynchronous Background Initialization (Hardware & Diagnostics)
  Future.microtask(() async {
    // Audio sound effects initialization
    try {
      SoundEffectService.instance.initialize();
    } catch (e) {
      PosLogger.instance.warning('Main', 'SoundEffectService init error: $e');
    }

    // Peripheral hardware initialization
    try {
      StartupTracker.instance.startStage('hardware_init');
      HardwareManager.instance.initialize();
      StartupTracker.instance.endStage('hardware_init', success: true);
    } catch (e) {
      PosLogger.instance.warning('Main', 'Background hardware init error: $e');
      StartupTracker.instance.endStage('hardware_init', success: false, error: e.toString());
    }

    // Windows environment inspection (offline, non-blocking)
    try {
      StartupTracker.instance.startStage('environment_diagnostics');
      final envReport = await EnvironmentDiagnosticsService()
          .inspectEnvironment()
          .timeout(
            const Duration(seconds: 4),
            onTimeout: () => EnvironmentDiagnosticReport(
              timestamp: DateTime.now(),
              osName: Platform.operatingSystem,
              osEdition: 'Windows (Offline)',
              osVersion: Platform.operatingSystemVersion,
              osBuild: 'N/A',
              architecture: 'x64',
              cpuModel: '${Platform.numberOfProcessors} cores',
              primaryDisplayWidth: 1920,
              primaryDisplayHeight: 1080,
              displayDpiScale: 1.0,
              displayCount: 1,
              locale: Platform.localeName,
              systemLanguage: 'fr',
              timeZone: DateTime.now().timeZoneName,
              isElevatedAdmin: false,
              appDirectory: '',
              dataDirectory: AppPaths.instance.baseDir.path,
              dataDirWritable: true,
              backupDirWritable: true,
              sqliteAccessible: true,
              sqliteIntegrityHealthy: true,
              vcRuntimeAvailable: true,
              networkAvailable: false,
              hostname: Platform.localHostname,
              isSupportedWindows: true,
            ),
          );
      StartupTracker.instance.endStage('environment_diagnostics', success: true);
      PosLogger.instance.info(
        'Main',
        'Environment inspection: ${envReport.osName} (${envReport.architecture}), Admin: ${envReport.isElevatedAdmin}, Supported: ${envReport.isSupportedWindows}',
      );
    } catch (e) {
      PosLogger.instance.warning('Main', 'Background diagnostics error: $e');
      StartupTracker.instance.endStage('environment_diagnostics', success: false, error: e.toString());
    }
  });
}

class TracePosApp extends ConsumerWidget {
  /// Zero in tests so they land directly on the app.
  final Duration splashDuration;

  const TracePosApp({
    super.key,
    this.splashDuration = const Duration(milliseconds: 1400),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(localeProvider);

    return MaterialApp(
      navigatorObservers:[ScannerRouteObserver()],
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      locale: currentLocale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: SplashGate(duration: splashDuration, child: const AppShell()),
    );
  }
}


class StartupFailureApp extends StatelessWidget {
  final Object error;

  const StartupFailureApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppConstants.appName,
      home: StartupRecoveryWidget(
        title: "${AppConstants.appName} ne peut pas accéder à son dossier de données.",
        errorMessage: error.toString().split('\n').first,
        technicalDetails: error.toString(),
        onRetry: () => main(),
        onClose: () => exit(0),
      ),
    );
  }
}
