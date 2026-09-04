import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';

/// Helper to manage Windows Auto-Start registration for POS Kiosk deployments.
class WindowsStartup {
  static const String _registryKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _appName = 'JazzPOS';

  /// Check if JazzPOS is registered to start on Windows boot
  static Future<bool> isAutoStartEnabled() async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run('reg', [
        'query',
        _registryKey,
        '/v',
        _appName,
      ]);
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('Error querying Windows startup registry: $e');
      return false;
    }
  }

  /// Enable auto-start on Windows boot
  static Future<bool> enableAutoStart() async {
    if (!Platform.isWindows) return false;
    try {
      final exePath = Platform.resolvedExecutable;
      final result = await Process.run('reg', [
        'add',
        _registryKey,
        '/v',
        _appName,
        '/t',
        'REG_SZ',
        '/d',
        '"$exePath"',
        '/f',
      ]);
      final success = result.exitCode == 0;
      if (success) {
        PosLogger.instance.info(
          'System',
          'Windows auto-start registered for $exePath',
        );
      } else {
        PosLogger.instance.warning(
          'System',
          'Failed to register Windows auto-start: ${result.stderr}',
        );
      }
      return success;
    } catch (e) {
      PosLogger.instance.error(
        'System',
        'Exception registering auto-start: $e',
      );
      return false;
    }
  }

  /// Disable auto-start
  static Future<bool> disableAutoStart() async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run('reg', [
        'delete',
        _registryKey,
        '/v',
        _appName,
        '/f',
      ]);
      final success = result.exitCode == 0;
      if (success) {
        PosLogger.instance.info('System', 'Windows auto-start unregistered');
      }
      return success;
    } catch (e) {
      PosLogger.instance.error(
        'System',
        'Exception unregistering auto-start: $e',
      );
      return false;
    }
  }
}
