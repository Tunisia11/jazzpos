import 'dart:convert';
import 'windows_raw_print_bridge.dart';
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

/// First-class Windows Print Spooler transport (`WINDOWS_SPOOLER`).
/// Sends raw ESC/POS bytes directly through the Windows print spooler subsystem
/// to any installed printer driver without altering the receipt byte stream.
typedef SpoolerProcessRunner = Future<ProcessResult> Function(String executable, List<String> arguments, {Duration timeout});

class WindowsSpoolerPrinter implements ReceiptPrinter {
  @override
  final String name;

  @override
  final String connectionType = 'WINDOWS_SPOOLER';

  @override
  final PrinterProfile profile;

  @override
  HardwareStatus status = HardwareStatus.configured;

  final SpoolerProcessRunner _run;
  final bool _canUseSpooler;
  int? lastJobId;
  final String? driverName;
  final String? portName;
  final List<Uint8List> lastSpoolJobs = [];

  WindowsSpoolerPrinter({
    required this.name,
    this.driverName,
    this.portName,
    this.profile = PrinterProfile.genericWindows,
    SpoolerProcessRunner? processRunner,
  }) : _run = processRunner ?? ProcessUtils.safeRun,
       _canUseSpooler = Platform.isWindows || processRunner != null;

  @override
  HardwareFingerprint get fingerprint => HardwareFingerprint(
    transport: 'WINDOWS_SPOOLER',
    friendlyName: name,
    portOrAddress: portName,
  );

  @override
  Future<bool> connect() async {
    status = HardwareStatus.connecting;
    return isConnected();
  }

  @override
  Future<bool> isConnected() async {
    if (!_canUseSpooler) { status = HardwareStatus.unsupported; return false; }
    status = HardwareStatus.unknown;
    try {
      final result = await _run('powershell', WindowsRawPrintBridge.arguments({'queueName':name}, print:false), timeout:const Duration(seconds:5));
      final value = jsonDecode(result.stdout.toString().trim());
      if (result.exitCode == 0 && value is Map && value['success'] == true && value['exists'] is bool) {
        status = HardwareStatus.values.where((s)=>s.value == value['status']).firstOrNull ?? HardwareStatus.unknown;
        if (value['exists'] == false) status = HardwareStatus.missing;
      }
    } catch (e) { PosLogger.instance.warning('windows_spooler_printer', 'Ignored error: $e'); status = HardwareStatus.unknown; }
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
      'WindowsSpooler',
      'Receipt #${document.receiptNumber} successfully sent to Windows spooler printer "$name"',
    );
  }

  @override
  Future<void> printRaw(Uint8List bytes) async {
    if (!_canUseSpooler) { status = HardwareStatus.unsupported; throw UnsupportedError('Windows printing requires Windows.'); }
    if (bytes.isEmpty) throw ArgumentError('Empty print job');
    final root = AppPaths.instance.isInitialized ? AppPaths.instance.tempDir : Directory.systemTemp;
    final jobDir = await root.createTemp('trace_spool_');
    final tempFile = File('${jobDir.path}${Platform.pathSeparator}receipt.bin');
    try {
      await tempFile.writeAsBytes(bytes, flush:true);
      final result = await _run('powershell', WindowsRawPrintBridge.arguments({'queueName':name, 'filePath':tempFile.path}, print:true), timeout:const Duration(seconds:15));
      Map? value;
      try { final decoded = jsonDecode(result.stdout.toString().trim()); if (decoded is Map) value=decoded; } catch (e) { PosLogger.instance.warning('windows_spooler_printer', 'Ignored error: $e'); }
      if (result.exitCode != 0 || value?['success'] != true || value?['jobId'] is! int ||
          (value!['jobId'] as int) <= 0 || value['bytesWritten'] != bytes.length || value['queueName'] != name || value['delivery'] != 'queued') {
        status = HardwareStatus.error;
        throw Exception('Impression non confirmée : ${value?['error'] ?? result.stderr}. Livraison incertaine : vérifiez la file Windows avant de réimprimer.');
      }
      lastJobId = value['jobId'] as int;
      lastSpoolJobs.add(Uint8List.fromList(bytes));
      if (lastSpoolJobs.length > 10) lastSpoolJobs.removeAt(0);
      PosLogger.instance.info('WindowsSpooler', 'Queued job $lastJobId ($name), ${bytes.length} bytes. Paper output unverified.');
    } finally {
      try { await jobDir.delete(recursive:true); } catch (e) { PosLogger.instance.warning('windows_spooler_printer', 'Ignored error: $e'); }
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
