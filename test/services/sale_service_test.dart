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
import 'package:jazzpos/domain/services/inventory_service.dart';
import 'package:jazzpos/domain/services/sale_service.dart';

void main() {
  late AppDatabase db;
  late InventoryService inventoryService;
  late SaleService saleService;

  late String storeId;
  late String registerId;
  late String shiftId;
  late String cashierId;
  late String productId;
  late String variantId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    inventoryService = InventoryService(db);
    saleService = SaleService(db, inventoryService);

    final now = DateTime.now();
    final companyId = IdGenerator.uuid();
    storeId = IdGenerator.uuid();
    registerId = IdGenerator.uuid();
    cashierId = IdGenerator.uuid();
    shiftId = IdGenerator.uuid();

    // 1. Seed Company, Store, Register, Cashier
    await db
        .into(db.companies)
        .insert(
          CompaniesCompanion.insert(
            id: companyId,
            name: 'Jazz Retail SARL',
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
            name: 'Tunis Mall Flagship',
            code: 'TM-01',
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
            name: 'Caisse 1',
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
            username: 'cashier1',
            displayName: 'Amira',
            role: 'CASHIER',
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
            openingCashMillimes: const Value(100000), // 100.000 TND float
            status: const Value(AppConstants.shiftOpen),
          ),
        );

    // 2. Seed Product & Variant with 10 initial stock
    productId = IdGenerator.uuid();
    variantId = IdGenerator.uuid();

    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: productId,
            name: 'Nike Basic Tee',
            defaultCostMillimes: const Value(20000),
            defaultPriceMillimes: const Value(39900),
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
            sku: 'TSH-BLK-M',
            barcode: '200111222333',
            createdAt: now,
            updatedAt: now,
          ),
        );

    final shopFloor = await inventoryService.getDefaultLocation(storeId);
    await inventoryService.recordMovement(
      variantId: variantId,
      movementType: AppConstants.movementInitial,
      quantityDelta: 10,
      toLocationId: shopFloor.id,
      unitCostMillimes: 20000,
      actorId: cashierId,
      reason: 'Initial stock',
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('SaleService Atomic Checkout & Invariants', () {
    test(
      'Successful cash sale commits sale, lines, stock movements, and audit',
      () async {
        final item = CartItem(
          variantId: variantId,
          productId: 'prod-1',
          productName: 'Nike Basic Tee',
          variantDescription: 'BLACK / M',
          sku: 'TSH-BLK-M',
          barcode: '200111222333',
          unitPrice: const Money.fromMillimes(39900), // 39.900 TND
          originalPrice: const Money.fromMillimes(39900),
          quantity: 2,
          unitCost: const Money.fromMillimes(20000),
        );

        final total = item.total; // 79.800 TND
        expect(total.millimes, 79800);

        final request = CheckoutRequest(
          storeId: storeId,
          registerId: registerId,
          shiftId: shiftId,
          cashierId: cashierId,
          items: [item],
          payments: [
            PaymentSplit(
              method: AppConstants.paymentCash,
              amount: total,
              tendered: const Money.fromMillimes(100000), // 100.000 TND
              change: const Money.fromMillimes(20200), // 20.200 TND
            ),
          ],
          idempotencyKey: 'IDEMP-TEST-001',
        );

        final result = await saleService.checkout(request);

        // Verify Sale record
        expect(result.sale.totalMillimes, 79800);
        expect(result.lines.length, 1);
        expect(result.lines.first.productName, 'Nike Basic Tee');
        expect(result.lines.first.variantDescription, 'BLACK / M');
        expect(result.lines.first.quantity, 2);

        // Verify Payments
        expect(result.payments.length, 1);
        expect(result.payments.first.paymentMethod, 'CASH');
        expect(result.payments.first.tenderedMillimes, 100000);
        expect(result.payments.first.changeMillimes, 20200);

        // Verify physical stock was deducted exactly once (10 - 2 = 8)
        final remainingStock = await inventoryService.getStock(variantId);
        expect(remainingStock, 8);

        // Verify Audit Event logged
        final audits = await db.select(db.auditEvents).get();
        expect(
          audits.any(
            (a) => a.action == 'SALE_COMPLETED' && a.entityId == result.sale.id,
          ),
          isTrue,
        );

        // Verify Outbox Event queued
        final outbox = await db.select(db.syncOutbox).get();
        expect(
          outbox.any((o) => o.entityType == 'SALE' && o.status == 'PENDING'),
          isTrue,
        );

        // Verify Print Job queued
        final printJobs = await db.select(db.printJobs).get();
        expect(printJobs.length, 1);
        expect(printJobs.first.jobType, 'RECEIPT');
      },
    );

    test('Idempotency protects against duplicate Pay clicks', () async {
      final item = CartItem(
        variantId: variantId,
        productId: 'prod-1',
        productName: 'Nike Basic Tee',
        variantDescription: 'BLACK / M',
        sku: 'TSH-BLK-M',
        barcode: '200111222333',
        unitPrice: const Money.fromMillimes(39900),
        originalPrice: const Money.fromMillimes(39900),
        quantity: 1,
      );

      final request = CheckoutRequest(
        storeId: storeId,
        registerId: registerId,
        shiftId: shiftId,
        cashierId: cashierId,
        items: [item],
        payments: [
          PaymentSplit(method: AppConstants.paymentCard, amount: item.total),
        ],
        idempotencyKey: 'IDEMP-DUPLICATE-CHECK',
      );

      // First call
      final res1 = await saleService.checkout(request);
      expect(res1.sale.idempotencyKey, 'IDEMP-DUPLICATE-CHECK');

      // Second rapid call with identical idempotencyKey
      final res2 = await saleService.checkout(request);
      expect(res2.sale.id, res1.sale.id); // Same sale returned!

      // Total sales in database must be strictly 1, NOT 2
      final allSales = await db.select(db.sales).get();
      expect(allSales.length, 1);

      // Stock deducted only once (10 - 1 = 9)
      final stock = await inventoryService.getStock(variantId);
      expect(stock, 9);
    });

    test(
      'Negative stock policy BLOCK throws InsufficientStockException',
      () async {
        // Set negative stock policy to BLOCK
        await db
            .into(db.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: AppConstants.keyNegativeStockPolicy,
                value: AppConstants.negativeStockBlock,
                updatedAt: DateTime.now(),
              ),
            );

        // Current stock is 10. Attempt to sell 15.
        final item = CartItem(
          variantId: variantId,
          productId: 'prod-1',
          productName: 'Nike Basic Tee',
          variantDescription: 'BLACK / M',
          sku: 'TSH-BLK-M',
          barcode: '200111222333',
          unitPrice: const Money.fromMillimes(39900),
          originalPrice: const Money.fromMillimes(39900),
          quantity: 15,
        );

        final request = CheckoutRequest(
          storeId: storeId,
          registerId: registerId,
          shiftId: shiftId,
          cashierId: cashierId,
          items: [item],
          payments: [
            PaymentSplit(method: AppConstants.paymentCash, amount: item.total),
          ],
          idempotencyKey: 'IDEMP-OVERSTOCK-FAIL',
        );

        expect(
          () => saleService.checkout(request),
          throwsA(isA<InsufficientStockException>()),
        );

        // Ensure no partial sale was created
        final allSales = await db.select(db.sales).get();
        expect(allSales.isEmpty, isTrue);

        // Stock remains untouched at 10
        final stock = await inventoryService.getStock(variantId);
        expect(stock, 10);
      },
    );

    test('Rejects over-applied payments without writing a sale', () async {
      final item = CartItem(
        variantId: variantId,
        productId: productId,
        productName: 'Nike Basic Tee',
        variantDescription: 'BLACK / M',
        sku: 'TSH-BLK-M',
        barcode: '200111222333',
        unitPrice: const Money.fromMillimes(39900),
        originalPrice: const Money.fromMillimes(39900),
      );
      final request = CheckoutRequest(
        storeId: storeId,
        registerId: registerId,
        shiftId: shiftId,
        cashierId: cashierId,
        items: [item],
        payments: const [
          PaymentSplit(
            method: AppConstants.paymentCash,
            amount: Money.fromMillimes(40000),
          ),
        ],
        idempotencyKey: 'OVERPAYMENT',
      );

      await expectLater(
        saleService.checkout(request),
        throwsA(isA<ValidationException>()),
      );
      expect(await db.select(db.sales).get(), isEmpty);
      expect(await inventoryService.getStock(variantId), 10);
    });

    test('Rejects an archived product still present in a cart', () async {
      await (db.update(db.products)
            ..where((table) => table.id.equals(productId)))
          .write(const ProductsCompanion(status: Value('ARCHIVED')));
      final item = CartItem(
        variantId: variantId,
        productId: productId,
        productName: 'Nike Basic Tee',
        variantDescription: 'BLACK / M',
        sku: 'TSH-BLK-M',
        barcode: '200111222333',
        unitPrice: const Money.fromMillimes(39900),
        originalPrice: const Money.fromMillimes(39900),
      );

      await expectLater(
        saleService.checkout(
          CheckoutRequest(
            storeId: storeId,
            registerId: registerId,
            shiftId: shiftId,
            cashierId: cashierId,
            items: [item],
            payments: [
              PaymentSplit(
                method: AppConstants.paymentCard,
                amount: item.total,
              ),
            ],
            idempotencyKey: 'ARCHIVED-CART',
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(await db.select(db.sales).get(), isEmpty);
      expect(await inventoryService.getStock(variantId), 10);
    });
  });
}
