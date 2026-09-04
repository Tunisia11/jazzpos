import 'package:drift/drift.dart';

class HardwareDevices extends Table {
  TextColumn get id => text()();
  TextColumn get deviceType => text()(); // RECEIPT_PRINTER, LABEL_PRINTER, SCANNER, CASH_DRAWER, CUSTOMER_DISPLAY
  TextColumn get name => text()();
  TextColumn get connectionType => text()(); // USB, NETWORK, SERIAL, WINDOWS_DRIVER, SIMULATED
  TextColumn get addressOrPort => text()(); // IP address, COM port, USB VID/PID, or queue name
  TextColumn get profileJson => text().withDefault(const Constant('{}'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class PrintJobs extends Table {
  TextColumn get id => text()();
  TextColumn get jobType => text()(); // RECEIPT, LABEL, SHIFT_REPORT
  TextColumn get targetDeviceId => text().nullable().references(HardwareDevices, #id)();
  TextColumn get payloadJson => text()();
  TextColumn get status => text().withDefault(const Constant('PENDING'))(); // PENDING, PRINTING, SUCCESS, FAILED
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class LabelTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get widthMm => integer()(); // e.g. 40, 50, 60
  IntColumn get heightMm => integer()(); // e.g. 25, 30, 40
  TextColumn get templateType => text().withDefault(const Constant('TSPL'))(); // TSPL, ZPL, ESC_POS
  TextColumn get contentJson => text()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
