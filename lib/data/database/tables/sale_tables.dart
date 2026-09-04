import 'package:drift/drift.dart';
import 'company_tables.dart';
import 'catalog_tables.dart';
import 'user_tables.dart';
import 'inventory_tables.dart';

class Shifts extends Table {
  TextColumn get id => text()();
  TextColumn get registerId => text().references(Registers, #id)();
  TextColumn get cashierId => text().references(Users, #id)();
  DateTimeColumn get openedAt => dateTime()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  IntColumn get openingCashMillimes =>
      integer().withDefault(const Constant(0))();
  IntColumn get expectedCashMillimes => integer().nullable()();
  IntColumn get countedCashMillimes => integer().nullable()();
  IntColumn get cashDifferenceMillimes => integer().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant('OPEN'))(); // OPEN, CLOSED

  @override
  Set<Column> get primaryKey => {id};
}

class CashMovements extends Table {
  TextColumn get id => text()();
  TextColumn get shiftId => text().references(Shifts, #id)();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get movementType => text()(); // PAY_IN, PAY_OUT, CASH_DROP
  IntColumn get amountMillimes => integer()();
  TextColumn get reason => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get totalSpentMillimes =>
      integer().withDefault(const Constant(0))();
  IntColumn get storeCreditMillimes =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Sales extends Table {
  TextColumn get id => text()();
  TextColumn get receiptNumber => text().unique()();
  TextColumn get storeId => text().references(Stores, #id)();
  TextColumn get registerId => text().references(Registers, #id)();
  TextColumn get shiftId => text().references(Shifts, #id)();
  TextColumn get cashierId => text().references(Users, #id)();
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  IntColumn get subtotalMillimes => integer()();
  IntColumn get discountMillimes => integer().withDefault(const Constant(0))();
  IntColumn get taxMillimes => integer().withDefault(const Constant(0))();
  IntColumn get totalMillimes => integer()();
  TextColumn get status => text().withDefault(
    const Constant('COMPLETED'),
  )(); // COMPLETED, VOIDED, EXCHANGED, REFUNDED, PARTIALLY_REFUNDED
  TextColumn get notes => text().nullable()();
  BoolColumn get offlineSynced =>
      boolean().withDefault(const Constant(false))();
  TextColumn get idempotencyKey => text().unique()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class SaleLines extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get variantId => text().references(ProductVariants, #id)();
  // Immutable snapshot fields
  TextColumn get productName => text()();
  TextColumn get variantDescription => text()(); // e.g. "Black / M"
  TextColumn get sku => text()();
  TextColumn get barcode => text()();
  IntColumn get quantity => integer()();
  IntColumn get unitPriceMillimes => integer()();
  IntColumn get originalPriceMillimes => integer()();
  IntColumn get discountMillimes => integer().withDefault(const Constant(0))();
  RealColumn get taxRatePercent => real().withDefault(const Constant(0.0))();
  IntColumn get taxAmountMillimes => integer().withDefault(const Constant(0))();
  IntColumn get totalMillimes => integer()();
  IntColumn get unitCostMillimes => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class SalePayments extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get paymentMethod =>
      text()(); // CASH, CARD, MIXED, STORE_CREDIT, OTHER
  IntColumn get amountMillimes => integer()();
  IntColumn get tenderedMillimes => integer().withDefault(const Constant(0))();
  IntColumn get changeMillimes => integer().withDefault(const Constant(0))();
  TextColumn get reference => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Returns extends Table {
  TextColumn get id => text()();
  TextColumn get returnNumber => text().unique()();
  TextColumn get originalSaleId => text().nullable().references(Sales, #id)();
  TextColumn get storeId => text().references(Stores, #id)();
  TextColumn get registerId => text().references(Registers, #id)();
  TextColumn get shiftId => text().references(Shifts, #id)();
  TextColumn get cashierId => text().references(Users, #id)();
  TextColumn get reason => text()();
  IntColumn get totalRefundMillimes => integer()();
  TextColumn get refundMethod => text()(); // CASH, CARD, STORE_CREDIT
  TextColumn get managerId => text().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class ReturnLines extends Table {
  TextColumn get id => text()();
  TextColumn get returnId => text().references(Returns, #id)();
  TextColumn get originalSaleLineId =>
      text().nullable().references(SaleLines, #id)();
  TextColumn get variantId => text().references(ProductVariants, #id)();
  IntColumn get quantity => integer()();
  IntColumn get refundUnitPriceMillimes => integer()();
  IntColumn get totalRefundMillimes => integer()();
  TextColumn get condition =>
      text().withDefault(const Constant('SELLABLE'))(); // SELLABLE, DAMAGED
  TextColumn get restockedLocationId =>
      text().nullable().references(StockLocations, #id)();

  @override
  Set<Column> get primaryKey => {id};
}

class Exchanges extends Table {
  TextColumn get id => text()();
  TextColumn get returnId => text().references(Returns, #id)();
  TextColumn get newSaleId => text().references(Sales, #id)();
  IntColumn get differenceMillimes =>
      integer()(); // positive (customer pays) or negative (customer refunded)
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get cashierId => text().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class SuspendedCarts extends Table {
  TextColumn get id => text()();
  TextColumn get referenceName => text()();
  TextColumn get cashierId => text().references(Users, #id)();
  TextColumn get registerId => text().references(Registers, #id)();
  TextColumn get cartJson => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Reservations extends Table {
  TextColumn get id => text()();
  TextColumn get reservationNumber => text().unique()();
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get status => text().withDefault(
    const Constant('ACTIVE'),
  )(); // ACTIVE, COMPLETED, EXPIRED, CANCELLED
  DateTimeColumn get expiresAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class ReservationLines extends Table {
  TextColumn get id => text()();
  TextColumn get reservationId => text().references(Reservations, #id)();
  TextColumn get variantId => text().references(ProductVariants, #id)();
  IntColumn get quantity => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
