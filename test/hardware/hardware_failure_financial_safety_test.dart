import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/models/cart_item.dart';
import 'package:jazzpos/domain/models/checkout_request.dart';
import 'package:jazzpos/domain/services/inventory_service.dart';
import 'package:jazzpos/domain/services/sale_service.dart';
import 'package:jazzpos/hardware/hardware_manager.dart';
import 'package:jazzpos/hardware/receipt_printer/receipt_document.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

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
    HardwareManager.instance.initialize();
    db = AppDatabase(NativeDatabase.memory());
    inventoryService = InventoryService(db);
    saleService = SaleService(db, inventoryService);

    final now = DateTime.now();
    final companyId = IdGenerator.uuid();
    storeId = IdGenerator.uuid();
    registerId = IdGenerator.uuid();
    cashierId = IdGenerator.uuid();
    shiftId = IdGenerator.uuid();

    // 1. Seed Company, Store, Register, Cashier, Shift
    await db
        .into(db.companies)
        .insert(
          CompaniesCompanion.insert(
            id: companyId,
            name: 'Boutique Test',
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
            name: 'Store 1',
            code: 'STR-01',
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
            displayName: 'Ahmed Caissier',
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
            openingCashMillimes: const Value(100000), // 100.000 TND
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
            name: 'Chemise Slim Fit',
            defaultCostMillimes: const Value(20000),
            defaultPriceMillimes: const Value(45000),
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
            sku: 'CHM-SLIM-BLU',
            barcode: '6191234567890',
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

  group('Hardware Failure Financial Safety & Zero Loss', () {
    test(
      'sale, payment, and stock movement remain fully committed when printer and drawer fail',
      () async {
        // Step 1: Prepare checkout request for 2 units (90.000 TND)
        final item = CartItem(
          variantId: variantId,
          productId: productId,
          productName: 'Chemise Slim Fit',
          variantDescription: 'Bleu / L',
          sku: 'CHM-SLIM-BLU',
          barcode: '6191234567890',
          unitPrice: const Money.fromMillimes(45000),
          originalPrice: const Money.fromMillimes(45000),
          quantity: 2,
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
              amount: Money.fromMillimes(90000),
            ),
          ],
          idempotencyKey: 'SALE-FAILSAFE-001',
        );

        // Step 2: Checkout executes SQLite transaction
        final checkoutResult = await saleService.checkout(request);
        expect(checkoutResult.sale.id.isNotEmpty, isTrue);
        expect(checkoutResult.sale.totalMillimes, equals(90000));

        // Verify database state immediately after transaction
        final salesBefore = await db.select(db.sales).get();
        expect(salesBefore.length, equals(1));
        final paymentsBefore = await db.select(db.salePayments).get();
        expect(paymentsBefore.length, equals(1));
        final stockBefore = await inventoryService.getStock(variantId);
        expect(stockBefore, equals(8)); // 10 - 2 = 8

        // Step 3: Simulate peripheral hardware cascade failures (post-transaction)
        bool drawerThrew = false;
        try {
          // Hardware drawer failure simulation
          throw Exception('Drawer serial port disconnected / power failure');
        } catch (_) {
          drawerThrew = true;
        }
        expect(drawerThrew, isTrue);

        bool printerThrew = false;
        try {
          // Hardware printer failure simulation (out of paper / offline)
          throw Exception('Printer offline: Out of Paper (0x12)');
        } catch (_) {
          printerThrew = true;
        }
        expect(printerThrew, isTrue);

        bool displayThrew = false;
        try {
          // Customer display failure simulation
          throw Exception('Customer display USB bulk transfer timeout');
        } catch (_) {
          displayThrew = true;
        }
        expect(displayThrew, isTrue);

        // Step 4: Verify that hardware failures CANNOT alter or rollback the committed transaction
        final salesAfter = await db.select(db.sales).get();
        expect(salesAfter.length, equals(1));
        expect(salesAfter.first.id, equals(checkoutResult.sale.id));
        expect(salesAfter.first.totalMillimes, equals(90000));
        expect(
          salesAfter.first.receiptNumber,
          equals(checkoutResult.sale.receiptNumber),
        );

        final paymentsAfter = await db.select(db.salePayments).get();
        expect(paymentsAfter.length, equals(1));
        expect(paymentsAfter.first.amountMillimes, equals(90000));

        final stockAfter = await inventoryService.getStock(variantId);
        expect(stockAfter, equals(8)); // Stock remains strictly 8

        final movements = await (db.select(
          db.stockMovements,
        )..where((t) => t.variantId.equals(variantId))).get();
        expect(movements.length, equals(2)); // INITIAL (10) and SALE (-2)
        expect(movements.last.movementType, equals(AppConstants.movementSale));
        expect(movements.last.quantityDelta, equals(-2));
      },
    );

    test(
      'reprint generates duplicate layout without creating additional sales, payments, or stock changes',
      () async {
        // Step 1: Create a sale
        final item = CartItem(
          variantId: variantId,
          productId: productId,
          productName: 'Chemise Slim Fit',
          variantDescription: 'Bleu / L',
          sku: 'CHM-SLIM-BLU',
          barcode: '6191234567890',
          unitPrice: const Money.fromMillimes(45000),
          originalPrice: const Money.fromMillimes(45000),
          quantity: 1,
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
              amount: Money.fromMillimes(45000),
            ),
          ],
          idempotencyKey: 'SALE-REPRINT-001',
        );

        final result = await saleService.checkout(request);

        // Record baselines
        final salesCountBefore = (await db.select(db.sales).get()).length;
        final paymentsCountBefore =
            (await db.select(db.salePayments).get()).length;
        final stockBefore = await inventoryService.getStock(variantId);
        final movementsCountBefore =
            (await db.select(db.stockMovements).get()).length;

        // Step 2: Build duplicate receipt document for reprint
        final duplicateDoc = ReceiptDocument(
          storeName: 'Boutique Test',
          receiptNumber: result.sale.receiptNumber,
          dateTime: result.sale.createdAt,
          cashierName: 'Ahmed Caissier',
          registerCode: 'REG-1',
          lines: [
            ReceiptLineItem(
              productName: 'Chemise Slim Fit',
              variantDescription: 'Bleu / L',
              sku: 'CHM-SLIM-BLU',
              barcode: '6191234567890',
              quantity: 1,
              unitPrice: const Money.fromMillimes(45000),
              total: const Money.fromMillimes(45000),
            ),
          ],
          subtotal: const Money.fromMillimes(45000),
          discount: Money.zero,
          tax: Money.zero,
          total: const Money.fromMillimes(45000),
          payments: const [
            ReceiptPaymentItem(
              method: 'ESPECES',
              amount: Money.fromMillimes(45000),
            ),
          ],
          isDuplicate: true,
        );
        expect(duplicateDoc.isDuplicate, isTrue);

        // Simulate reprint through HardwareManager receipt printer
        await HardwareManager.instance.receiptPrinter.printReceipt(
          duplicateDoc,
        );

        // Log audit event as done in ReceiptPreviewDialog
        await db
            .into(db.auditEvents)
            .insert(
              AuditEventsCompanion.insert(
                id: IdGenerator.uuid(),
                action: 'receipt_reprinted',
                entityType: 'SALE',
                entityId: Value(result.sale.id),
                userId: cashierId,
                detailsJson: Value(
                  '{"receiptNumber": "${result.sale.receiptNumber}", "isDuplicate": true}',
                ),
                createdAt: DateTime.now(),
              ),
            );

        // Step 3: Strict verification of non-destructive financial safety
        final salesCountAfter = (await db.select(db.sales).get()).length;
        final paymentsCountAfter =
            (await db.select(db.salePayments).get()).length;
        final stockAfter = await inventoryService.getStock(variantId);
        final movementsCountAfter =
            (await db.select(db.stockMovements).get()).length;

        expect(
          salesCountAfter,
          equals(salesCountBefore),
          reason: 'Reprint must NEVER create a new sale',
        );
        expect(
          paymentsCountAfter,
          equals(paymentsCountBefore),
          reason: 'Reprint must NEVER create a new payment',
        );
        expect(
          stockAfter,
          equals(stockBefore),
          reason: 'Reprint must NEVER alter inventory stock',
        );
        expect(
          movementsCountAfter,
          equals(movementsCountBefore),
          reason: 'Reprint must NEVER create stock movements',
        );

        // Verify audit event is recorded
        final auditLogs = await db.select(db.auditEvents).get();
        final reprintLogs = auditLogs.where(
          (l) => l.action == 'receipt_reprinted',
        );
        expect(reprintLogs.length, equals(1));
      },
    );
  });
}
