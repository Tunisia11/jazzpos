import 'package:drift/drift.dart';
import 'catalog_tables.dart';
import 'user_tables.dart';
import 'inventory_tables.dart';

class Suppliers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get contactPerson => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get taxNumber => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class PurchaseOrders extends Table {
  TextColumn get id => text()();
  TextColumn get poNumber => text().unique()();
  TextColumn get supplierId => text().references(Suppliers, #id)();
  TextColumn get status => text().withDefault(const Constant('DRAFT'))(); // DRAFT, ORDERED, PARTIALLY_RECEIVED, RECEIVED, CANCELLED
  IntColumn get totalCostMillimes => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class PurchaseOrderLines extends Table {
  TextColumn get id => text()();
  TextColumn get purchaseOrderId => text().references(PurchaseOrders, #id)();
  TextColumn get variantId => text().references(ProductVariants, #id)();
  IntColumn get expectedQty => integer()();
  IntColumn get receivedQty => integer().withDefault(const Constant(0))();
  IntColumn get unitCostMillimes => integer()();
  IntColumn get totalCostMillimes => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class GoodsReceipts extends Table {
  TextColumn get id => text()();
  TextColumn get grNumber => text().unique()();
  TextColumn get purchaseOrderId => text().nullable().references(PurchaseOrders, #id)();
  TextColumn get supplierId => text().references(Suppliers, #id)();
  TextColumn get invoiceReference => text().nullable()();
  TextColumn get receivedById => text().references(Users, #id)();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class GoodsReceiptLines extends Table {
  TextColumn get id => text()();
  TextColumn get goodsReceiptId => text().references(GoodsReceipts, #id)();
  TextColumn get variantId => text().references(ProductVariants, #id)();
  IntColumn get quantityReceived => integer()();
  IntColumn get quantityDamaged => integer().withDefault(const Constant(0))();
  IntColumn get quantityRejected => integer().withDefault(const Constant(0))();
  IntColumn get unitCostMillimes => integer()();
  TextColumn get locationId => text().references(StockLocations, #id)();

  @override
  Set<Column> get primaryKey => {id};
}
