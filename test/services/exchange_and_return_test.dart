import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/models/cart_item.dart';
import 'package:jazzpos/domain/services/exchange_service.dart';
import 'package:jazzpos/domain/services/inventory_service.dart';
import 'package:jazzpos/domain/services/return_service.dart';
import 'package:jazzpos/domain/services/sale_service.dart';

void main() {
  late AppDatabase db;
  late InventoryService inventoryService;
  late SaleService saleService;
  late ReturnService returnService;
  late ExchangeService exchangeService;

  late String storeId;
  late String registerId;
  late String shiftId;
  late String cashierId;
  late String managerId;
  late String variantM;
  late String variantL;
  late StockLocation shopFloor;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    inventoryService = InventoryService(db);
    saleService = SaleService(db, inventoryService);
    returnService = ReturnService(db, inventoryService);
    exchangeService = ExchangeService(db, returnService, saleService);

    final now = DateTime.now();
    final companyId = IdGenerator.uuid();
    storeId = IdGenerator.uuid();
    registerId = IdGenerator.uuid();
    cashierId = IdGenerator.uuid();
    shiftId = IdGenerator.uuid();

    await db.into(db.companies).insert(
          CompaniesCompanion.insert(
            id: companyId,
            name: 'Jazz Retail SARL',
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
            name: 'Caisse 1',
            code: 'REG-1',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await db.into(db.users).insert(
          UsersCompanion.insert(
            id: cashierId,
            username: 'cashier1',
            displayName: 'Amira',
            role: 'CASHIER',
            pinHash: 'hash',
            pinSalt: 'salt',
            createdAt: now,
            updatedAt: now,
          ),
        );

    managerId = IdGenerator.uuid();
    await db.into(db.users).insert(
          UsersCompanion.insert(
            id: managerId,
            username: 'manager1',
            displayName: 'Mehdi Manager',
            role: 'MANAGER',
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
            openingCashMillimes: const Value(100000),
            status: const Value(AppConstants.shiftOpen),
          ),
        );

    shopFloor = await inventoryService.getDefaultLocation(storeId);

    // Create damaged location
    await db.into(db.stockLocations).insert(
          StockLocationsCompanion.insert(
            id: IdGenerator.uuid(),
            storeId: storeId,
            name: 'Damaged Items',
            code: 'DMG',
            locationType: AppConstants.locationDamaged,
            isDefault: const Value(false),
          ),
        );

    // Seed 2 variants: Size M (39.900 TND) and Size L (49.900 TND)
    final prodId = IdGenerator.uuid();
    variantM = IdGenerator.uuid();
    variantL = IdGenerator.uuid();

    await db.into(db.products).insert(
          ProductsCompanion.insert(
            id: prodId,
            name: 'Polo Shirt',
            defaultCostMillimes: const Value(20000),
            defaultPriceMillimes: const Value(39900),
            createdAt: now,
            updatedAt: now,
          ),
        );

    await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            id: variantM,
            productId: prodId,
            sku: 'POLO-BLK-M',
            barcode: '200111111111',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            id: variantL,
            productId: prodId,
            sku: 'POLO-BLK-L',
            barcode: '200222222222',
            salePriceOverrideMillimes: const Value(49900), // Size L is 49.900 TND
            createdAt: now,
            updatedAt: now,
          ),
        );

    // Initial stock: 10 of M, 10 of L
    await inventoryService.recordMovement(
      variantId: variantM,
      movementType: AppConstants.movementInitial,
      quantityDelta: 10,
      toLocationId: shopFloor.id,
      actorId: cashierId,
      reason: 'Initial stock M',
    );
    await inventoryService.recordMovement(
      variantId: variantL,
      movementType: AppConstants.movementInitial,
      quantityDelta: 10,
      toLocationId: shopFloor.id,
      actorId: cashierId,
      reason: 'Initial stock L',
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Returns and Clothing Exchanges', () {
    test('Standard return restocks sellable item to shop floor', () async {
      final returnItem = ReturnLineItem(
        variantId: variantM,
        quantity: 1,
        refundUnitPrice: const Money.fromMillimes(39900),
        condition: AppConstants.returnConditionSellable,
      );

      final req = ReturnRequest(
        storeId: storeId,
        registerId: registerId,
        shiftId: shiftId,
        cashierId: cashierId,
        reason: 'Customer changed mind',
        refundMethod: AppConstants.paymentCash,
        items: [returnItem],
        managerId: managerId,
      );

      final res = await returnService.processReturn(req);
      expect(res.totalRefundMillimes, 39900);

      // Stock of M was 10, now should be 11
      final stockM = await inventoryService.getStock(variantM);
      expect(stockM, 11);
    });

    test('Damaged return puts item into damaged location, NOT sellable shop floor', () async {
      final returnItem = ReturnLineItem(
        variantId: variantM,
        quantity: 1,
        refundUnitPrice: const Money.fromMillimes(39900),
        condition: AppConstants.returnConditionDamaged,
      );

      final req = ReturnRequest(
        storeId: storeId,
        registerId: registerId,
        shiftId: shiftId,
        cashierId: cashierId,
        reason: 'Torn seam',
        refundMethod: AppConstants.paymentCash,
        items: [returnItem],
        managerId: managerId,
      );

      await returnService.processReturn(req);

      // Sellable shop floor stock must NOT increase (remains 10)
      final sellableStock = await inventoryService.getStock(variantM, locationId: shopFloor.id);
      expect(sellableStock, 10);
    });

    test('Exchange Size M for Size L with net price difference settlement', () async {
      // Customer bought M (39.900 TND) and now exchanges for L (49.900 TND).
      // Customer pays +10.000 TND cash.
      final returned = ReturnLineItem(
        variantId: variantM,
        quantity: 1,
        refundUnitPrice: const Money.fromMillimes(39900),
        condition: AppConstants.returnConditionSellable,
      );

      final newItem = CartItem(
        variantId: variantL,
        productId: 'prod-1',
        productName: 'Polo Shirt',
        variantDescription: 'BLACK / L',
        sku: 'POLO-BLK-L',
        barcode: '200222222222',
        unitPrice: const Money.fromMillimes(49900),
        originalPrice: const Money.fromMillimes(49900),
        quantity: 1,
      );

      final exchangeReq = ExchangeRequest(
        storeId: storeId,
        registerId: registerId,
        shiftId: shiftId,
        cashierId: cashierId,
        returnedItems: [returned],
        newItems: [newItem],
        paymentMethod: AppConstants.paymentCash,
        tendered: const Money.fromMillimes(10000), // 10.000 TND
        reason: 'Size exchange M to L',
        managerOverrideId: managerId,
      );

      expect(exchangeReq.difference.millimes, 10000); // 49900 - 39900 = 10000

      final result = await exchangeService.processExchange(exchangeReq);

      expect(result.difference.millimes, 10000);
      expect(result.exchange.differenceMillimes, 10000);

      // Stock M increased by 1 (10 -> 11)
      final stockM = await inventoryService.getStock(variantM);
      expect(stockM, 11);

      // Stock L decreased by 1 (10 -> 9)
      final stockL = await inventoryService.getStock(variantL);
      expect(stockL, 9);
    });
  });
}
