import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Centralized file and directory path resolver for JAZZ POS.
/// Guarantees writable storage locations on Windows 10/11 IoT and macOS.
class AppPaths {
  static final AppPaths instance = AppPaths._();
  AppPaths._();

  late Directory _baseDir;
  late Directory _databaseDir;
  late Directory _logsDir;
  late Directory _backupsDir;
  late Directory _tempDir;
  late Directory _imagesDir;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Directory get baseDir => _baseDir;
  Directory get databaseDir => _databaseDir;
  Directory get logsDir => _logsDir;
  Directory get backupsDir => _backupsDir;
  Directory get tempDir => _tempDir;
  Directory get imagesDir => _imagesDir;

  String get databaseFilePath => p.join(_databaseDir.path, 'jazzpos.sqlite');
  String get logFilePath => p.join(_logsDir.path, 'jazzpos.log');

  /// Initialize and guarantee directory hierarchy
  Future<void> initialize({Directory? customBaseDir}) async {
    if (_initialized) return;

    if (customBaseDir != null) {
      _baseDir = customBaseDir;
    } else {
      // Check environment override (e.g. JAZZPOS_DATA_DIR=D:\JazzPOS_Data)
      final envPath = Platform.environment['JAZZPOS_DATA_DIR'];
      if (envPath != null && envPath.trim().isNotEmpty) {
        _baseDir = Directory(envPath.trim());
      } else {
        final supportDir = await getApplicationSupportDirectory();
        // Standardize base path under 'JazzPOS'
        if (Platform.isWindows &&
            !supportDir.path.toLowerCase().contains('jazzpos')) {
          _baseDir = Directory(p.join(supportDir.path, 'JazzPOS'));
        } else {
          _baseDir = supportDir;
        }
      }
    }

    _databaseDir = Directory(p.join(_baseDir.path, 'database'));
    _logsDir = Directory(p.join(_baseDir.path, 'logs'));
    _backupsDir = Directory(p.join(_baseDir.path, 'backups'));
    _tempDir = Directory(p.join(_baseDir.path, 'temp'));
    _imagesDir = Directory(p.join(_baseDir.path, 'product_images'));

    await _ensureDirectoryExists(_baseDir);
    await _ensureDirectoryExists(_databaseDir);
    await _ensureDirectoryExists(_logsDir);
    await _ensureDirectoryExists(_backupsDir);
    await _ensureDirectoryExists(_tempDir);
    await _ensureDirectoryExists(_imagesDir);

    _initialized = true;
  }

  Future<void> _ensureDirectoryExists(Directory dir) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Verify read/write storage permissions across all critical directories.
  /// Returns a map of directory name -> write test success.
  Future<Map<String, bool>> verifyStorageHealth() async {
    if (!_initialized) await initialize();

    final results = <String, bool>{};
    final targets = {
      'database': _databaseDir,
      'logs': _logsDir,
      'backups': _backupsDir,
      'temp': _tempDir,
      'images': _imagesDir,
    };

    for (final entry in targets.entries) {
      final testFile = File(
        p.join(
          entry.value.path,
          '.write_test_${DateTime.now().millisecondsSinceEpoch}.tmp',
        ),
      );
      try {
        await testFile.writeAsString('health_check', flush: true);
        final read = await testFile.readAsString();
        await testFile.delete();
        results[entry.key] = (read == 'health_check');
      } catch (e) {
        debugPrint('Storage health check failed for ${entry.key}: $e');
        results[entry.key] = false;
      }
    }

    return results;
  }
}
