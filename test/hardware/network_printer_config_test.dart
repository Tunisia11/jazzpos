import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/hardware/barcode_scanner/fake_barcode_scanner.dart';
import 'package:tracepos/hardware/cash_drawer/printer_kick_cash_drawer.dart';
import 'package:tracepos/hardware/hardware_manager.dart';
import 'package:tracepos/hardware/receipt_printer/esc_pos_network_printer.dart';
import 'package:tracepos/hardware/receipt_printer/printer_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Save and restore network ESC/POS printer survives HardwareManager restart', () async {
    final dir = await Directory.systemTemp.createTemp('net_config_');
    try {
      final manager = HardwareManager.forTesting(configDirectory: dir);
      manager.initialize(customBarcodeScanner: FakeBarcodeScanner());

      final profile = PrinterProfile.custom(
        name: 'Epson Net 80mm',
        paperWidthMm: 80,
        charactersPerLine: 48,
        hasCutter: true,
        hasDrawerPort: true,
        drawerKickCommand: const [27, 112, 0, 25, 250],
      );

      await manager.saveReceiptPrinter(
        'Network (192.168.1.150:9100)',
        transport: 'NETWORK',
        ipAddress: '192.168.1.150',
        port: 9100,
        profile: profile,
        drawerEnabled: true,
      );

      // Verify immediate activation
      expect(manager.configuredTransport, 'NETWORK');
      expect(manager.configuredNetworkIp, '192.168.1.150');
      expect(manager.configuredNetworkPort, 9100);
      expect(manager.receiptPrinter, isA<EscPosNetworkPrinter>());
      final netPrinter = manager.receiptPrinter as EscPosNetworkPrinter;
      expect(netPrinter.ipAddress, '192.168.1.150');
      expect(netPrinter.port, 9100);
      expect(manager.drawerEnabled, true);
      expect(manager.cashDrawer, isA<PrinterKickCashDrawer>());

      // Verify JSON file on disk
      final configFile = File('${dir.path}/hardware_config.json');
      expect(await configFile.exists(), true);
      final payload = jsonDecode(await configFile.readAsString());
      expect(payload['receiptPrinter']['transport'], 'NETWORK');
      expect(payload['receiptPrinter']['ipAddress'], '192.168.1.150');
      expect(payload['receiptPrinter']['port'], 9100);
      expect(payload['receiptPrinter']['paperWidth'], 80);

      // Simulate restart
      final restarted = HardwareManager.forTesting(configDirectory: dir);
      restarted.initialize(customBarcodeScanner: FakeBarcodeScanner());

      expect(restarted.configuredTransport, 'NETWORK');
      expect(restarted.configuredNetworkIp, '192.168.1.150');
      expect(restarted.configuredNetworkPort, 9100);
      expect(restarted.receiptPrinter, isA<EscPosNetworkPrinter>());
      final restartedNetPrinter = restarted.receiptPrinter as EscPosNetworkPrinter;
      expect(restartedNetPrinter.ipAddress, '192.168.1.150');
      expect(restartedNetPrinter.port, 9100);
      expect(restarted.drawerEnabled, true);
      expect(restarted.cashDrawer, isA<PrinterKickCashDrawer>());
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
