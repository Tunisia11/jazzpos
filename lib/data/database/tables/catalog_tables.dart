import 'package:drift/drift.dart';
import 'user_tables.dart';

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get code => text().nullable()();
  TextColumn get parentId => text().nullable().references(Categories, #id)();

  @override
  Set<Column> get primaryKey => {id};
}

class Brands extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();

  @override
  Set<Column> get primaryKey => {id};
}

class Collections extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get season => text().nullable()();
  IntColumn get year => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Products extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get secondaryName => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get brandId => text().nullable().references(Brands, #id)();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get collectionId =>
      text().nullable().references(Collections, #id)();
  IntColumn get defaultCostMillimes =>
      integer().withDefault(const Constant(0))();
  IntColumn get defaultPriceMillimes =>
      integer().withDefault(const Constant(0))();
  IntColumn get oldPriceMillimes => integer().nullable()();
  RealColumn get taxRatePercent => real().withDefault(const Constant(0.0))();
  TextColumn get status => text().withDefault(
    const Constant('ACTIVE'),
  )(); // ACTIVE, ARCHIVED, DISCONTINUED
  TextColumn get imageUrl => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class AttributeTypes extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()(); // e.g. Size, Color, Fit, Shoe Size, Material
  TextColumn get code => text()(); // e.g. SIZE, COLOR, FIT

  @override
  Set<Column> get primaryKey => {id};
}

class AttributeValues extends Table {
  TextColumn get id => text()();
  TextColumn get attributeTypeId => text().references(AttributeTypes, #id)();
  TextColumn get value => text()(); // e.g. "S", "M", "L", "Black", "White"
  TextColumn get code => text()(); // e.g. "S", "M", "BLK", "WHT"

  @override
  Set<Column> get primaryKey => {id};
}

class ProductVariants extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get sku => text().unique()();
  TextColumn get barcode => text().unique()();
  IntColumn get costPriceOverrideMillimes => integer().nullable()();
  IntColumn get salePriceOverrideMillimes => integer().nullable()();
  IntColumn get minStockAlert => integer().withDefault(const Constant(2))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get imageUrl => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class VariantAttributeValues extends Table {
  TextColumn get variantId => text().references(ProductVariants, #id)();
  TextColumn get attributeValueId => text().references(AttributeValues, #id)();

  @override
  Set<Column> get primaryKey => {variantId, attributeValueId};
}

class BarcodeAliases extends Table {
  TextColumn get id => text()();
  TextColumn get variantId => text().references(ProductVariants, #id)();
  TextColumn get barcode => text().unique()();
  TextColumn get barcodeType => text().withDefault(const Constant('CODE128'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class PriceHistories extends Table {
  TextColumn get id => text()();
  TextColumn get variantId => text().references(ProductVariants, #id)();
  IntColumn get oldPriceMillimes => integer()();
  IntColumn get newPriceMillimes => integer()();
  TextColumn get reason => text().nullable()();
  TextColumn get userId => text().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
