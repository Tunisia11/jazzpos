import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'core/logging/pos_logger.dart';
import 'core/platform/app_paths.dart';
import 'hardware/hardware_manager.dart';
import 'ui/navigation/app_router.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // 4. Desktop window configuration for POS screen resolutions
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

  // 5. Initialize peripheral hardware layer
  HardwareManager.instance.initialize();

  runApp(const ProviderScope(child: JazzPosApp()));
}

class JazzPosApp extends StatelessWidget {
  const JazzPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JazzPOS — Point de Vente Prêt-à-Porter',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AppShell(),
    );
  }
}
