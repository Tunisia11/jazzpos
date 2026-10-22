import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/core/constants/roles.dart';
import 'package:tracepos/data/database/app_database.dart';
import 'package:tracepos/domain/services/auth_service.dart';
import 'package:tracepos/domain/services/pos_initialization_service.dart';

void main() {
  if (Platform.environment['RUN_LIVE_DB_TESTS'] != 'true') {
    test('Live database checks require explicit opt-in', () {}, skip: 'Set RUN_LIVE_DB_TESTS=true only on an approved disposable database.');
    return;
  }

  final appData = Platform.environment['APPDATA'];
  final liveDbFile = (appData != null && Platform.isWindows)
      ? File('$appData/TracePOS/Trace POS/database/tracepos.sqlite')
      : null;
  final shouldRun = liveDbFile != null && liveDbFile.existsSync();

  test(
    'VERIFY LIVE REPRODUCTION: Initialize on exact live DB schema copy succeeds',
    () async {
      final liveDb = liveDbFile!;

    // Make a temporary copy so we do not mutate the live file during testing
    final tempDir = Directory.systemTemp.createTempSync('live_db_test_');
    final tempDbFile = File('${tempDir.path}/tracepos_copy.sqlite');
    liveDb.copySync(tempDbFile.path);

    final db = AppDatabase(NativeDatabase(tempDbFile));
    final initService = PosInitializationService(db);
    final authService = AuthService(db);

    try {
      // 1. Verify that setup is not yet completed
      expect(await initService.isSetupCompleted(), isFalse);

      // 2. Verify bootstrap is allowed because only a CASHIER exists
      expect(await initService.isBootstrapAllowed(), isTrue);

      // 3. Auto register code generation: REG-01 already exists in live DB, so next is REG-002
      final nextReg = await initService.generateNextRegisterCode();
      expect(nextReg, 'REG-002');

      // 4. Run full POS initialization
      await initService.initializePos(
        companyName: 'Boutique Mode Élégance',
        fiscalId: '1234567/A/M/000',
        phone: '71000000',
        address: 'Tunis Centre',
        storeName: 'Boutique Principale',
        registerCode: nextReg,
        registerName: 'Caisse Principale',
        locationName: 'Stock principal',
        ownerUsername: 'admin',
        ownerDisplayName: 'Directeur',
        ownerPin: '1234',
        paperWidthMm: 80,
      );

      // 5. Verify setup completed successfully
      expect(await initService.isSetupCompleted(), isTrue);
      expect(await initService.isBootstrapAllowed(), isFalse);

      // 6. Verify owner user exists and can log in immediately
      final session = await authService.login(username: 'admin', pin: '1234');
      expect(session.user.role, AppRoles.owner);
      expect(session.user.username, 'admin');

      // 7. Verify pre-existing cashier is still intact
      final cashier = await (db.select(db.users)..where((t) => t.id.equals('usr_inst'))).getSingle();
      expect(cashier.username, 'caissier');
    } finally {
      await db.close();
      tempDir.deleteSync(recursive: true);
    }
  }, skip: !shouldRun ? 'Requires live Windows AppData database file' : null);
}
