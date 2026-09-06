import 'dart:io';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';
import 'cash_drawer_interface.dart';

/// Cash drawer triggered directly via a dedicated serial COM port trigger box.
class SerialCashDrawer implements CashDrawer {
  @override
  final String name;

  final String comPort; // e.g. "COM2"
  final bool operatorConfirmed;

  @override
  final CashDrawerMode mode = CashDrawerMode.serial;

  bool _isTested = false;

  @override
  bool get isTested => _isTested;

  @override
  HardwareStatus get status =>
      _isTested ? HardwareStatus.ready : HardwareStatus.configured;

  SerialCashDrawer({
    required this.name,
    required this.comPort,
    this.operatorConfirmed = false,
  });

  @override
  Future<void> openDrawer() async {
    if (!operatorConfirmed) {
      throw Exception(
        'Refusing to send drawer pulse to unconfirmed COM port $comPort',
      );
    }

    if (!Platform.isWindows) {
      PosLogger.instance.info(
        'CashDrawer',
        '[Simulated] Serial drawer kick on $comPort',
      );
      _isTested = true;
      return;
    }

    try {
      // Send pulse sequence (e.g. byte 0x01 or DTR toggle)
      final temp = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}drawer_${DateTime.now().millisecondsSinceEpoch}.bin',
      );
      await temp.writeAsBytes([0x1B, 0x70, 0x00, 0x19, 0xFA]);
      await Process.run('cmd', ['/c', 'copy', '/b', temp.path, comPort]);
      try {
        await temp.delete();
      } catch (_) {}
      _isTested = true;
      PosLogger.instance.info(
        'CashDrawer',
        'Fired drawer kick pulse on serial port $comPort',
      );
    } catch (e) {
      throw Exception('Failed to trigger serial cash drawer on $comPort: $e');
    }
  }
}
