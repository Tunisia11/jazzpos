import 'package:drift/drift.dart';

class Companies extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get fiscalId => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Stores extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get name => text()();
  TextColumn get code => text()();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Registers extends Table {
  TextColumn get id => text()();
  TextColumn get storeId => text().references(Stores, #id)();
  TextColumn get name => text()();
  TextColumn get code => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
