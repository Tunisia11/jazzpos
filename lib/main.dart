import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/logging/pos_logger.dart';
import 'hardware/hardware_manager.dart';
import 'ui/navigation/app_router.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize hardware layer (with simulated fallbacks on macOS)
  HardwareManager.instance.initialize();
  PosLogger.instance.info('Main', 'JazzPOS starting in production desktop mode...');

  runApp(
    const ProviderScope(
      child: JazzPosApp(),
    ),
  );
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
