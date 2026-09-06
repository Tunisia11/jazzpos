import 'dart:io';
import 'dart:typed_data';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';
import 'customer_display_interface.dart';

/// 2x20 VFD Line Pole Customer Display communicating over serial COM port (ESC/POS / CD5220).
class SerialCustomerDisplay implements CustomerDisplay {
  @override
  final String name;

  final String comPort;
  final int baudRate;
  final bool operatorConfirmed;

  @override
  final CustomerDisplayMode mode = CustomerDisplayMode.serial;

  @override
  HardwareStatus status = HardwareStatus.configured;

  SerialCustomerDisplay({
    required this.name,
    required this.comPort,
    this.baudRate = 9600,
    this.operatorConfirmed = false,
  });

  @override
  Future<void> showWelcome() async {
    await clear();
    await _sendLines('   BIENVENUE CHEZ   ', '      JAZZ POS      ');
  }

  @override
  Future<void> showItem({
    required String productName,
    required Money price,
    required Money total,
  }) async {
    final line1 = productName.length > 20
        ? productName.substring(0, 20)
        : productName.padRight(20);
    final priceStr = price.format();
    final line2 = 'PRIX: ${priceStr.padLeft(14)}';
    await _sendLines(line1, line2);
  }

  @override
  Future<void> showTotal({required Money total, required Money change}) async {
    final totalStr = total.format();
    final line1 = 'TOTAL: ${totalStr.padLeft(13)}';
    final changeStr = change.format();
    final line2 = change > Money.zero
        ? 'RENDU: ${changeStr.padLeft(13)}'
        : 'MERCI DE VOTRE VISITE';
    await _sendLines(line1, line2);
  }

  @override
  Future<void> clear() async {
    // Standard VFD clear command: 0x0C (Form Feed) or ESC @
    await _sendBytes(Uint8List.fromList([0x0C]));
  }

  Future<void> _sendLines(String l1, String l2) async {
    final bytes = <int>[];
    // Move to line 1, pos 1
    bytes.addAll([0x1B, 0x51, 0x41]); // ESC Q A
    bytes.addAll(l1.padRight(20).codeUnits);
    bytes.addAll([0x0D]); // CR
    // Move to line 2, pos 1
    bytes.addAll([0x1B, 0x51, 0x42]); // ESC Q B
    bytes.addAll(l2.padRight(20).codeUnits);
    bytes.addAll([0x0D]);

    await _sendBytes(Uint8List.fromList(bytes));
  }

  Future<void> _sendBytes(Uint8List bytes) async {
    if (!operatorConfirmed) return;

    if (!Platform.isWindows) {
      PosLogger.instance.info(
        'VFDDisplay',
        '[Simulated Serial] Sent ${bytes.length} bytes to $comPort',
      );
      return;
    }

    try {
      final temp = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}vfd_${DateTime.now().millisecondsSinceEpoch}.bin',
      );
      await temp.writeAsBytes(bytes);
      await Process.run('cmd', ['/c', 'copy', '/b', temp.path, comPort]);
      try {
        await temp.delete();
      } catch (_) {}
    } catch (e) {
      status = HardwareStatus.error;
      PosLogger.instance.warning(
        'VFDDisplay',
        'Error sending bytes to VFD display on $comPort: $e',
      );
    }
  }
}
