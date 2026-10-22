import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tracepos/core/platform/legacy_names.dart';

/// Centralized file and directory path resolver for Trace POS.
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
  Directory get tempDir => _initialized ? _tempDir : Directory.systemTemp;
  Directory get imagesDir => _imagesDir;
  Directory get productImagesDir =>
      Directory(p.join(_baseDir.path, 'images', 'products'));
  Directory get stagedImagesDir =>
      Directory(p.join(tempDir.path, 'staged_images'));

  String get databaseFilePath => p.join(_databaseDir.path, 'tracepos.sqlite');
  String get logFilePath => p.join(_logsDir.path, 'tracepos.log');
  String get startupLogFilePath => p.join(_logsDir.path, 'startup.log');

  /// Safely resolve a managed relative or legacy absolute image path to an absolute filesystem path.
  /// Protects against directory traversal attacks and absolute paths outside baseDir.
  String? resolveImagePath(String? imagePath) {
    if (imagePath == null || imagePath.trim().isEmpty) return null;
    final clean = imagePath.trim().replaceAll(r'\', '/');

    // Prevent directory traversal
    if (clean.contains('..')) {
      return null;
    }

    final isWindowsDrive = RegExp(r'^[a-zA-Z]:').hasMatch(clean);
    final isAbsolute = p.isAbsolute(clean) || p.windows.isAbsolute(clean) || isWindowsDrive || clean.startsWith('/');
    if (isAbsolute) {
      if (p.isWithin(_baseDir.path, clean) || p.equals(_baseDir.path, clean)) {
        return p.normalize(clean);
      }
      return null;
    }

    final fullPath = p.normalize(p.join(_baseDir.path, clean));
    if (!p.isWithin(_baseDir.path, fullPath) && !p.equals(_baseDir.path, fullPath)) {
      return null;
    }

    return fullPath;
  }

  /// Convert a filesystem path inside baseDir to a canonical database-storable relative path.
  String toRelativeImagePath(String absoluteOrRelativePath) {
    final clean = absoluteOrRelativePath.trim().replaceAll(r'\', '/');
    final baseClean = _baseDir.path.replaceAll(r'\', '/');

    if (clean.startsWith('$baseClean/')) {
      return clean.substring(baseClean.length + 1);
    }
    if (clean.startsWith(baseClean)) {
      return clean.substring(baseClean.length);
    }
    return clean;
  }

  /// Initialize and guarantee directory hierarchy
  Future<void> initialize({Directory? customBaseDir}) async {
    if (_initialized && customBaseDir == null) return;

    if (customBaseDir != null) {
      _baseDir = customBaseDir;
    } else {
        // Check environment override (e.g. TRACEPOS_DATA_DIR=D:\TracePOS_Data)
        final envPath = Platform.environment['TRACEPOS_DATA_DIR'] ??
            Platform.environment[LegacyNames.dataDirEnv];
        if (envPath != null && envPath.trim().isNotEmpty) {
          _baseDir = Directory(envPath.trim());
        } else {
          final supportDir = await getApplicationSupportDirectory();
          if (Platform.isWindows) {
            final traceDir = Directory(p.join(supportDir.path, 'TracePOS'));
            final legacyDir = Directory(
              p.join(supportDir.path, LegacyNames.dataDir),
            );
            if (!traceDir.existsSync() && legacyDir.existsSync()) {
              // Upgrade from a pre-rename install: move the data folder, or
              // keep using it in place if it cannot be moved.
              try {
                legacyDir.renameSync(traceDir.path);
                _baseDir = traceDir;
              } catch (_) {
                _baseDir = legacyDir;
              }
            } else if (!supportDir.path.toLowerCase().contains('tracepos')) {
              _baseDir = traceDir;
            } else {
              _baseDir = supportDir;
            }
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
    await _migrateLegacyDatabaseFile();
    await _ensureDirectoryExists(_databaseDir);
    await _ensureDirectoryExists(_logsDir);
    await _ensureDirectoryExists(_backupsDir);
    await _ensureDirectoryExists(_tempDir);
    await _ensureDirectoryExists(_imagesDir);
    await _ensureDirectoryExists(productImagesDir);
    await _ensureDirectoryExists(stagedImagesDir);

    _initialized = true;
  }

  /// Renames a pre-rename database (and its WAL files) to the current name.
  Future<void> _migrateLegacyDatabaseFile() async {
    final current = File(databaseFilePath);
    final legacy = File(p.join(_databaseDir.path, LegacyNames.databaseFile));
    if (await current.exists() || !await legacy.exists()) return;
    for (final suffix in ['', '-wal', '-shm']) {
      final from = File('${legacy.path}$suffix');
      if (await from.exists()) await from.rename('${current.path}$suffix');
    }
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
