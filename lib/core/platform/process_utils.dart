import 'dart:io';
import 'package:jazzpos/core/logging/pos_logger.dart';

/// Utilities for executing external processes with guaranteed finite timeouts.
/// Eliminates infinite hangs when executing PowerShell, WMIC, or registry commands.
class ProcessUtils {
  /// Default timeout for external system queries (e.g. registry, WMI, PowerShell)
  static const Duration defaultTimeout = Duration(seconds: 3);

  /// Run an external process with strict timeout. If the process exceeds [timeout],
  /// it is terminated and a failure [ProcessResult] is returned instead of hanging.
  static Future<ProcessResult> safeRun(
    String executable,
    List<String> arguments, {
    Duration timeout = defaultTimeout,
    String? workingDirectory,
  }) async {
    try {
      return await Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
      ).timeout(
        timeout,
        onTimeout: () {
          PosLogger.instance.warning(
            'ProcessUtils',
            'Execution timed out after ${timeout.inSeconds}s: $executable ${arguments.take(3).join(' ')}...',
          );
          return ProcessResult(
            -1,
            -1,
            '',
            'Process $executable timed out after ${timeout.inSeconds}s',
          );
        },
      );
    } catch (e) {
      PosLogger.instance.warning(
        'ProcessUtils',
        'Execution exception for $executable: $e',
      );
      return ProcessResult(-1, -1, '', e.toString());
    }
  }
}