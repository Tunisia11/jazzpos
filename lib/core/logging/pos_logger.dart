import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:jazzpos/core/platform/app_paths.dart';

enum LogLevel { debug, info, warning, error }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String category;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.error,
    this.stackTrace,
  });

  String format() {
    final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(timestamp);
    final lvlStr = level.name.toUpperCase().padRight(7);
    final catStr = '[$category]'.padRight(14);
    var res = '$timeStr $lvlStr $catStr $message';
    if (error != null) res += '\n  Error: $error';
    if (stackTrace != null) res += '\n  StackTrace: $stackTrace';
    return res;
  }
}

/// Centralized POS logging system with secret redaction,
/// in-memory buffer for diagnostics, and rotating file persistence.
class PosLogger {
  static final PosLogger instance = PosLogger._();
  PosLogger._();

  final Queue<LogEntry> _inMemoryBuffer = Queue<LogEntry>();
  static const int maxBufferSize = 1000;
  File? _logFile;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await AppPaths.instance.initialize();
      _logFile = File(AppPaths.instance.logFilePath);
      _rotateIfNeeded();
      _initialized = true;
      info('Logger', 'POS Logging system initialized at ${_logFile?.path}');
    } catch (e) {
      debugPrint('Failed to initialize file logger: $e');
    }
  }

  void _rotateIfNeeded() {
    try {
      if (_logFile != null && _logFile!.existsSync()) {
        if (_logFile!.lengthSync() > 10 * 1024 * 1024) {
          // 10MB limit
          final backupPath = '${_logFile!.path}.old';
          final backupFile = File(backupPath);
          if (backupFile.existsSync()) backupFile.deleteSync();
          _logFile!.renameSync(backupPath);
          _logFile = File(_logFile!.path);
        }
      }
    } catch (e) {
      debugPrint('Error rotating log file: $e');
    }
  }

  /// Sanitize messages to never leak PINs, passwords, or secret tokens
  String _sanitize(String text) {
    return text
        .replaceAll(
          RegExp(
            r'(pin|password|secret|token|hash)[:=]\s*(\S+)',
            caseSensitive: false,
          ),
          r'$1=[REDACTED]',
        )
        .replaceAll(
          RegExp(
            r'\b\d{4,6}\b(?=.*(?:pin|password|auth))',
            caseSensitive: false,
          ),
          '[REDACTED_PIN]',
        );
  }

  void log(
    LogLevel level,
    String category,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    final sanitizedMessage = _sanitize(message);
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: sanitizedMessage,
      error: error,
      stackTrace: stackTrace,
    );

    // In-memory buffer
    _inMemoryBuffer.addLast(entry);
    while (_inMemoryBuffer.length > maxBufferSize) {
      _inMemoryBuffer.removeFirst();
    }

    final formatted = entry.format();
    if (kDebugMode) {
      debugPrint(formatted);
    }

    // Persist to file
    if (_logFile != null) {
      try {
        _logFile!.writeAsStringSync(
          '$formatted\n',
          mode: FileMode.append,
          flush: false,
        );
      } catch (_) {}
    }
  }

  void debug(String category, String message) =>
      log(LogLevel.debug, category, message);
  void info(String category, String message) =>
      log(LogLevel.info, category, message);
  void warning(String category, String message, [Object? error]) =>
      log(LogLevel.warning, category, message, error);
  void error(
    String category,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) => log(LogLevel.error, category, message, error, stackTrace);

  List<LogEntry> getRecentLogs([int count = 100]) {
    return _inMemoryBuffer.toList().reversed.take(count).toList();
  }

  String exportLogText() {
    return _inMemoryBuffer.map((e) => e.format()).join('\n');
  }
}
