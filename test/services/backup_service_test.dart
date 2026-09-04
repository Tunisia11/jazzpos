import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/backup_service.dart';

void main() {
  late AppDatabase db;
  late BackupService backupService;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    backupService = BackupService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('BackupService Tests', () {
    test('Refuses invalid or corrupted backup files', () async {
      final tempFile = File('${Directory.systemTemp.path}/fake_corrupt_db.sqlite');
      await tempFile.writeAsString('This is not an SQLite database file at all!');

      try {
        expect(() => backupService.validateBackupFile(tempFile.path), throwsA(isA<ValidationException>()));
      } finally {
        if (await tempFile.exists()) await tempFile.delete();
      }
    });
  });
}
