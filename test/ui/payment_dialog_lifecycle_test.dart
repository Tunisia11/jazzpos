import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/core/localization/app_localizations_delegate.dart';
import 'package:tracepos/core/money/money.dart';
import 'package:tracepos/data/database/app_database.dart';
import 'package:tracepos/hardware/hardware_manager.dart';
import 'package:tracepos/providers/app_providers.dart';
import 'package:tracepos/providers/cart_provider.dart';
import 'package:tracepos/ui/screens/checkout/widgets/payment_dialog.dart';

void main() {
  for (final size in [const Size(1366,768), const Size(1440,900), const Size(1920,1080)]) {
    testWidgets('Real French payment close, decimal, validation and cycles at $size', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
      HardwareManager.instance.initialize();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(UncontrolledProviderScope(container:container, child:MaterialApp(
        locale:const Locale('fr'), supportedLocales:const [Locale('fr')],
        localizationsDelegates:const [AppLocalizationsDelegate(),GlobalMaterialLocalizations.delegate,GlobalWidgetsLocalizations.delegate,GlobalCupertinoLocalizations.delegate],
        home:Scaffold(body:Builder(builder:(context)=>TextButton(onPressed:()=>PaymentDialog.show(context,totalAmount:const Money.fromMillimes(45000),storeId:'store',registerId:'register'),child:const Text('Open payment')))),
      )));
      for (final close in ['X','Escape','cancel','back']) {
        await tester.tap(find.text('Open payment'));
        await tester.pumpAndSettle();
        expect(container.read(cartNotifierProvider).isLocked,isTrue);
        expect(tester.takeException(),isNull);
        for (final key in ['.','.','1','2','3','4']) {
          await tester.tap(find.text(key).last);
          await tester.pump();
          expect(tester.takeException(),isNull);
        }
        expect(find.text('0.123'),findsOneWidget);
        // Missing authenticated cashier is a real validation failure.
        final submit = find.byIcon(Icons.check_circle_outline);
        expect(submit, findsOneWidget);
        {
          await tester.ensureVisible(submit); await tester.tap(submit); await tester.pumpAndSettle();
          expect(container.read(cartNotifierProvider).isLocked,isTrue);
          expect(find.byType(PaymentDialog),findsOneWidget);
        }
        switch(close) {
          case 'X': await tester.ensureVisible(find.byIcon(Icons.close)); await tester.tap(find.byIcon(Icons.close));
          case 'Escape': await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          case 'cancel': final cancel=find.textContaining('(Echap)'); await tester.ensureVisible(cancel); await tester.tap(cancel);
          case 'back': Navigator.of(tester.element(find.byType(PaymentDialog))).pop();
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(),isNull);
        expect(find.byType(PaymentDialog),findsNothing);
        expect(container.read(cartNotifierProvider).isLocked,isFalse);
      }
      await tester.pumpWidget(const SizedBox());
      container.dispose(); await tester.runAsync(db.close);
    });
  }
}
