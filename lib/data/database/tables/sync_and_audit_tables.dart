import 'package:drift/drift.dart';
import 'user_tables.dart';

class AuditEvents extends Table {
  TextColumn get id => text()();
  TextColumn get action => text()(); // PRICE_CHANGED, SALE_VOID, RETURN, STOCK_ADJUSTMENT, DRAWER_OPEN, etc.
  TextColumn get entityType => text()(); // SALE, VARIANT, PRODUCT, USER, SHIFT
  TextColumn get entityId => text().nullable()();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get managerId => text().nullable().references(Users, #id)();
  TextColumn get detailsJson => text().withDefault(const Constant('{}'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncOutbox extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()(); // SALE, STOCK_MOVEMENT, SHIFT, PRODUCT
  TextColumn get operation => text()(); // INSERT, UPDATE, DELETE
  TextColumn get payloadJson => text()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('PENDING'))(); // PENDING, IN_PROGRESS, SYNCED, FAILED
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}

class BackupRecords extends Table {
  TextColumn get id => text()();
  TextColumn get filePath => text()();
  IntColumn get fileSizeBytes => integer()();
  TextColumn get checksum => text()();
  TextColumn get backupType => text()(); // LOCAL_SNAPSHOT, CLOUD_REPLICA
  TextColumn get status => text().withDefault(const Constant('COMPLETED'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class ImportBatches extends Table {
  TextColumn get id => text()();
  TextColumn get fileName => text()();
  IntColumn get totalRows => integer()();
  IntColumn get importedRows => integer()();
  IntColumn get errorRows => integer()();
  TextColumn get status => text()(); // COMPLETED, REVERSED, FAILED
  TextColumn get userId => text().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class ImportErrors extends Table {
  TextColumn get id => text()();
  TextColumn get importBatchId => text().references(ImportBatches, #id)();
  IntColumn get rowNumber => integer()();
  TextColumn get rawData => text()();
  TextColumn get errorMessage => text()();

  @override
  Set<Column> get primaryKey => {id};
}
