import 'dart:io';
import 'dart:typed_data';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/hardware/models/hardware_fingerprint.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';
import 'printer_profile.dart';
import 'receipt_document.dart';
import 'receipt_layout_builder.dart';
import 'receipt_printer_interface.dart';

/// Direct Serial / COM port raw ESC/POS printer transport.
/// Safety rule: Never opens or sends bytes to an unconfirmed serial port.
class EscPosSerialPrinter implements ReceiptPrinter {
  @override
  final String name;

  @override
  final String connectionType = 'SERIAL';

  final String comPort; // e.g. "COM1", "COM3"
  final int baudRate; // default 9600 or 115200
  final bool operatorConfirmed;

  @override
  final PrinterProfile profile;

  @override
  HardwareStatus status = HardwareStatus.configured;

  final List<Uint8List> lastPrintedBytes = [];

  EscPosSerialPrinter({
    required this.name,
    required this.comPort,
    this.baudRate = 9600,
    this.operatorConfirmed = false,
    this.profile = PrinterProfile.genericEscPos80,
  });

  @override
  HardwareFingerprint get fingerprint => HardwareFingerprint(
    transport: 'SERIAL',
    portOrAddress: comPort,
    friendlyName: name,
  );

  @override
  Future<bool> connect() async {
    if (!operatorConfirmed) {
      PosLogger.instance.warning(
        'SerialPrinter',
        'Refusing to send bytes to unconfirmed COM port $comPort. Operator confirmation required.',
      );
      status = HardwareStatus.unsupported;
      return false;
    }

    status = HardwareStatus.connecting;
    final ok = await isConnected();
    status = ok ? HardwareStatus.ready : HardwareStatus.offline;
    return ok;
  }

  @override
  Future<bool> isConnected() async {
    if (!Platform.isWindows) {
      status = HardwareStatus.ready;
      return true;
    }

    try {
      // Check if COM port is present in Windows serial ports
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '[System.IO.Ports.SerialPort]::getportnames() -contains "$comPort"',
      ]);
      final isPresent =
          (result.stdout as String).trim().toLowerCase() == 'true';
      status = isPresent ? HardwareStatus.ready : HardwareStatus.offline;
      return isPresent;
    } catch (_) {
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
      'SerialPrinter',
      'Sent receipt #${document.receiptNumber} to Serial printer on $comPort',
    );
  }

  @override
  Future<void> printRaw(Uint8List bytes) async {
    if (!operatorConfirmed) {
      throw Exception('Cannot write to unconfirmed serial port $comPort');
    }

    lastPrintedBytes.add(bytes);

    if (!Platform.isWindows) {
      PosLogger.instance.info(
        'SerialPrinter',
        '[Simulated Serial] ${bytes.length} bytes sent to $comPort',
      );
      return;
    }

    try {
      final tempFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}serial_${DateTime.now().millisecondsSinceEpoch}.bin',
      );
      await tempFile.writeAsBytes(bytes);
      // Windows command to redirect binary file to COM port
      await Process.run('cmd', [
        '/c',
        'mode',
        '$comPort:BAUD=$baudRate',
        'PARITY=N',
        'DATA=8',
        'STOP=1',
      ]);
      await Process.run('cmd', ['/c', 'copy', '/b', tempFile.path, comPort]);
      try {
        await tempFile.delete();
      } catch (_) {}
    } catch (e) {
      status = HardwareStatus.error;
      throw Exception('Serial write error on $comPort: $e');
    }
  }

  @override
  Future<void> openCashDrawer() async {
    if (profile.hasDrawerPort && profile.drawerKickCommand.isNotEmpty) {
      await printRaw(Uint8List.fromList(profile.drawerKickCommand));
    }
  }

  @override
  Future<void> cutPaper() async {
    if (profile.hasCutter && profile.cutCommand.isNotEmpty) {
      await printRaw(Uint8List.fromList(profile.cutCommand));
    }
  }

  @override
  Future<void> disconnect() async {
    status = HardwareStatus.configured;
  }
}
