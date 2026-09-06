import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/localization/app_localizations_delegate.dart';
import 'core/localization/locale_provider.dart';
import 'core/logging/pos_logger.dart';
import 'core/platform/app_paths.dart';
import 'core/platform/environment_diagnostics_service.dart';
import 'hardware/hardware_manager.dart';
import 'ui/navigation/app_router.dart';
import 'ui/screens/auth/unsupported_os_screen.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // 1. Initialize storage paths and verify permissions on Windows / desktop
    await AppPaths.instance.initialize();

    // 2. Initialize file logging in AppData directory
    await PosLogger.instance.initialize();
    PosLogger.instance.info(
      'Main',
      'JazzPOS starting in production desktop mode...',
    );

    // 3. Storage permission health check
    final storageHealth = await AppPaths.instance.verifyStorageHealth();
    PosLogger.instance.info(
      'Main',
      'Storage permissions health check: $storageHealth',
    );
  } catch (error) {
    // A bad JAZZPOS_DATA_DIR or an unavailable disk must not leave a black
    // desktop window. Do not silently use another database location.
    runApp(StartupFailureApp(error: error));
    return;
  }

  // 4. Inspect Windows environment and OS compatibility
  final envReport = await EnvironmentDiagnosticsService().inspectEnvironment();
  PosLogger.instance.info(
    'Main',
    'Environment inspection: ${envReport.osName} (${envReport.architecture}), Admin: ${envReport.isElevatedAdmin}, Supported: ${envReport.isSupportedWindows}',
  );

  // 5. Desktop window configuration for POS screen resolutions
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    try {
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        size: Size(1280, 800),
        minimumSize: Size(1024, 768),
        center: true,
        title: 'JAZZ POS — Point de Vente Prêt-à-Porter',
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

  // 6. Initialize peripheral hardware layer
  HardwareManager.instance.initialize();

  // If running on an unsupported legacy operating system (e.g. Windows 7 / 8 / 32-bit),
  // present the non-destructive compatibility warning screen.
  if (!envReport.isSupportedWindows) {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: UnsupportedOsScreen(
          report: envReport,
          onProceedAnyway: () {
            runApp(const ProviderScope(child: JazzPosApp()));
          },
        ),
      ),
    );
    return;
  }

  runApp(const ProviderScope(child: JazzPosApp()));
}

class JazzPosApp extends ConsumerWidget {
  const JazzPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(localeProvider);

    return MaterialApp(
      title: 'JAZZ POS',
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
      home: const AppShell(),
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
      title: 'JAZZ POS',
      home: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.storage_rounded,
                    color: Color(0xFFDC2626),
                    size: 52,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'JAZZ POS ne peut pas accéder à son dossier de données.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Vérifiez les permissions du disque et la valeur de JAZZPOS_DATA_DIR, puis relancez l’application. Aucune donnée n’a été déplacée.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF475569), height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Détail technique : $error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
