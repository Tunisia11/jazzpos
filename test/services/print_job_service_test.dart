import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/print_job_service.dart';

void main() {
  late AppDatabase db;
  late PrintJobService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    service = PrintJobService(db);
  });
  tearDown(() => db.close());

  Future<void> addJob(String id, DateTime at, {String status = 'PENDING'}) =>
      db.into(db.printJobs).insert(PrintJobsCompanion.insert(
            id: id,
            jobType: 'RECEIPT',
            payloadJson: '{}',
            status: Value(status),
            createdAt: at,
            updatedAt: at,
          ));

  Future<PrintJob> job(String id) =>
      (db.select(db.printJobs)..where((t) => t.id.equals(id))).getSingle();

  test('markResult records success and failure with retry count', () async {
    await addJob('a', DateTime(2026, 1, 1));
    await service.markResult('a', ok: false, error: 'paper out');
    var row = await job('a');
    expect((row.status, row.retryCount, row.errorMessage), ('FAILED', 1, 'paper out'));
    await service.markResult('a', ok: true);
    row = await job('a');
    expect((row.status, row.errorMessage), ('SUCCESS', null));
  });

  test('reconcile fails only abandoned jobs created before the cutoff', () async {
    final cutoff = DateTime(2026, 6, 1);
    await addJob('old', DateTime(2026, 5, 1));
    await addJob('old-done', DateTime(2026, 5, 1), status: 'SUCCESS');
    await addJob('new', DateTime(2026, 7, 1));
    expect(await service.reconcileAbandonedJobs(cutoff: cutoff), 1);
    expect((await job('old')).status, 'FAILED');
    expect((await job('old-done')).status, 'SUCCESS');
    expect((await job('new')).status, 'PENDING');
  });
}
