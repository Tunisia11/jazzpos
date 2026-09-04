import 'package:drift/drift.dart';

class Users extends Table {
  TextColumn get id => text()();
  TextColumn get username => text().unique()();
  TextColumn get displayName => text()();
  TextColumn get role => text()(); // OWNER, MANAGER, CASHIER, STOCK_MANAGER
  TextColumn get pinHash => text()();
  TextColumn get pinSalt => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class UserPermissions extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get permission => text()();

  @override
  Set<Column> get primaryKey => {id};
}
