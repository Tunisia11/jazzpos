import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';

class StartupStageRecord {
  final String stage;
  final DateTime startTime;
  DateTime? endTime;
  bool? success;
  String? error;

  StartupStageRecord({
    required this.stage,
    required this.startTime,
  });

  int get elapsedMs {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime).inMilliseconds;
  }
}

/// Centralized startup performance and lifecycle tracer.
/// Logs startup milestones to console, PosLogger, and writes directly
/// to `%APPDATA%\JazzPOS\JAZZ POS\logs\startup.log`.
class StartupTracker {
  static final StartupTracker instance = StartupTracker._();
  StartupTracker._();

  final List<StartupStageRecord> _stages = [];
  final Map<String, Stopwatch> _stopwatches = {};
  File? _startupLogFile;
  final DateTime appStartTime = DateTime.now();

  List<StartupStageRecord> get stages => List.unmodifiable(_stages);

  void initStartupLog(String filePath) {
    try {
      _startupLogFile = File(filePath);
      if (!_startupLogFile!.parent.existsSync()) {
        _startupLogFile!.parent.createSync(recursive: true);
      }
      _appendToFile(
        '\n=== TRACE POS STARTUP SESSION: ${DateTime.now().toIso8601String()} ===\n'
        'OS: ${Platform.operatingSystem} (${Platform.operatingSystemVersion})\n'
        'Process PID: $pid\n'
        '------------------------------------------------------------\n',
      );
    } catch (e) {
      debugPrint('Could not initialize startup log file: $e');
    }
  }

  void startStage(String stageName) {
    final record = StartupStageRecord(
      stage: stageName,
      startTime: DateTime.now(),
    );
    _stages.add(record);
    final sw = Stopwatch()..start();
    _stopwatches[stageName] = sw;

    final msg = '[STARTUP] $stageName START';
    PosLogger.instance.info('Startup', msg);
    _appendToFile('${_timestamp()} $msg\n');
  }

  void endStage(String stageName, {bool success = true, String? error}) {
    final sw = _stopwatches.remove(stageName);
    final elapsedMs = sw != null ? sw.elapsedMilliseconds : 0;

    StartupStageRecord? record;
    for (final r in _stages.reversed) {
      if (r.stage == stageName && r.endTime == null) {
        record = r;
        break;
      }
    }
    if (record != null) {
      record.endTime = DateTime.now();
      record.success = success;
      record.error = error;
    }

    final status = success ? 'OK' : 'FAIL';
    final detail = error != null ? ': $error' : '';
    final msg = '[STARTUP] $stageName $status ${elapsedMs}ms$detail';

    if (success) {
      PosLogger.instance.info('Startup', msg);
    } else {
      PosLogger.instance.warning('Startup', msg);
    }
    _appendToFile('${_timestamp()} $msg\n');
  }

  String _timestamp() {
    return DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());
  }

  void _appendToFile(String text) {
    try {
      if (_startupLogFile != null) {
        _startupLogFile!.writeAsStringSync(text, mode: FileMode.append, flush: true);
      }
    } catch (e) { PosLogger.instance.warning('startup_tracker', 'Ignored error: $e'); }
  }

  String getDiagnosticSummary() {
    final buffer = StringBuffer();
    buffer.writeln('Session started at: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(appStartTime)}');
    buffer.writeln('Total stages recorded: ${_stages.length}');
    for (final s in _stages) {
      final status = s.success == null
          ? 'IN PROGRESS'
          : s.success!
              ? 'OK'
              : 'FAILED';
      buffer.writeln(' - ${s.stage.padRight(28)}: $status (${s.elapsedMs}ms)${s.error != null ? ' - ${s.error}' : ''}');
    }
    return buffer.toString();
  }
}