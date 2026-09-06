import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/core/localization/translations/translations_ar.dart';
import 'package:jazzpos/core/localization/translations/translations_en.dart';
import 'package:jazzpos/core/localization/translations/translations_fr.dart';

void main() {
  group('Localization and RTL Test Suite', () {
    test('AppLocalizationsDelegate supports fr, ar, en', () {
      const delegate = AppLocalizationsDelegate();
      expect(delegate.isSupported(const Locale('fr')), isTrue);
      expect(delegate.isSupported(const Locale('ar')), isTrue);
      expect(delegate.isSupported(const Locale('en')), isTrue);
      expect(delegate.isSupported(const Locale('es')), isFalse);
    });

    test('Locale-specific RTL and LTR properties', () {
      final fr = AppLocalizationsFr();
      final ar = AppLocalizationsAr();
      final en = AppLocalizationsEn();

      expect(fr.locale.languageCode, 'fr');
      expect(fr.isRtl, isFalse);
      expect(fr.textDirection, TextDirection.ltr);

      expect(ar.locale.languageCode, 'ar');
      expect(ar.isRtl, isTrue);
      expect(ar.textDirection, TextDirection.rtl);

      expect(en.locale.languageCode, 'en');
      expect(en.isRtl, isFalse);
      expect(en.textDirection, TextDirection.ltr);
    });

    test('Currency formatting per locale', () {
      final fr = AppLocalizationsFr();
      final ar = AppLocalizationsAr();
      final en = AppLocalizationsEn();

      expect(fr.formatCurrency(45.5), '45.500 TND');
      expect(ar.formatCurrency(45.5), '45.500 د.ت');
      expect(en.formatCurrency(45.5), '45.500 TND');
    });

    test('Translation key completeness and non-empty assertions', () {
      final fr = AppLocalizationsFr();
      final ar = AppLocalizationsAr();
      final en = AppLocalizationsEn();

      // Navigation & Shell
      expect(fr.navPos.isNotEmpty, isTrue);
      expect(ar.navPos.isNotEmpty, isTrue);
      expect(en.navPos.isNotEmpty, isTrue);

      expect(fr.navCatalog.isNotEmpty, isTrue);
      expect(ar.navCatalog.isNotEmpty, isTrue);
      expect(en.navCatalog.isNotEmpty, isTrue);

      expect(fr.navInventory.isNotEmpty, isTrue);
      expect(ar.navInventory.isNotEmpty, isTrue);
      expect(en.navInventory.isNotEmpty, isTrue);

      expect(fr.navPurchasing.isNotEmpty, isTrue);
      expect(ar.navPurchasing.isNotEmpty, isTrue);
      expect(en.navPurchasing.isNotEmpty, isTrue);

      expect(fr.navReturns.isNotEmpty, isTrue);
      expect(ar.navReturns.isNotEmpty, isTrue);
      expect(en.navReturns.isNotEmpty, isTrue);

      expect(fr.navLabels.isNotEmpty, isTrue);
      expect(ar.navLabels.isNotEmpty, isTrue);
      expect(en.navLabels.isNotEmpty, isTrue);

      expect(fr.navShifts.isNotEmpty, isTrue);
      expect(ar.navShifts.isNotEmpty, isTrue);
      expect(en.navShifts.isNotEmpty, isTrue);

      expect(fr.navReports.isNotEmpty, isTrue);
      expect(ar.navReports.isNotEmpty, isTrue);
      expect(en.navReports.isNotEmpty, isTrue);

      expect(fr.navSettings.isNotEmpty, isTrue);
      expect(ar.navSettings.isNotEmpty, isTrue);
      expect(en.navSettings.isNotEmpty, isTrue);

      // Auth & Access
      expect(fr.loginTitle, 'Connexion Caisse');
      expect(ar.loginTitle, 'تسجيل الدخول إلى الصندوق');
      expect(en.loginTitle, 'Register Login');

      expect(fr.screenLocked, 'Session Verrouillée');
      expect(ar.screenLocked, 'الجلسة مقفلة');
      expect(en.screenLocked, 'Session Locked');

      expect(fr.unlockAction, 'Déverrouiller');
      expect(ar.unlockAction, 'إلغاء القفل');
      expect(en.unlockAction, 'Unlock');

      // Shifts & Money
      expect(fr.openRegisterAction.isNotEmpty, isTrue);
      expect(ar.openRegisterAction.isNotEmpty, isTrue);
      expect(en.openRegisterAction.isNotEmpty, isTrue);

      expect(fr.payInAction.isNotEmpty, isTrue);
      expect(ar.payInAction.isNotEmpty, isTrue);
      expect(en.payInAction.isNotEmpty, isTrue);

      expect(fr.payOutAction.isNotEmpty, isTrue);
      expect(ar.payOutAction.isNotEmpty, isTrue);
      expect(en.payOutAction.isNotEmpty, isTrue);

      // Reports
      expect(fr.reportsTitle.isNotEmpty, isTrue);
      expect(ar.reportsTitle.isNotEmpty, isTrue);
      expect(en.reportsTitle.isNotEmpty, isTrue);

      expect(fr.totalSales.isNotEmpty, isTrue);
      expect(ar.totalSales.isNotEmpty, isTrue);
      expect(en.totalSales.isNotEmpty, isTrue);

      expect(fr.grossMargin.isNotEmpty, isTrue);
      expect(ar.grossMargin.isNotEmpty, isTrue);
      expect(en.grossMargin.isNotEmpty, isTrue);
    });

    testWidgets('Widget Directionality is RTL for Arabic and LTR for French', (
      tester,
    ) async {
      late BuildContext capturedArContext;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) {
              capturedArContext = context;
              return Text(context.loc.navPos);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(Directionality.of(capturedArContext), TextDirection.rtl);
      expect(capturedArContext.loc.navPos, 'نقطة البيع (POS)');
      expect(find.text('نقطة البيع (POS)'), findsOneWidget);

      late BuildContext capturedFrContext;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) {
              capturedFrContext = context;
              return Text(context.loc.navPos);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(Directionality.of(capturedFrContext), TextDirection.ltr);
      expect(capturedFrContext.loc.navPos, 'Caisse (POS)');
      expect(find.text('Caisse (POS)'), findsOneWidget);
    });
  });
}
