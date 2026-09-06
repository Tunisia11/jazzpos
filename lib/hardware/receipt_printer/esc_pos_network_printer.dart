import 'dart:io';
import 'dart:typed_data';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/hardware/models/hardware_fingerprint.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';
import 'printer_profile.dart';
import 'receipt_document.dart';
import 'receipt_layout_builder.dart';
import 'receipt_printer_interface.dart';

/// Direct Raw TCP Network ESC/POS printer transport (typically port 9100).
class EscPosNetworkPrinter implements ReceiptPrinter {
  @override
  final String name;

  @override
  final String connectionType = 'NETWORK';

  final String ipAddress;
  final int port;
  final Duration timeout;

  @override
  final PrinterProfile profile;

  @override
  HardwareStatus status = HardwareStatus.configured;

  Socket? _socket;
  final List<Uint8List> lastPrintedBytes = [];

  EscPosNetworkPrinter({
    required this.name,
    required this.ipAddress,
    this.port = 9100,
    this.timeout = const Duration(seconds: 3),
    this.profile = PrinterProfile.genericEscPos80,
  });

  @override
  HardwareFingerprint get fingerprint => HardwareFingerprint(
    transport: 'NETWORK',
    portOrAddress: '$ipAddress:$port',
    friendlyName: name,
  );

  @override
  Future<bool> connect() async {
    status = HardwareStatus.connecting;
    try {
      _socket = await Socket.connect(ipAddress, port, timeout: timeout);
      status = HardwareStatus.ready;
      PosLogger.instance.info(
        'NetworkPrinter',
        'Connected to network printer at $ipAddress:$port',
      );
      return true;
    } catch (e) {
      status = HardwareStatus.offline;
      PosLogger.instance.warning(
        'NetworkPrinter',
        'Failed to connect to network printer at $ipAddress:$port: $e',
      );
      return false;
    }
  }

  @override
  Future<bool> isConnected() async {
    if (_socket != null) return true;
    return await connect();
  }

  @override
  Future<void> printReceipt(ReceiptDocument document) async {
    final bytes = ReceiptLayoutBuilder.buildEscPosBytes(
      document,
      profile: profile,
    );
    await printRaw(bytes);
    PosLogger.instance.info(
      'NetworkPrinter',
      'Sent receipt #${document.receiptNumber} to network printer at $ipAddress:$port',
    );
  }

  @override
  Future<void> printRaw(Uint8List bytes) async {
    lastPrintedBytes.add(bytes);

    if (_socket == null) {
      final ok = await connect();
      if (!ok) {
        status = HardwareStatus.offline;
        throw Exception(
          'Cannot connect to network printer at $ipAddress:$port',
        );
      }
    }

    try {
      _socket!.add(bytes);
      await _socket!.flush();
    } catch (e) {
      status = HardwareStatus.error;
      await disconnect();
      throw Exception('Network printer write error: $e');
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
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    status = HardwareStatus.configured;
  }
}
