import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/hardware/hardware_manager.dart';
import 'package:tracepos/hardware/barcode_scanner/fake_barcode_scanner.dart';
import 'package:tracepos/hardware/cash_drawer/disabled_cash_drawer.dart';
import 'package:tracepos/hardware/cash_drawer/printer_kick_cash_drawer.dart';
import 'package:tracepos/hardware/receipt_printer/printer_profile.dart';
import 'package:tracepos/hardware/receipt_printer/printer_queue_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [58,80]) {
    for(final enabled in [false,true]) {
      test('$width mm profile and drawer=$enabled survive new manager',()async {
        final dir=await Directory.systemTemp.createTemp('trace_config_');
        try {
          final manager=HardwareManager.forTesting(configDirectory:dir);
          manager.initialize(customBarcodeScanner:FakeBarcodeScanner());
          final profile=PrinterProfile.custom(name:'Été $width',paperWidthMm:width,charactersPerLine:width==58?32:48,hasCutter:width==80,hasDrawerPort:enabled,drawerKickCommand:const [27,112,1,25,250]);
          await manager.saveReceiptPrinter('Caisse Éléonore',profile:profile,drawerEnabled:enabled);
          final restarted=HardwareManager.forTesting(configDirectory:dir);
          restarted.initialize(customBarcodeScanner:FakeBarcodeScanner());
          expect(restarted.receiptPrinter.name,'Caisse Éléonore');
          expect(restarted.receiptPrinter.profile.toJson(),profile.toJson());
          expect(restarted.drawerEnabled,enabled);
          if(enabled) {
            expect(restarted.cashDrawer,isA<PrinterKickCashDrawer>());
            expect((restarted.cashDrawer as PrinterKickCashDrawer).printer,same(restarted.receiptPrinter));
          } else {expect(restarted.cashDrawer,isA<DisabledCashDrawer>());}
          final payload=jsonDecode(await File('${dir.path}/hardware_config.json').readAsString());
          expect(payload['receiptPrinter']['transport'],'WINDOWS_SPOOLER');
          expect(payload['receiptPrinter']['drawerPin'],1);
          expect(payload['receiptPrinter']['encoding'],'PC850');
        } finally {await dir.delete(recursive:true);}
      });
    }
  }
  test('Save failure reaches caller and leaves active configuration intact',()async {
    final dir=await Directory.systemTemp.createTemp('trace_config_fail_');
    try {
      final manager=HardwareManager.forTesting(configDirectory:dir);
      manager.initialize(customBarcodeScanner:FakeBarcodeScanner());
      final original=manager.receiptPrinter;
      await Directory('${dir.path}/hardware_config.json.tmp').create();
      await expectLater(manager.saveReceiptPrinter('POS'),throwsA(isA<FileSystemException>()));
      expect(manager.configuredReceiptPrinterName,isNull);
      expect(manager.receiptPrinter,same(original));
    } finally {await dir.delete(recursive:true);}
  });
  test('Virtual queues excluded; suspicious label queues require UI confirmation',(){
    for(final name in ['Microsoft Print to PDF','OneNote','Fax','Microsoft XPS Document Writer']) {expect(PrinterQueuePolicy.isVirtual(name),true);}
    for(final name in ['Zebra ZD420','ZDesigner GK420','Godex','TSC']) {expect(PrinterQueuePolicy.looksLikeLabel(name),true);}
    expect(PrinterQueuePolicy.isVirtual('EPSON TM-T20III'),false);
    expect(PrinterQueuePolicy.looksLikeLabel('EPSON TM-T20III'),false);
  });
}
