import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/hardware/barcode_scanner/scanner_input_service.dart';
void key(LogicalKeyboardKey logical,PhysicalKeyboardKey physical,{String? character}) {
  HardwareKeyboard.instance.handleKeyEvent(KeyDownEvent(logicalKey:logical,physicalKey:physical,character:character,timeStamp:Duration.zero));
  HardwareKeyboard.instance.handleKeyEvent(KeyUpEvent(logicalKey:logical,physicalKey:physical,timeStamp:Duration.zero));
}
void burst() {key(LogicalKeyboardKey.digit1,PhysicalKeyboardKey.digit1,character:'1');key(LogicalKeyboardKey.digit2,PhysicalKeyboardKey.digit2,character:'2');key(LogicalKeyboardKey.digit3,PhysicalKeyboardKey.digit3,character:'3');}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for(final transition in ['stale','restart','reset']) {
    test('Reject unfinished barcode after $transition',()async {
      final scanner=ScannerInputService();final scans=<String>[];final sub=scanner.onScan.listen(scans.add);
      await scanner.startListening();burst();
      if(transition=='stale') await Future<void>.delayed(const Duration(milliseconds:150));
      if(transition=='restart'){await scanner.stopListening();await scanner.startListening();}
      if(transition=='reset')scanner.reset();
      key(LogicalKeyboardKey.enter,PhysicalKeyboardKey.enter);await pumpEventQueue();
      expect(scans,isEmpty);await scanner.stopListening();await sub.cancel();
    });
  }
  for(final tab in [false,true]) {
    test('Configured ${tab?'Tab':'Enter'} suffix accepts rapid burst',()async {
      final scanner=ScannerInputService(acceptTabTerminator:tab);final scans=<String>[];final sub=scanner.onScan.listen(scans.add);
      await scanner.startListening();burst();
      key(tab?LogicalKeyboardKey.tab:LogicalKeyboardKey.enter,tab?PhysicalKeyboardKey.tab:PhysicalKeyboardKey.enter);
      await pumpEventQueue();expect(scans,['123']);await scanner.stopListening();await sub.cancel();
    });
  }
}
