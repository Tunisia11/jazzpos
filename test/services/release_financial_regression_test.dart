import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/models/cart_item.dart';
import 'package:jazzpos/domain/models/checkout_request.dart';
import 'package:jazzpos/domain/services/database_integrity_service.dart';
import 'package:jazzpos/domain/services/inventory_service.dart';
import 'package:jazzpos/domain/services/report_service.dart';
import 'package:jazzpos/domain/services/return_service.dart';
import 'package:jazzpos/domain/services/sale_service.dart';

CartItem makeTestItem(String variantId) => CartItem(
  variantId: variantId,
  productId: 'ignored-in-sale',
  productName: 'Test Jacket',
  variantDescription: 'Standard',
  sku: 'JACKET-1',
  barcode: '200000000001',
  unitPrice: const Money.fromMillimes(100000),
  originalPrice: const Money.fromMillimes(100000),
  lineDiscount: const Money.fromMillimes(10000),
  unitCost: const Money.fromMillimes(50000),
);

void main() {
  late AppDatabase db;
  late InventoryService inventory;
  late SaleService sales;
  late ReturnService returns;
  late String storeId;
  late String registerId;
  late String shiftId;
  late String cashierId;
  late String managerId;
  late String variantId;
  late StockLocation shopFloor;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    inventory = InventoryService(db);
    sales = SaleService(db, inventory);
    returns = ReturnService(db, inventory);
    final now = DateTime.now();
    final companyId = IdGenerator.uuid();
    storeId = IdGenerator.uuid();
    registerId = IdGenerator.uuid();
    shiftId = IdGenerator.uuid();
    cashierId = IdGenerator.uuid();

    await db
        .into(db.companies)
        .insert(
          CompaniesCompanion.insert(
            id: companyId,
            name: 'Jazz Retail',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.stores)
        .insert(
          StoresCompanion.insert(
            id: storeId,
            companyId: companyId,
            name: 'Main Store',
            code: 'MAIN',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.registers)
        .insert(
          RegistersCompanion.insert(
            id: registerId,
            storeId: storeId,
            name: 'Register 1',
            code: 'REG-1',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: cashierId,
            username: 'cashier',
            displayName: 'Cashier',
            role: 'CASHIER',
            pinHash: 'hash',
            pinSalt: 'salt',
            createdAt: now,
            updatedAt: now,
          ),
        );
    managerId = IdGenerator.uuid();
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: managerId,
            username: 'manager',
            displayName: 'Manager',
            role: 'MANAGER',
            pinHash: 'hash',
            pinSalt: 'salt',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.shifts)
        .insert(
          ShiftsCompanion.insert(
            id: shiftId,
            registerId: registerId,
            cashierId: cashierId,
            openedAt: now,
          ),
        );
    shopFloor = await inventory.getDefaultLocation(storeId);

    final productId = IdGenerator.uuid();
    variantId = IdGenerator.uuid();
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: productId,
            name: 'Test Jacket',
            defaultCostMillimes: const Value(50000),
            defaultPriceMillimes: const Value(100000),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            id: variantId,
            productId: productId,
            sku: 'JACKET-1',
            barcode: '200000000001',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await inventory.recordMovement(
      variantId: variantId,
      movementType: AppConstants.movementInitial,
      quantityDelta: 10,
      toLocationId: shopFloor.id,
      actorId: cashierId,
      reason: 'Opening inventory',
    );
  });

  tearDown(() => db.close());

  test('report remains correct after cart discount and full refund', () async {
    final completed = await sales.checkout(
      CheckoutRequest(
        storeId: storeId,
        registerId: registerId,
        shiftId: shiftId,
        cashierId: cashierId,
        items: [makeTestItem(variantId)],
        cartDiscount: const Money.fromMillimes(5000),
        payments: const [
          PaymentSplit(
            method: AppConstants.paymentCash,
            amount: Money.fromMillimes(85000),
          ),
        ],
        idempotencyKey: 'report-refund-regression',
      ),
    );
    final line = completed.lines.single;
    expect(line.totalMillimes, 90000);
    await returns.processReturn(
      ReturnRequest(
        originalSaleId: completed.sale.id,
        storeId: storeId,
        registerId: registerId,
        shiftId: shiftId,
        cashierId: cashierId,
        reason: 'Customer return',
        refundMethod: AppConstants.paymentCash,
        items: [
          ReturnLineItem(
            originalSaleLineId: line.id,
            variantId: variantId,
            quantity: 1,
            refundUnitPrice: const Money.fromMillimes(85000),
          ),
        ],
      ),
    );

    final report = await ReportService(db).getSalesReport(
      startDate: DateTime.now().subtract(const Duration(days: 1)),
      endDate: DateTime.now().add(const Duration(days: 1)),
    );
    expect(report.grossSales, const Money.fromMillimes(100000));
    expect(report.totalDiscounts, const Money.fromMillimes(15000));
    expect(report.totalRefunds, const Money.fromMillimes(85000));
    expect(report.netSales, Money.zero);
    expect(report.totalCost, Money.zero);
    expect(report.grossProfit, Money.zero);
  });

  test('ledger rebuild preserves stock at both ends of a transfer', () async {
    final backRoomId = IdGenerator.uuid();
    await db
        .into(db.stockLocations)
        .insert(
          StockLocationsCompanion.insert(
            id: backRoomId,
            storeId: storeId,
            name: 'Back room',
            code: 'BACK',
            locationType: AppConstants.locationBackRoom,
          ),
        );
    await inventory.transferStock(
      variantId: variantId,
      fromLocationId: shopFloor.id,
      toLocationId: backRoomId,
      quantity: 4,
      actorId: managerId,
    );

    final shopLevel =
        await (db.select(db.stockLevels)..where(
              (t) =>
                  t.variantId.equals(variantId) &
                  t.locationId.equals(shopFloor.id),
            ))
            .getSingle();
    await (db.update(db.stockLevels)..where((t) => t.id.equals(shopLevel.id)))
        .write(const StockLevelsCompanion(quantity: Value(0)));

    final integrity = DatabaseIntegrityService(db);
    expect((await integrity.runDiagnostics()).isHealthy, isFalse);
    await integrity.rebuildStockLevelsFromMovements();
    expect(await inventory.getStock(variantId, locationId: shopFloor.id), 6);
    expect(await inventory.getStock(variantId, locationId: backRoomId), 4);
    expect((await integrity.runDiagnostics()).isHealthy, isTrue);
  });

  test(
    'same receipt line cannot be duplicated within one return request',
    () async {
      final completed = await sales.checkout(
        CheckoutRequest(
          storeId: storeId,
          registerId: registerId,
          shiftId: shiftId,
          cashierId: cashierId,
          items: [makeTestItem(variantId)],
          cartDiscount: const Money.fromMillimes(5000),
          payments: const [
            PaymentSplit(
              method: AppConstants.paymentCash,
              amount: Money.fromMillimes(85000),
            ),
          ],
          idempotencyKey: 'duplicate-return-line-source',
        ),
      );
      final item = ReturnLineItem(
        originalSaleLineId: completed.lines.single.id,
        variantId: variantId,
        quantity: 1,
        refundUnitPrice: const Money.fromMillimes(85000),
      );

      await expectLater(
        returns.processReturn(
          ReturnRequest(
            originalSaleId: completed.sale.id,
            storeId: storeId,
            registerId: registerId,
            shiftId: shiftId,
            cashierId: cashierId,
            reason: 'Duplicate line attempt',
            refundMethod: AppConstants.paymentCash,
            items: [item, item],
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(await db.select(db.returns).get(), isEmpty);
      expect(await inventory.getStock(variantId, locationId: shopFloor.id), 9);
    },
  );

  test(
    'damaged return creates quarantine location, not sellable stock',
    () async {
      final completed = await sales.checkout(
        CheckoutRequest(
          storeId: storeId,
          registerId: registerId,
          shiftId: shiftId,
          cashierId: cashierId,
          items: [makeTestItem(variantId)],
          cartDiscount: const Money.fromMillimes(5000),
          payments: const [
            PaymentSplit(
              method: AppConstants.paymentCash,
              amount: Money.fromMillimes(85000),
            ),
          ],
          idempotencyKey: 'damaged-location-source',
        ),
      );
      await returns.processReturn(
        ReturnRequest(
          originalSaleId: completed.sale.id,
          storeId: storeId,
          registerId: registerId,
          shiftId: shiftId,
          cashierId: cashierId,
          reason: 'Damaged item',
          refundMethod: AppConstants.paymentCash,
          items: [
            ReturnLineItem(
              originalSaleLineId: completed.lines.single.id,
              variantId: variantId,
              quantity: 1,
              refundUnitPrice: const Money.fromMillimes(85000),
              condition: AppConstants.returnConditionDamaged,
            ),
          ],
        ),
      );

      final damaged =
          await (db.select(db.stockLocations)..where(
                (table) =>
                    table.locationType.equals(AppConstants.locationDamaged),
              ))
              .getSingle();
      expect(await inventory.getStock(variantId, locationId: shopFloor.id), 9);
      expect(await inventory.getStock(variantId, locationId: damaged.id), 1);
    },
  );
}
