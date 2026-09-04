import 'package:drift/drift.dart';
import 'company_tables.dart';
import 'catalog_tables.dart';
import 'user_tables.dart';

class StockLocations extends Table {
  TextColumn get id => text()();
  TextColumn get storeId => text().references(Stores, #id)();
  TextColumn get name => text()();
  TextColumn get code => text()();
  TextColumn get locationType =>
      text()(); // SHOP_FLOOR, BACK_ROOM, DAMAGED, WAREHOUSE
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class StockLevels extends Table {
  TextColumn get id => text()();
  TextColumn get variantId => text().references(ProductVariants, #id)();
  TextColumn get locationId => text().references(StockLocations, #id)();
  IntColumn get quantity => integer().withDefault(const Constant(0))();
  IntColumn get reservedQuantity => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class StockMovements extends Table {
  TextColumn get id => text()();
  TextColumn get variantId => text().references(ProductVariants, #id)();
  TextColumn get fromLocationId =>
      text().nullable().references(StockLocations, #id)();
  TextColumn get toLocationId =>
      text().nullable().references(StockLocations, #id)();
  TextColumn get movementType =>
      text()(); // INITIAL, PURCHASE_RECEIPT, SALE, RETURN, DAMAGE, etc.
  IntColumn get quantityDelta => integer()(); // positive or negative
  IntColumn get unitCostMillimes => integer().withDefault(const Constant(0))();
  TextColumn get referenceId =>
      text().nullable()(); // sale_id, po_id, return_id, count_id, etc.
  TextColumn get referenceType =>
      text().nullable()(); // SALE, PURCHASE, RETURN, ADJUSTMENT
  TextColumn get actorId => text().nullable().references(Users, #id)();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class InventoryCounts extends Table {
  TextColumn get id => text()();
  TextColumn get countNumber => text().unique()();
  TextColumn get locationId => text().references(StockLocations, #id)();
  TextColumn get status => text().withDefault(
    const Constant('IN_PROGRESS'),
  )(); // IN_PROGRESS, COMPLETED, CANCELLED
  TextColumn get scope =>
      text().withDefault(const Constant('FULL'))(); // FULL, CATEGORY, BRAND
  TextColumn get initiatedById => text().references(Users, #id)();
  TextColumn get approvedById => text().nullable().references(Users, #id)();
  DateTimeColumn get approvedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class InventoryCountLines extends Table {
  TextColumn get id => text()();
  TextColumn get inventoryCountId => text().references(InventoryCounts, #id)();
  TextColumn get variantId => text().references(ProductVariants, #id)();
  IntColumn get expectedQuantity => integer()();
  IntColumn get countedQuantity => integer()();
  IntColumn get differenceQuantity => integer()();
  IntColumn get unitCostMillimes => integer().withDefault(const Constant(0))();
  BoolColumn get isReconciled => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class StockTransfers extends Table {
  TextColumn get id => text()();
  TextColumn get transferNumber => text().unique()();
  TextColumn get fromLocationId => text().references(StockLocations, #id)();
  TextColumn get toLocationId => text().references(StockLocations, #id)();
  TextColumn get status => text().withDefault(
    const Constant('DRAFT'),
  )(); // DRAFT, REQUESTED, SENT, RECEIVED, CANCELLED
  TextColumn get initiatedById => text().references(Users, #id)();
  TextColumn get receivedById => text().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get receivedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class StockTransferLines extends Table {
  TextColumn get id => text()();
  TextColumn get stockTransferId => text().references(StockTransfers, #id)();
  TextColumn get variantId => text().references(ProductVariants, #id)();
  IntColumn get requestedQty => integer()();
  IntColumn get sentQty => integer().withDefault(const Constant(0))();
  IntColumn get receivedQty => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
