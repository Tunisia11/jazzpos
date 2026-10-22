import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/core/constants/app_constants.dart';
import 'package:tracepos/core/localization/app_localizations_delegate.dart';
import 'package:tracepos/core/money/money.dart';
import 'package:tracepos/data/database/app_database.dart';
import 'package:tracepos/domain/models/cart_item.dart';
import 'package:tracepos/domain/models/checkout_request.dart';
import 'package:tracepos/domain/services/inventory_service.dart';
import 'package:tracepos/domain/services/pos_initialization_service.dart';
import 'package:tracepos/domain/services/sale_service.dart';
import 'package:tracepos/providers/app_providers.dart';
import 'package:tracepos/providers/auth_provider.dart';
import 'package:tracepos/providers/shift_provider.dart';
import 'package:tracepos/ui/navigation/app_router.dart';
import 'package:tracepos/ui/screens/mobile/owner_catalog_view.dart';
import 'package:tracepos/ui/screens/mobile/owner_dashboard_view.dart';
import 'package:tracepos/ui/screens/mobile/owner_mobile_shell.dart';
import 'package:tracepos/ui/screens/mobile/owner_stock_alerts_view.dart';
import 'package:tracepos/ui/screens/mobile/owner_sync_view.dart';

Widget _wrapWithApp(Widget child, ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late ProviderContainer container;
  late InventoryService inventory;
  late SaleService saleService;
  late String registerId;
  late String storeId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    inventory = InventoryService(db);
    saleService = SaleService(db, inventory);

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        inventoryServiceProvider.overrideWithValue(inventory),
        saleServiceProvider.overrideWithValue(saleService),
      ],
    );

    await PosInitializationService(db).initializePos(
      companyName: 'Boutique Élégance Tunis',
      storeName: 'Boutique Lac 2',
      registerCode: 'REG-001',
      ownerUsername: 'owner',
      ownerDisplayName: 'Sami Ben Ali',
      ownerPin: '1234',
    );

    final ok = await container.read(authNotifierProvider.notifier).login('owner', '1234');
    expect(ok, true);

    final user = container.read(authNotifierProvider).user!;
    final reg = await db.select(db.registers).getSingle();
    registerId = reg.id;
    storeId = reg.storeId;

    await container.read(shiftNotifierProvider.notifier).openShift(
      registerId: registerId,
      cashierId: user.id,
      openingCash: Money.zero,
    );

    // Seed test products, variants, and stock
    final now = DateTime.now();
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: 'prod_chemise',
        name: 'Chemise Lin Blanche',
        defaultPriceMillimes: const d.Value(75000),
        defaultCostMillimes: const d.Value(40000),
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.productVariants).insert(
      ProductVariantsCompanion.insert(
        id: 'var_chemise_l',
        productId: 'prod_chemise',
        sku: 'CHM-LIN-L',
        barcode: '112233445566',
        salePriceOverrideMillimes: const d.Value(75000),
        createdAt: now,
        updatedAt: now,
      ),
    );

    // Out of stock product
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: 'prod_pantalon',
        name: 'Pantalon Chino Kaki',
        defaultPriceMillimes: const d.Value(90000),
        defaultCostMillimes: const d.Value(50000),
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.productVariants).insert(
      ProductVariantsCompanion.insert(
        id: 'var_pantalon_42',
        productId: 'prod_pantalon',
        sku: 'PNT-CHK-42',
        barcode: '998877665544',
        salePriceOverrideMillimes: const d.Value(90000),
        createdAt: now,
        updatedAt: now,
      ),
    );

    final loc = await inventory.getDefaultLocation(storeId);
    // 3 units for chemise
    await inventory.recordMovement(
      variantId: 'var_chemise_l',
      movementType: AppConstants.movementInitial,
      quantityDelta: 3,
      toLocationId: loc.id,
      actorId: user.id,
      reason: 'Initial stock',
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('Owner Mobile Shell & Responsive Routing', () {
    testWidgets('Renders OwnerMobileShell on compact screens (<768px)', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_wrapWithApp(const AppShell(), container));
      await tester.pumpAndSettle();

      expect(find.byType(OwnerMobileShell), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Aperçu'), findsOneWidget);
      expect(find.text('Catalogue'), findsOneWidget);
      expect(find.text('Alertes'), findsOneWidget);
      expect(find.text('Synchro'), findsOneWidget);
    });

    testWidgets('Tapping mobile navigation tabs switches views smoothly', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_wrapWithApp(const OwnerMobileShell(), container));
      await tester.pumpAndSettle();

      // Initial tab: Dashboard
      expect(find.byType(OwnerDashboardView), findsOneWidget);

      // Tap Catalogue tab
      await tester.tap(find.text('Catalogue'));
      await tester.pumpAndSettle();
      expect(find.byType(OwnerCatalogView), findsOneWidget);

      // Tap Alertes tab
      await tester.tap(find.text('Alertes'));
      await tester.pumpAndSettle();
      expect(find.byType(OwnerStockAlertsView), findsOneWidget);

      // Tap Synchro tab
      await tester.tap(find.text('Synchro'));
      await tester.pumpAndSettle();
      expect(find.byType(OwnerSyncView), findsOneWidget);
    });
  });

  group('Owner Dashboard View', () {
    testWidgets('Displays store revenue and key business metrics', (tester) async {
      // Execute a real sale to populate metrics
      final user = container.read(authNotifierProvider).user!;
      final shift = container.read(shiftNotifierProvider).activeShift!;
      await saleService.checkout(
        CheckoutRequest(
          items: [
            const CartItem(
              variantId: 'var_chemise_l',
              productId: 'prod_chemise',
              productName: 'Chemise Lin Blanche',
              variantDescription: 'L',
              sku: 'CHM-LIN-L',
              barcode: '112233445566',
              quantity: 1,
              unitPrice: Money.fromMillimes(75000),
              originalPrice: Money.fromMillimes(75000),
            ),
          ],
          payments: [
            const PaymentSplit(
              method: 'CASH',
              amount: Money.fromMillimes(75000),
            ),
          ],
          storeId: storeId,
          registerId: registerId,
          cashierId: user.id,
          shiftId: shift.id,
          idempotencyKey: 'test-checkout-1',
        ),
      );

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_wrapWithApp(const OwnerDashboardView(), container));
      await tester.pumpAndSettle();

      // Header and revenue section
      expect(find.text('75.000 TND'), findsAtLeastNWidgets(1));
      expect(find.text('Panier Moyen'), findsOneWidget);
      expect(find.text('Espèces'), findsOneWidget);
      expect(find.text('Carte / TPE'), findsOneWidget);
      expect(find.text('Dernières Transactions'), findsOneWidget);
    });
  });

  group('Owner Catalog & Remote Price Editor', () {
    testWidgets('Lists products, filters search, and allows quick price adjustments', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_wrapWithApp(const OwnerCatalogView(), container));
      await tester.pumpAndSettle();

      // Should show the 2 seeded products
      expect(find.text('Chemise Lin Blanche'), findsOneWidget);
      expect(find.text('Pantalon Chino Kaki'), findsOneWidget);

      // Search filter
      await tester.enterText(find.byType(TextField), 'Chemise');
      await tester.pumpAndSettle();
      expect(find.text('Chemise Lin Blanche'), findsOneWidget);
      expect(find.text('Pantalon Chino Kaki'), findsNothing);

      // Clear search
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      // Tap on Chemise to edit price
      await tester.tap(find.text('Chemise Lin Blanche'));
      await tester.pumpAndSettle();

      // Price modal should be visible
      expect(find.textContaining('Modifier le prix'), findsOneWidget);
      expect(find.text('Prix de Vente (TND)'), findsOneWidget);

      // Update price from 75.000 to 82.500
      final priceInput = find.byType(TextFormField);
      await tester.enterText(priceInput, '82.500');
      await tester.pumpAndSettle();

      // Tap Mettre à jour le prix
      await tester.tap(find.text('Mettre à jour le prix'));
      await tester.pumpAndSettle();

      // Check database updated
      final updatedProduct = await (db.select(db.products)..where((t) => t.id.equals('prod_chemise'))).getSingle();
      expect(updatedProduct.defaultPriceMillimes, 82500);

      final updatedVariant = await (db.select(db.productVariants)..where((t) => t.id.equals('var_chemise_l'))).getSingle();
      expect(updatedVariant.salePriceOverrideMillimes, 82500);

      // Check SyncOutbox recorded the change for cloud propagation
      final outboxEntries = await (db.select(db.syncOutbox)..where((t) => t.entityType.equals('PRODUCT'))).get();
      expect(outboxEntries.isNotEmpty, true);
      expect(outboxEntries.first.operation, 'UPDATE');
      expect(outboxEntries.first.payloadJson.contains('prod_chemise'), true);
    });
  });

  group('Owner Stock Alerts View', () {
    testWidgets('Calculates inventory valuation and displays low-stock / out-of-stock items', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_wrapWithApp(const OwnerStockAlertsView(), container));
      await tester.pumpAndSettle();

      expect(find.text('Unités en Magasin'), findsOneWidget);
      expect(find.text('Valeur au Prix Public'), findsOneWidget);

      // Filter segmented buttons
      expect(find.textContaining('Toutes'), findsOneWidget);
      expect(find.textContaining('Ruptures'), findsOneWidget);
      expect(find.textContaining('Critiques'), findsOneWidget);

      // Pantalon is at 0 units -> 0 EN STOCK
      expect(find.text('0 EN STOCK'), findsOneWidget);
      expect(find.text('Pantalon Chino Kaki'), findsOneWidget);

      // Filter by Ruptures
      await tester.tap(find.textContaining('Ruptures'));
      await tester.pumpAndSettle();
      expect(find.text('Pantalon Chino Kaki'), findsOneWidget);
    });
  });

  group('Owner Cloud Sync View', () {
    testWidgets('Displays sync status and cloud sync trigger button', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_wrapWithApp(const OwnerSyncView(), container));
      await tester.pumpAndSettle();

      expect(find.textContaining('Synchronisation Cloud'), findsAtLeastNWidgets(1));
      expect(find.text('En attente'), findsOneWidget);
      expect(find.text('Synchronisés'), findsOneWidget);
      expect(find.text('Synchroniser maintenant'), findsOneWidget);

      // Tap Synchroniser maintenant
      await tester.tap(find.text('Synchroniser maintenant'));
      await tester.pumpAndSettle();
    });
  });
}
