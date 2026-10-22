import 'dart:io';
import 'dart:typed_data';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/platform/app_paths.dart';
import 'package:jazzpos/core/platform/process_utils.dart';
import 'package:jazzpos/hardware/models/hardware_fingerprint.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';
import 'printer_profile.dart';
import 'receipt_document.dart';
import 'receipt_layout_builder.dart';
import 'receipt_printer_interface.dart';

/// Process runner signature for hermetic testability
typedef CupsProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  Duration timeout,
});

/// Native macOS CUPS Print Spooler transport (`MACOS_CUPS`).
/// Sends raw ESC/POS binary data directly through the macOS/Unix CUPS subsystem
/// using `/usr/bin/lpr -l` (literal/raw mode) or `/usr/bin/lp -o raw`.
class MacCupsPrinter implements ReceiptPrinter {
  @override
  final String name;

  @override
  final String connectionType = 'MACOS_CUPS';

  @override
  final PrinterProfile profile;

  @override
  HardwareStatus status = HardwareStatus.configured;

  final CupsProcessRunner _run;
  final List<Uint8List> lastPrintJobs = [];

  MacCupsPrinter({
    required this.name,
    this.profile = PrinterProfile.genericEscPos80,
    CupsProcessRunner? processRunner,
  }) : _run = processRunner ?? ProcessUtils.safeRun;

  @override
  HardwareFingerprint get fingerprint => HardwareFingerprint(
    transport: 'MACOS_CUPS',
    friendlyName: name,
    portOrAddress: 'cups',
  );

  @override
  Future<bool> connect() async {
    status = HardwareStatus.connecting;
    return isConnected();
  }

  @override
  Future<bool> isConnected() async {
    if (name.isEmpty) {
      status = HardwareStatus.notConfigured;
      return false;
    }

    try {
      final args = (name == 'default' || name.isEmpty)
          ? ['-d']
          : ['-p', name];
      final result = await _run(
        'lpstat',
        args,
        timeout: const Duration(seconds: 4),
      );

      final out = result.stdout.toString().toLowerCase();
      final err = result.stderr.toString().toLowerCase();

      if (result.exitCode == 0) {
        if (out.contains('disabled') || err.contains('disabled')) {
          status = HardwareStatus.offline;
        } else {
          status = HardwareStatus.ready;
        }
      } else {
        if (out.contains('unknown destination') ||
            err.contains('unknown destination') ||
            err.contains('no such file') ||
            err.contains('no destinations')) {
          status = HardwareStatus.missing;
        } else {
          status = HardwareStatus.offline;
        }
      }
    } catch (e) {
      PosLogger.instance.warning('mac_cups_printer', 'Ignored error: $e');
      status = HardwareStatus.unknown;
    }

    return status == HardwareStatus.ready;
  }

  @override
  Future<void> printReceipt(ReceiptDocument document) async {
    final bytes = ReceiptLayoutBuilder.buildEscPosBytes(
      document,
      profile: profile,
    );
    await printRaw(bytes);
    PosLogger.instance.info(
      'MacCupsPrinter',
      'Receipt #${document.receiptNumber} successfully sent to macOS CUPS printer "$name"',
    );
  }

  @override
  Future<void> printRaw(Uint8List bytes) async {
    if (bytes.isEmpty) throw ArgumentError('Empty print job');

    final root = AppPaths.instance.isInitialized
        ? AppPaths.instance.tempDir
        : Directory.systemTemp;
    final jobDir = await root.createTemp('trace_cups_');
    final tempFile = File(
      '${jobDir.path}${Platform.pathSeparator}receipt.bin',
    );

    try {
      await tempFile.writeAsBytes(bytes, flush: true);

      final cleanName = name.trim();
      if (cleanName.startsWith('-')) {
        throw ArgumentError('Invalid printer queue name: cannot start with a dash');
      }

      // Attempt 1: lpr -P <queue> -l <tempFile>
      // The -l flag tells CUPS to bypass PostScript/raster filters and output raw bytes
      final isDefaultQueue = (cleanName == 'default' || cleanName.isEmpty);
      final lprArgs = isDefaultQueue
          ? ['-l', tempFile.path]
          : ['-P', cleanName, '-l', tempFile.path];

      var result = await _run(
        'lpr',
        lprArgs,
        timeout: const Duration(seconds: 10),
      );

      // Attempt 2 fallback: lp -d <queue> -o raw <tempFile>
      if (result.exitCode != 0) {
        final lpArgs = isDefaultQueue
            ? ['-o', 'raw', tempFile.path]
            : ['-d', name, '-o', 'raw', tempFile.path];
        result = await _run(
          'lp',
          lpArgs,
          timeout: const Duration(seconds: 10),
        );
      }

      if (result.exitCode != 0) {
        status = HardwareStatus.error;
        final errorMsg = result.stderr.toString().trim().isNotEmpty
            ? result.stderr.toString().trim()
            : result.stdout.toString().trim();
        throw Exception(
          'Impression CUPS échouée sur "$name" (code ${result.exitCode}) : $errorMsg',
        );
      }

      status = HardwareStatus.ready;
      lastPrintJobs.add(Uint8List.fromList(bytes));
      if (lastPrintJobs.length > 10) lastPrintJobs.removeAt(0);
      PosLogger.instance.info(
        'MacCupsPrinter',
        'Direct raw ESC/POS job sent to macOS CUPS queue "$name" (${bytes.length} bytes)',
      );
    } finally {
      try {
        await jobDir.delete(recursive: true);
      } catch (e) { PosLogger.instance.warning('mac_cups_printer', 'Ignored error: $e'); }
    }
  }

  @override
  Future<void> openCashDrawer() async {
    if (profile.hasDrawerPort && profile.drawerKickCommand.isNotEmpty) {
      await printRaw(Uint8List.fromList(profile.drawerKickCommand));
      PosLogger.instance.info(
        'MacCupsPrinter',
        'Drawer kick pulse sent via CUPS queue "$name"',
      );
    }
  }

  @override
  Future<void> cutPaper() async {
    if (profile.hasCutter && profile.cutCommand.isNotEmpty) {
      await printRaw(Uint8List.fromList(profile.cutCommand));
      PosLogger.instance.info(
        'MacCupsPrinter',
        'Paper cut command sent via CUPS queue "$name"',
      );
    }
  }

  @override
  Future<void> disconnect() async {
    status = HardwareStatus.configured;
  }
}
