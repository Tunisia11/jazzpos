import 'package:drift/drift.dart';

class Promotions extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get promotionType => text()(); // PERCENTAGE, FIXED, BUY_X_GET_Y
  RealColumn get value => real()(); // percentage (e.g. 20.0) or fixed millimes as double
  IntColumn get minCartMillimes => integer().withDefault(const Constant(0))();
  IntColumn get minQuantity => integer().withDefault(const Constant(1))();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get priority => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class PromotionRules extends Table {
  TextColumn get id => text()();
  TextColumn get promotionId => text().references(Promotions, #id)();
  TextColumn get targetType => text()(); // ALL, PRODUCT, CATEGORY, BRAND, COLLECTION, VARIANT
  TextColumn get targetId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
