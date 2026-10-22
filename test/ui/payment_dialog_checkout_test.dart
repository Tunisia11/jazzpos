import 'dart:async';
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/core/constants/app_constants.dart';
import 'package:tracepos/core/localization/app_localizations_delegate.dart';
import 'package:tracepos/core/money/money.dart';
import 'package:tracepos/data/database/app_database.dart';
import 'package:tracepos/domain/models/checkout_request.dart';
import 'package:tracepos/domain/services/pos_initialization_service.dart';
import 'package:tracepos/domain/services/sale_service.dart';
import 'package:tracepos/domain/services/inventory_service.dart';
import 'package:tracepos/hardware/hardware_manager.dart';
import 'package:tracepos/hardware/receipt_printer/fake_receipt_printer.dart';
import 'package:tracepos/hardware/cash_drawer/fake_cash_drawer.dart';
import 'package:tracepos/providers/app_providers.dart';
import 'package:tracepos/providers/auth_provider.dart';
import 'package:tracepos/providers/cart_provider.dart';
import 'package:tracepos/providers/shift_provider.dart';
import 'package:tracepos/ui/screens/checkout/widgets/payment_dialog.dart';

class ControlledSaleService extends SaleService {
  ControlledSaleService(super.db, super.inventoryService);
  bool fail = false;
  Completer<void>? gate;
  @override Future<SaleCompletedResult> checkout(CheckoutRequest request) async {
    if (gate != null) await gate!.future;
    if (fail) throw StateError('Forced checkout service failure');
    return super.checkout(request);
  }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late ProviderContainer container;
  late ControlledSaleService service;
  late String registerId;
  late FakeReceiptPrinter printer;
  setUp(() async {
    db=AppDatabase(NativeDatabase.memory());
    final inventory=InventoryService(db);
    service=ControlledSaleService(db,inventory);
    container=ProviderContainer(overrides:[databaseProvider.overrideWithValue(db),saleServiceProvider.overrideWithValue(service)]);
    await PosInitializationService(db).initializePos(companyName:'Boutique Élégance',storeName:'Boutique',registerCode:'REG-001',ownerUsername:'owner',ownerDisplayName:'Owner',ownerPin:'1234');
    expect(await container.read(authNotifierProvider.notifier).login('owner','1234'),true);
    final user=container.read(authNotifierProvider).user!;
    registerId=(await db.select(db.registers).getSingle()).id;
    await container.read(shiftNotifierProvider.notifier).openShift(registerId:registerId,cashierId:user.id,openingCash:Money.zero);
    final now=DateTime.now();
    await db.into(db.products).insert(ProductsCompanion.insert(id:'product',name:'Robe bleu M',defaultPriceMillimes:const d.Value(45000),createdAt:now,updatedAt:now));
    await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(id:'variant',productId:'product',sku:'ROBE-M-BLEU',barcode:'001234567890',createdAt:now,updatedAt:now));
    final location=await inventory.getDefaultLocation('STORE-01');
    await inventory.recordMovement(variantId:'variant',movementType:AppConstants.movementInitial,quantityDelta:10,toLocationId:location.id,actorId:user.id,reason:'Disposable fixture');
    expect(await container.read(cartNotifierProvider.notifier).addItemByBarcode('001234567890'),true);
    HardwareManager.instance.initialize();
    printer=FakeReceiptPrinter();
    HardwareManager.instance.receiptPrinter=printer;
    HardwareManager.instance.cashDrawer=FakeCashDrawer();
  });
  tearDown(()async {container.dispose(); await db.close();});

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize=const Size(1366,768); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(container:container,child:MaterialApp(
      locale:const Locale('fr'),supportedLocales:const [Locale('fr')],localizationsDelegates:const [AppLocalizationsDelegate(),GlobalMaterialLocalizations.delegate,GlobalWidgetsLocalizations.delegate,GlobalCupertinoLocalizations.delegate],
      home:Scaffold(body:Builder(builder:(context)=>TextButton(onPressed:()=>PaymentDialog.show(context,totalAmount:const Money.fromMillimes(45000),storeId:'STORE-01',registerId:registerId),child:const Text('Payment')))),
    )));
    await tester.tap(find.text('Payment'));await tester.pumpAndSettle();
    expect(container.read(cartNotifierProvider).isLocked,true);
  }
  Future<void> submit(WidgetTester tester)async {
    final button=find.byIcon(Icons.check_circle_outline);await tester.ensureVisible(button);await tester.tap(button);await tester.pump();
    // Real SQLite and print futures must run outside the widget's fake clock.
    for(var i=0;i<20;i++) {await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:15)));await tester.pump(const Duration(milliseconds:50));}
    if (service.gate == null || service.gate!.isCompleted) await tester.pumpAndSettle();
  }
  testWidgets('Committed cash sale unlocks and saves exactly once',(tester)async {
    await open(tester);await submit(tester);
    expect(tester.takeException(),isNull);expect(find.byType(PaymentDialog),findsNothing);
    expect(container.read(cartNotifierProvider).isLocked,false);
    expect(container.read(cartNotifierProvider).items,isEmpty);
    expect(await tester.runAsync(()=>db.select(db.sales).get()),hasLength(1));
    expect(printer.printedDocuments,hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Printer fails after commit: saved sale notice, close unlocks, no second sale',(tester)async {
    printer.simulateDisconnect();
    await open(tester);await submit(tester);
    expect(tester.takeException(),isNull);expect(find.text('Vente enregistrée'),findsOneWidget);
    expect(container.read(cartNotifierProvider).isLocked,false);
    expect(await tester.runAsync(()=>db.select(db.sales).get()),hasLength(1));
    await tester.tap(find.text('Fermer'));await tester.pumpAndSettle();
    expect(await tester.runAsync(()=>db.select(db.sales).get()),hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Service exception leaves modal locked; closing releases it',(tester)async {
    service.fail=true;await open(tester);await submit(tester);
    expect(tester.takeException(),isNull);expect(find.byType(PaymentDialog),findsOneWidget);
    expect(find.textContaining('Forced checkout service failure'),findsOneWidget);
    expect(container.read(cartNotifierProvider).isLocked,true);
    expect(await container.read(cartNotifierProvider.notifier).addItemByBarcode('001234567890'),false);
    await tester.ensureVisible(find.byIcon(Icons.close));await tester.tap(find.byIcon(Icons.close));await tester.pumpAndSettle();
    expect(container.read(cartNotifierProvider).isLocked,false);
    expect(await tester.runAsync(()=>db.select(db.sales).get()),isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Insufficient tender remains locked; cancel releases after validation',(tester)async {
    await open(tester);await tester.tap(find.text('1').last);await submit(tester);
    expect(find.byType(PaymentDialog),findsOneWidget);expect(container.read(cartNotifierProvider).isLocked,true);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);await tester.pumpAndSettle();
    expect(container.read(cartNotifierProvider).isLocked,false);
    expect(await tester.runAsync(()=>db.select(db.sales).get()),isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('In-flight payment rejects back, scanner and duplicate submit',(tester)async {
    service.gate=Completer<void>();await open(tester);await submit(tester);
    expect(container.read(cartNotifierProvider).isProcessing,true);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);await tester.pump();
    await Navigator.of(tester.element(find.byType(PaymentDialog))).maybePop();await tester.pump();
    expect(find.byType(PaymentDialog),findsOneWidget);
    expect(await container.read(cartNotifierProvider.notifier).addItemByBarcode('001234567890'),false);
    service.gate!.complete();
    for(var i=0;i<20;i++){await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:15)));await tester.pump(const Duration(milliseconds:50));}
    await tester.pumpAndSettle();
    expect(tester.takeException(),isNull);expect(container.read(cartNotifierProvider).isLocked,false);
    expect(await tester.runAsync(()=>db.select(db.sales).get()),hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });
}
