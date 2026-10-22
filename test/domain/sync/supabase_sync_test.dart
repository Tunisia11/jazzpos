import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/core/constants/app_constants.dart';
import 'package:tracepos/core/money/money.dart';
import 'package:tracepos/core/utils/id_generator.dart';
import 'package:tracepos/data/database/app_database.dart';
import 'package:tracepos/domain/models/cart_item.dart';
import 'package:tracepos/domain/models/checkout_request.dart';
import 'package:tracepos/domain/services/inventory_service.dart';
import 'package:tracepos/domain/services/sale_service.dart';
import 'package:tracepos/domain/services/sync_service.dart';
import 'package:tracepos/domain/sync/cloud_sync_backend.dart';

class MockCloudSyncBackend implements CloudSyncBackend {
  bool connectionSuccess = true;
  bool shouldThrowOnPush = false;
  final List<Map<String, dynamic>> pushedSales = [];
  final List<Map<String, dynamic>> pushedReturns = [];
  final List<Map<String, dynamic>> pushedStockLevels = [];
  final List<Map<String, dynamic>> pushedProductUpdates = [];
  List<Map<String, dynamic>> catalogUpdatesToReturn = [];

  @override
  Future<bool> testConnection(String url, String apiKey) async {
    return connectionSuccess;
  }

  @override
  Future<void> pushSale(Map<String, dynamic> saleData) async {
    if (shouldThrowOnPush) {
      throw const SyncException('Simulated 504 Gateway Timeout', statusCode: 504);
    }
    pushedSales.add(saleData);
  }

  @override
  Future<void> pushReturn(Map<String, dynamic> returnData) async {
    if (shouldThrowOnPush) {
      throw const SyncException('Simulated 504 Gateway Timeout', statusCode: 504);
    }
    pushedReturns.add(returnData);
  }

  @override
  Future<void> pushProductUpdate(Map<String, dynamic> productData) async {
    if (shouldThrowOnPush) {
      throw const SyncException('Simulated 504 Gateway Timeout', statusCode: 504);
    }
    pushedProductUpdates.add(productData);
  }

  @override
  Future<void> pushStockLevels(List<Map<String, dynamic>> stockLevels) async {
    pushedStockLevels.addAll(stockLevels);
  }

  @override
  Future<List<Map<String, dynamic>>> pullCatalogUpdates({DateTime? since}) async {
    return catalogUpdatesToReturn;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late InventoryService inventoryService;
  late SaleService saleService;
  late MockCloudSyncBackend mockBackend;
  late SyncService syncService;

  late String storeId;
  late String registerId;
  late String shiftId;
  late String cashierId;
  late String productId;
  late String variantId;
  late String locationId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    inventoryService = InventoryService(db);
    saleService = SaleService(db, inventoryService);
    mockBackend = MockCloudSyncBackend();
    syncService = SyncService(db, backend: mockBackend);

    final now = DateTime.now();
    final companyId = IdGenerator.uuid();
    storeId = IdGenerator.uuid();
    registerId = IdGenerator.uuid();
    cashierId = IdGenerator.uuid();
    shiftId = IdGenerator.uuid();
    locationId = IdGenerator.uuid();
    productId = IdGenerator.uuid();
    variantId = IdGenerator.uuid();

    // 1. Seed Company, Store, Register, Location, Cashier, Shift
    await db.into(db.companies).insert(
      CompaniesCompanion.insert(
        id: companyId,
        name: 'Trace Retail SARL',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.stores).insert(
      StoresCompanion.insert(
        id: storeId,
        companyId: companyId,
        name: 'Tunis Mall Flagship',
        code: 'TM-01',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.registers).insert(
      RegistersCompanion.insert(
        id: registerId,
        storeId: storeId,
        name: 'Caisse 01',
        code: 'REG-01',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.stockLocations).insert(
      StockLocationsCompanion.insert(
        id: locationId,
        storeId: storeId,
        name: 'Rayon Principal',
        code: 'SHOP',
        locationType: AppConstants.locationShopFloor,
        isDefault: const Value(true),
      ),
    );

    await db.into(db.users).insert(
      UsersCompanion.insert(
        id: cashierId,
        username: 'sami',
        displayName: 'Sami Ben Ali',
        role: 'CASHIER',
        pinHash: 'hash',
        pinSalt: 'salt',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.shifts).insert(
      ShiftsCompanion.insert(
        id: shiftId,
        registerId: registerId,
        cashierId: cashierId,
        openedAt: now,
        openingCashMillimes: const Value(200000),
      ),
    );

    // 2. Seed Product, Variant, Stock
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: productId,
        name: 'T-Shirt Coton Bio',
        defaultPriceMillimes: const Value(35000),
        defaultCostMillimes: const Value(15000),
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.productVariants).insert(
      ProductVariantsCompanion.insert(
        id: variantId,
        productId: productId,
        sku: 'TSH-WHT-M',
        barcode: '1900010001',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.stockLevels).insert(
      StockLevelsCompanion.insert(
        id: '${variantId}_$locationId',
        variantId: variantId,
        locationId: locationId,
        quantity: const Value(10),
        updatedAt: now,
      ),
    );

    // Enable Cloud Sync in AppSettings
    await syncService.saveCloudConfig(
      enabled: true,
      url: 'https://testproject.supabase.co',
      key: 'test-anon-key-123',
    );
  });

  tearDown(() async {
    syncService.dispose();
    await db.close();
  });

  test('Sale made offline enqueues outbox event, and syncNow pushes complete sale to Supabase', () async {
    // 1. Process Sale on cash register
    final request = CheckoutRequest(
      storeId: storeId,
      registerId: registerId,
      shiftId: shiftId,
      cashierId: cashierId,
      idempotencyKey: IdGenerator.uuid(),
      items: [
        CartItem(
          variantId: variantId,
          productId: productId,
          productName: 'T-Shirt Coton Bio',
          variantDescription: 'Blanc / M',
          sku: 'TSH-WHT-M',
          barcode: '1900010001',
          quantity: 2,
          unitPrice: const Money.fromMillimes(35000),
          originalPrice: const Money.fromMillimes(35000),
          unitCost: const Money.fromMillimes(15000),
        ),
      ],
      payments: [
        PaymentSplit(
          method: AppConstants.paymentCash,
          amount: const Money.fromMillimes(70000),
          tendered: const Money.fromMillimes(100000),
          change: const Money.fromMillimes(30000),
        ),
      ],
    );

    final saleResult = await saleService.checkout(request);
    expect(saleResult.sale.receiptNumber, isNotEmpty);

    // Check offline state in SQLite
    final localSale = await (db.select(db.sales)..where((t) => t.id.equals(saleResult.sale.id))).getSingle();
    expect(localSale.offlineSynced, false);

    final outboxEvents = await db.select(db.syncOutbox).get();
    expect(outboxEvents.length, 1);
    expect(outboxEvents.first.entityType, 'SALE');
    expect(outboxEvents.first.status, AppConstants.syncPending);

    // 2. Trigger Cloud Sync
    final syncResult = await syncService.syncNow();
    expect(syncResult.pushed, 1);
    expect(syncResult.error, isNull);

    // 3. Verify backend received complete sale payload
    expect(mockBackend.pushedSales.length, 1);
    final pushed = mockBackend.pushedSales.first;
    expect(pushed['id'], saleResult.sale.id);
    expect(pushed['receipt_number'], saleResult.sale.receiptNumber);
    expect(pushed['total_millimes'], 70000);
    expect((pushed['lines'] as List).length, 1);
    expect((pushed['payments'] as List).length, 1);

    // 4. Verify local DB state updated
    final syncedOutbox = await db.select(db.syncOutbox).get();
    expect(syncedOutbox.first.status, AppConstants.syncSynced);

    final updatedSale = await (db.select(db.sales)..where((t) => t.id.equals(saleResult.sale.id))).getSingle();
    expect(updatedSale.offlineSynced, true);
  });

  test('Conflict resolution: Cloud wins on Catalog/Prices, Register preserves local StockLevels', () async {
    // Current local product price is 35,000 millimes, stock is 10
    final initialStock = await (db.select(db.stockLevels)..where((t) => t.variantId.equals(variantId))).getSingle();
    expect(initialStock.quantity, 10);

    final newVariantId = IdGenerator.uuid();

    // Cloud pushes price change: 42,000 millimes and a new variant
    mockBackend.catalogUpdatesToReturn = [
      {
        'id': productId,
        'name': 'T-Shirt Coton Bio Premium',
        'default_price_millimes': 42000,
        'default_cost_millimes': 18000,
        'status': 'ACTIVE',
        'updated_at': DateTime.now().toIso8601String(),
        'product_variants': [
          {
            'id': variantId,
            'sku': 'TSH-WHT-M',
            'barcode': '1900010001',
            'sale_price_override_millimes': 42000,
            'cost_price_override_millimes': 18000,
            'is_active': true,
          },
          {
            'id': newVariantId,
            'sku': 'TSH-BLK-L',
            'barcode': '1900010002',
            'sale_price_override_millimes': 45000,
            'cost_price_override_millimes': 19000,
            'is_active': true,
          }
        ],
      }
    ];

    // Trigger sync
    final result = await syncService.syncNow();
    expect(result.pulled, 1);

    // 1. Verify Cloud WON on Product & Variant prices
    final updatedProduct = await (db.select(db.products)..where((t) => t.id.equals(productId))).getSingle();
    expect(updatedProduct.name, 'T-Shirt Coton Bio Premium');
    expect(updatedProduct.defaultPriceMillimes, 42000);

    final updatedVariant = await (db.select(db.productVariants)..where((t) => t.id.equals(variantId))).getSingle();
    expect(updatedVariant.salePriceOverrideMillimes, 42000);

    // 2. Verify Register WON on physical Stock (stock quantity remains untouched at 10)
    final preservedStock = await (db.select(db.stockLevels)..where((t) => t.variantId.equals(variantId))).getSingle();
    expect(preservedStock.quantity, 10);

    // 3. Verify new variant was created locally with initial stock level = 0
    final newVariant = await (db.select(db.productVariants)..where((t) => t.id.equals(newVariantId))).getSingle();
    expect(newVariant.sku, 'TSH-BLK-L');
    expect(newVariant.salePriceOverrideMillimes, 45000);

    final newStock = await (db.select(db.stockLevels)..where((t) => t.variantId.equals(newVariantId))).getSingle();
    expect(newStock.quantity, 0);
  });

  test('Network error increments retryCount, leaves event in outbox with FAILED status, no crash', () async {
    mockBackend.shouldThrowOnPush = true;

    // Enqueue an outbox event
    await db.into(db.syncOutbox).insert(
      SyncOutboxCompanion.insert(
        id: IdGenerator.uuid(),
        entityType: 'SALE',
        operation: 'INSERT',
        payloadJson: '{"id":"non-existent"}',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    final result = await syncService.syncNow();
    expect(result.pushed, 0);

    final outbox = await db.select(db.syncOutbox).get();
    expect(outbox.first.status, AppConstants.syncFailed);
    expect(outbox.first.retryCount, 1);
    expect(outbox.first.errorMessage, isNotNull);
  });

  test('Event is moved to DEAD_LETTER after 5 failures and unblocks queue', () async {
    mockBackend.shouldThrowOnPush = true;

    await db.into(db.syncOutbox).insert(
      SyncOutboxCompanion.insert(
        id: 'poison-pill',
        entityType: 'SALE',
        operation: 'INSERT',
        payloadJson: '{"id":"bad-id"}',
        status: const Value(AppConstants.syncFailed),
        retryCount: const Value(4), // 4th retry already
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    );

    final result = await syncService.syncNow();
    expect(result.pushed, 0);

    final poisoned = await (db.select(db.syncOutbox)..where((t) => t.id.equals('poison-pill'))).getSingle();
    expect(poisoned.status, AppConstants.syncDeadLetter);
    expect(poisoned.retryCount, 5);

    // Verify next sync run skips the dead letter record
    final nextResult = await syncService.syncNow();
    expect(nextResult.pushed, 0);
  });

  test('PRODUCT outbox event is pushed to remote Supabase backend', () async {
    await db.into(db.syncOutbox).insert(
      SyncOutboxCompanion.insert(
        id: IdGenerator.uuid(),
        entityType: 'PRODUCT',
        operation: 'UPDATE',
        payloadJson: jsonEncode({
          'id': productId,
          'name': 'Updated Product Name',
          'default_price_millimes': 42000,
        }),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    final syncResult = await syncService.syncNow();
    expect(syncResult.pushed, 1);
    expect(mockBackend.pushedProductUpdates.length, 1);
    expect(mockBackend.pushedProductUpdates.first['name'], 'Updated Product Name');
    expect(mockBackend.pushedProductUpdates.first['default_price_millimes'], 42000);
  });

  test('When cloud sync is disabled, outbox is NOT purged or marked synced', () async {
    await syncService.saveCloudConfig(
      enabled: false,
      url: 'https://example.supabase.co',
      key: 'some-key',
    );

    await db.into(db.syncOutbox).insert(
      SyncOutboxCompanion.insert(
        id: 'pending-offline-event',
        entityType: 'SALE',
        operation: 'INSERT',
        payloadJson: '{"id":"sale-offline-1"}',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    final syncResult = await syncService.syncNow();
    expect(syncResult.pushed, 0);

    // Verify record is STILL PENDING and has not been marked SYNCED
    final record = await (db.select(db.syncOutbox)..where((t) => t.id.equals('pending-offline-event'))).getSingle();
    expect(record.status, AppConstants.syncPending);
  });

  test('Cloud config persistence and connectivity test', () async {
    await syncService.saveCloudConfig(
      enabled: false,
      url: 'https://mycustom.supabase.co',
      key: 'my-key-abc',
    );

    final config = await syncService.getCloudConfig();
    expect(config.enabled, false);
    expect(config.url, 'https://mycustom.supabase.co');
    expect(config.key, 'my-key-abc');

    mockBackend.connectionSuccess = true;
    expect(await syncService.testConnection(), true);

    mockBackend.connectionSuccess = false;
    expect(await syncService.testConnection(), false);
  });
}
