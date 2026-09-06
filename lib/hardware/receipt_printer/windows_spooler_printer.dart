import 'dart:io';
import 'dart:typed_data';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/platform/app_paths.dart';
import 'package:jazzpos/hardware/models/hardware_fingerprint.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';
import 'printer_profile.dart';
import 'receipt_document.dart';
import 'receipt_layout_builder.dart';
import 'receipt_printer_interface.dart';

/// First-class Windows Print Spooler transport (`WINDOWS_SPOOLER`).
/// Sends raw ESC/POS bytes directly through the Windows print spooler subsystem
/// to any installed printer driver without altering the receipt byte stream.
class WindowsSpoolerPrinter implements ReceiptPrinter {
  @override
  final String name;

  @override
  final String connectionType = 'WINDOWS_SPOOLER';

  @override
  final PrinterProfile profile;

  @override
  HardwareStatus status = HardwareStatus.configured;

  final String? driverName;
  final String? portName;
  final List<Uint8List> lastSpoolJobs = [];

  WindowsSpoolerPrinter({
    required this.name,
    this.driverName,
    this.portName,
    this.profile = PrinterProfile.genericWindows,
  });

  @override
  HardwareFingerprint get fingerprint => HardwareFingerprint(
    transport: 'WINDOWS_SPOOLER',
    friendlyName: name,
    portOrAddress: portName,
  );

  @override
  Future<bool> connect() async {
    status = HardwareStatus.connecting;
    final isOk = await isConnected();
    status = isOk ? HardwareStatus.ready : HardwareStatus.offline;
    return isOk;
  }

  @override
  Future<bool> isConnected() async {
    if (!Platform.isWindows) {
      // In macOS / Linux dev environments, spooler is simulated
      return true;
    }

    try {
      // Query Windows printer spooler status
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Get-CimInstance Win32_Printer -Filter "Name = \'$name\'" | Select-Object -ExpandProperty WorkOffline',
      ]);
      if (result.exitCode == 0) {
        final text = (result.stdout as String).trim().toLowerCase();
        final isOffline = text == 'true';
        status = isOffline ? HardwareStatus.offline : HardwareStatus.ready;
        return !isOffline;
      }
      status = HardwareStatus.offline;
      return false;
    } catch (e) {
      PosLogger.instance.warning(
        'WindowsSpooler',
        'Failed to query printer status for $name: $e',
      );
      status = HardwareStatus.offline;
      return false;
    }
  }

  @override
  Future<void> printReceipt(ReceiptDocument document) async {
    final bytes = ReceiptLayoutBuilder.buildEscPosBytes(
      document,
      profile: profile,
    );
    await printRaw(bytes);
    PosLogger.instance.info(
      'WindowsSpooler',
      'Receipt #${document.receiptNumber} successfully sent to Windows spooler printer "$name"',
    );
  }

  @override
  Future<void> printRaw(Uint8List bytes) async {
    lastSpoolJobs.add(bytes);

    if (!Platform.isWindows) {
      PosLogger.instance.info(
        'WindowsSpooler',
        '[Simulated Spooler] ${bytes.length} bytes spooled to "$name"',
      );
      return;
    }

    // Write bytes to temporary spool file
    final tempDir = AppPaths.instance.tempDir;
    final tempFile = File(
      '${tempDir.path}${Platform.pathSeparator}spool_${DateTime.now().millisecondsSinceEpoch}.bin',
    );
    await tempFile.writeAsBytes(bytes, flush: true);

    try {
      // Send raw binary file to Windows printer queue via PowerShell Raw Print
      // or copy /b command
      final psScript =
          '''
\$printerName = "$name";
\$filePath = "${tempFile.path.replaceAll(r'\', r'\\')}";
if (Test-Path \$filePath) {
    [System.IO.File]::ReadAllBytes(\$filePath) | Out-Null;
    # Spool directly to the shared/local print queue
    cmd /c "copy /b `"\$filePath`" `"\$printerName`"" | Out-Null;
}
''';
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        psScript,
      ]);

      if (result.exitCode != 0) {
        PosLogger.instance.warning(
          'WindowsSpooler',
          'Spooler command returned exitCode ${result.exitCode}: ${result.stderr}',
        );
        throw Exception(
          'Windows Spooler write failed (exit code ${result.exitCode}): ${result.stderr}',
        );
      }
    } finally {
      // Clean up temporary spool file
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  @override
  Future<void> openCashDrawer() async {
    if (profile.hasDrawerPort && profile.drawerKickCommand.isNotEmpty) {
      await printRaw(Uint8List.fromList(profile.drawerKickCommand));
      PosLogger.instance.info(
        'WindowsSpooler',
        'Drawer kick pulse spooled to "$name"',
      );
    }
  }

  @override
  Future<void> cutPaper() async {
    if (profile.hasCutter && profile.cutCommand.isNotEmpty) {
      await printRaw(Uint8List.fromList(profile.cutCommand));
      PosLogger.instance.info(
        'WindowsSpooler',
        'Paper cut command spooled to "$name"',
      );
    }
  }

  @override
  Future<void> disconnect() async {
    status = HardwareStatus.configured;
  }
}
