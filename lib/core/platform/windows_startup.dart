import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/platform/process_utils.dart';

/// Helper to manage Windows Auto-Start registration for POS Kiosk deployments.
class WindowsStartup {
  static const String _registryKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _appName = 'TracePOS';
  static const String _legacyAppName = 'JazzPOS';

  /// Check if Trace POS (or legacy JazzPOS) is registered to start on Windows boot
  static Future<bool> isAutoStartEnabled() async {
    if (!Platform.isWindows) return false;
    try {
      var result = await ProcessUtils.safeRun('reg', [
        'query',
        _registryKey,
        '/v',
        _appName,
      ]);
      if (result.exitCode == 0) return true;

      // Check legacy registry entry for upgrades
      result = await ProcessUtils.safeRun('reg', [
        'query',
        _registryKey,
        '/v',
        _legacyAppName,
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
      // Clean up legacy key if it exists
      await ProcessUtils.safeRun('reg', [
        'delete',
        _registryKey,
        '/v',
        _legacyAppName,
        '/f',
      ]);

      final result = await ProcessUtils.safeRun('reg', [
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
      final result = await ProcessUtils.safeRun('reg', [
        'delete',
        _registryKey,
        '/v',
        _appName,
        '/f',
      ]);
      // Also ensure legacy key is deleted
      await ProcessUtils.safeRun('reg', [
        'delete',
        _registryKey,
        '/v',
        _legacyAppName,
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
