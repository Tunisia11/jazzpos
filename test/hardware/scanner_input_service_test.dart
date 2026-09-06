import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/hardware/barcode_scanner/scanner_input_service.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScannerInputService', () {
    late ScannerInputService scanner;

    setUp(() {
      scanner = ScannerInputService();
    });

    tearDown(() async {
      await scanner.stopListening();
    });

    test(
      'initial status is configured and transitions to ready on startListening',
      () async {
        expect(scanner.status, equals(HardwareStatus.configured));
        await scanner.startListening();
        expect(scanner.status, equals(HardwareStatus.ready));
        await scanner.stopListening();
        expect(scanner.status, equals(HardwareStatus.configured));
      },
    );

    test('fingerprint reflects KEYBOARD_WEDGE transport', () {
      final fp = scanner.fingerprint;
      expect(fp.transport, equals('KEYBOARD_WEDGE'));
      expect(fp.toCanonicalKey(), contains('KEYBOARD_WEDGE'));
    });

    test(
      'simulateScan emits barcode to onScan and onTestEvent streams',
      () async {
        const testCode = '6191234567890';
        String? emittedCode;
        ScannerTestEvent? emittedEvent;

        final scanSub = scanner.onScan.listen((code) => emittedCode = code);
        final eventSub = scanner.onTestEvent.listen(
          (event) => emittedEvent = event,
        );

        scanner.simulateScan(testCode);

        await pumpEventQueue();

        expect(emittedCode, equals(testCode));
        expect(emittedEvent, isNotNull);
        expect(emittedEvent!.barcode, equals(testCode));
        expect(emittedEvent!.characterCount, equals(13));
        expect(emittedEvent!.averageInterKeyMs, lessThan(80));

        final json = emittedEvent!.toJson();
        expect(json['barcode'], equals(testCode));
        expect(json['characterCount'], equals(13));

        await scanSub.cancel();
        await eventSub.cancel();
      },
    );
  });
}
