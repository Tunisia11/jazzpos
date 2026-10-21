// Characterization probes: PASS confirms the observed issue, not readiness.
// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member, use_build_context_synchronously
// Run with flutter test release_audit/evidence/2026-09-08-hardware/audit_probes_test.dart
import 'dart:async';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/catalog_service.dart';
import 'package:jazzpos/domain/services/inventory_service.dart';
import 'package:jazzpos/domain/services/sale_service.dart';
import 'package:jazzpos/hardware/barcode_scanner/scanner_input_service.dart';
import 'package:jazzpos/hardware/hardware_manager.dart';
import 'package:jazzpos/hardware/receipt_printer/printer_candidate.dart';
import 'package:jazzpos/hardware/receipt_printer/printer_scorer.dart';
import 'package:jazzpos/hardware/receipt_printer/receipt_rasterizer.dart';
import 'package:jazzpos/providers/cart_provider.dart';
import 'package:jazzpos/ui/screens/checkout/widgets/payment_dialog.dart';
import 'package:jazzpos/ui/widgets/barcode_scanner_listener.dart';

void key(
  LogicalKeyboardKey logical,
  PhysicalKeyboardKey physical, {
  String? character,
}) {
  HardwareKeyboard.instance.handleKeyEvent(
    KeyDownEvent(
      logicalKey: logical,
      physicalKey: physical,
      character: character,
      timeStamp: Duration.zero,
    ),
  );
  HardwareKeyboard.instance.handleKeyEvent(
    KeyUpEvent(
      logicalKey: logical,
      physicalKey: physical,
      timeStamp: Duration.zero,
    ),
  );
}

void burst() {
  key(LogicalKeyboardKey.digit1, PhysicalKeyboardKey.digit1, character: '1');
  key(LogicalKeyboardKey.digit2, PhysicalKeyboardKey.digit2, character: '2');
  key(LogicalKeyboardKey.digit3, PhysicalKeyboardKey.digit3, character: '3');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CONFIRMED: delayed Enter accepts stale keyboard burst', () async {
    final scanner = ScannerInputService();
    final scans = <String>[];
    final sub = scanner.onScan.listen(scans.add);
    await scanner.startListening();
    burst();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    key(LogicalKeyboardKey.enter, PhysicalKeyboardKey.enter);
    await Future<void>.delayed(Duration.zero);
    expect(scans, ['123']);
    await scanner.stopListening();
    await sub.cancel();
  });

  test('CONFIRMED: stop and restart retain an unfinished scan', () async {
    final scanner = ScannerInputService();
    final scans = <String>[];
    final sub = scanner.onScan.listen(scans.add);
    await scanner.startListening();
    burst();
    await scanner.stopListening();
    await scanner.startListening();
    key(LogicalKeyboardKey.enter, PhysicalKeyboardKey.enter);
    await Future<void>.delayed(Duration.zero);
    expect(scans, ['123']);
    await scanner.stopListening();
    await sub.cancel();
  });

  test('CONFIRMED: Tab suffix does not complete a scan', () async {
    final scanner = ScannerInputService();
    final scans = <String>[];
    final sub = scanner.onScan.listen(scans.add);
    await scanner.startListening();
    burst();
    key(LogicalKeyboardKey.tab, PhysicalKeyboardKey.tab);
    await Future<void>.delayed(Duration.zero);
    expect(scans, isEmpty);
    await scanner.stopListening();
    await sub.cancel();
  });

  test('CONFIRMED: unknown barcode can select a partial SKU match', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final inventory = InventoryService(db);
    final cart = CartNotifier(
      CatalogService(db, inventory),
      SaleService(db, inventory),
    );
    final now = DateTime.now();
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'audit-product',
            name: 'Wrong garment',
            defaultPriceMillimes: const drift.Value(45000),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            id: 'audit-variant',
            productId: 'audit-product',
            sku: 'SKU-123-OTHER',
            barcode: '9999999999999',
            createdAt: now,
            updatedAt: now,
          ),
        );
    expect(await cart.addItemByBarcode('123'), isTrue);
    expect(cart.state.items.single.barcode, '9999999999999');
    cart.dispose();
    await db.close();
  });

  testWidgets(
    'CONFIRMED: scanner listener invokes underlying callback while modal is open',
    (tester) async {
      final scanner = ScannerInputService();
      HardwareManager.instance.initialize(customBarcodeScanner: scanner);
      final received = <String>[];
      late BuildContext pageContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              pageContext = context;
              return BarcodeScannerListener(
                onBarcodeScanned: received.add,
                child: const Scaffold(),
              );
            },
          ),
        ),
      );
      unawaited(
        showDialog<void>(
          context: pageContext,
          builder: (_) => const AlertDialog(title: Text('Payment')),
        ),
      );
      await tester.pumpAndSettle();
      expect(ModalRoute.of(pageContext)!.isCurrent, isFalse);
      scanner.simulateScan('6191234567890');
      await tester.pump();
      expect(received, ['6191234567890']);
      await tester.pumpWidget(const SizedBox());
      await scanner.stopListening();
    },
  );

  test('CONFIRMED: Arabic raster test ignores its text argument', () {
    final a = ReceiptRasterizer.imageToMonochromeBytes(
      ReceiptRasterizer.createTestRasterPattern(text: 'مرحبا'),
    );
    final b = ReceiptRasterizer.imageToMonochromeBytes(
      ReceiptRasterizer.createTestRasterPattern(text: 'DIFFERENT TEXT'),
    );
    expect(a, orderedEquals(b));
  });

  test(
    'CONFIRMED: Zebra label queue can be high-confidence receipt candidate',
    () {
      final candidate = PrinterScorer.evaluate(
        name: 'Zebra ZD420',
        driverName: 'ZDesigner Thermal Label Printer',
        portName: 'USB001',
        isDefault: true,
      );
      expect(candidate.confidence, PrinterConfidence.high);
      expect(candidate.isReceiptPrinterCandidate, isTrue);
    },
  );

  testWidgets(
    'CONFIRMED: repeated decimal key throws from payment dialog build',
    (tester) async {
      final previousOnError = FlutterError.onError;
      final overflows = <FlutterErrorDetails>[];
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
          overflows.add(details);
        } else {
          previousOnError!(details);
        }
      };
      addTearDown(() => FlutterError.onError = previousOnError);
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('fr'),
            localizationsDelegates: [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: [Locale('fr'), Locale('en'), Locale('ar')],
            home: Scaffold(
              body: PaymentDialog(
                totalAmount: Money.fromMillimes(45000),
                storeId: 'audit-store',
                registerId: 'audit-register',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        overflows,
        isNotEmpty,
        reason: 'French payment layout also overflows before typing.',
      );
      await tester.tap(find.text('.').last);
      await tester.pump();
      await tester.tap(find.text('.').last);
      await tester.pump();
      expect(tester.takeException(), isA<FormatException>());
      await tester.pumpWidget(const SizedBox());
    },
  );
}
