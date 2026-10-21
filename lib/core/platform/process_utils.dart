import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// External operations are bounded; a timeout kills and reaps the child.
class ProcessUtils {
  static const defaultTimeout = Duration(seconds: 3);
  static Future<ProcessResult> safeRun(String executable, List<String> arguments, {
    Duration timeout = defaultTimeout, String? workingDirectory,
  }) async {
    try {
      final process = await Process.start(executable, arguments, workingDirectory: workingDirectory);
      final stdout = process.stdout.transform(const Utf8Decoder(allowMalformed: true)).join();
      final stderr = process.stderr.transform(const Utf8Decoder(allowMalformed: true)).join();
      int exitCode;
      try {
        exitCode = await process.exitCode.timeout(timeout);
      } on TimeoutException {
        if (Platform.isWindows) {
          final killer = await Process.start('taskkill', ['/PID', '${process.pid}', '/T', '/F']);
          final drains = Future.wait([killer.stdout.drain<void>(), killer.stderr.drain<void>()]);
          try { await killer.exitCode.timeout(const Duration(seconds: 3)); }
          on TimeoutException { killer.kill(); await killer.exitCode; }
          await drains;
          process.kill();
        } else {
          process.kill(ProcessSignal.sigkill);
        }
        await process.exitCode;
        // Reap before returning. A submitted spool job may still print.
        await Future.wait([stdout, stderr]);
        return ProcessResult(process.pid, -1, '', 'TIMEOUT: child terminated; delivery unknown. Check the Windows queue before retrying.');
      }
      return ProcessResult(process.pid, exitCode, await stdout, await stderr);
    } catch (e) {
      return ProcessResult(-1, -1, '', e.toString());
    }
  }
}
