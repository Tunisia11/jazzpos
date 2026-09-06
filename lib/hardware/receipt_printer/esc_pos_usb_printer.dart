import 'dart:io';
import 'dart:typed_data';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/hardware/models/hardware_fingerprint.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';
import 'printer_profile.dart';
import 'receipt_document.dart';
import 'receipt_layout_builder.dart';
import 'receipt_printer_interface.dart';

/// Direct USB Raw ESC/POS Printer Transport.
class EscPosUsbPrinter implements ReceiptPrinter {
  @override
  final String name;

  @override
  final String connectionType = 'USB';

  final String? vendorId;
  final String? productId;
  final String? serialNumber;
  final String? usbPortName; // e.g. "USB001"

  @override
  final PrinterProfile profile;

  @override
  HardwareStatus status = HardwareStatus.configured;

  final List<Uint8List> lastPrintedBytes = [];

  EscPosUsbPrinter({
    required this.name,
    this.vendorId,
    this.productId,
    this.serialNumber,
    this.usbPortName,
    this.profile = PrinterProfile.genericEscPos80,
  });

  @override
  HardwareFingerprint get fingerprint => HardwareFingerprint(
    transport: 'USB',
    vendorId: vendorId,
    productId: productId,
    serialNumber: serialNumber,
    portOrAddress: usbPortName,
    friendlyName: name,
  );

  @override
  Future<bool> connect() async {
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
      // Check if USB device is present in PnP
      final filter = vendorId != null
          ? 'DeviceID -like "*VID_$vendorId*"'
          : 'Name -like "*$name*"';
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Get-CimInstance Win32_PnPEntity | Where-Object { $filter -and \$_.Status -eq "OK" } | Select-Object -First 1',
      ]);
      final isFound =
          result.exitCode == 0 && (result.stdout as String).trim().isNotEmpty;
      status = isFound ? HardwareStatus.ready : HardwareStatus.offline;
      return isFound;
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
      'UsbPrinter',
      'Sent receipt #${document.receiptNumber} to USB printer "$name"',
    );
  }

  @override
  Future<void> printRaw(Uint8List bytes) async {
    lastPrintedBytes.add(bytes);

    if (!Platform.isWindows) {
      PosLogger.instance.info(
        'UsbPrinter',
        '[Simulated USB] ${bytes.length} bytes sent to "$name"',
      );
      return;
    }

    // On Windows, if usbPortName is available (e.g. USB001), send directly
    final target = usbPortName ?? name;
    try {
      final tempFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}usb_print_${DateTime.now().millisecondsSinceEpoch}.bin',
      );
      await tempFile.writeAsBytes(bytes);
      await Process.run('cmd', ['/c', 'copy', '/b', tempFile.path, target]);
      try {
        await tempFile.delete();
      } catch (_) {}
    } catch (e) {
      status = HardwareStatus.error;
      throw Exception('USB Printer write error: $e');
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
