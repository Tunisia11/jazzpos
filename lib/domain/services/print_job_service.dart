import 'package:drift/drift.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/data/database/app_database.dart';

/// Keeps `print_jobs` rows honest: a job is SUCCESS or FAILED once a print
/// attempt finishes, and rows abandoned mid-flight (app closed, power cut)
/// are surfaced as FAILED instead of staying PENDING forever.
class PrintJobService {
  static const String pending = 'PENDING';
  static const String printing = 'PRINTING';
  static const String success = 'SUCCESS';
  static const String failed = 'FAILED';

  /// Touch this in main() so it records process start, not first use.
  static final DateTime processStart = DateTime.now();

  final AppDatabase db;
  PrintJobService(this.db);

  Future<void> markResult(
    String jobId, {
    required bool ok,
    String? error,
  }) async {
    if (jobId.isEmpty) return;
    final existing = await (db.select(db.printJobs)
          ..where((t) => t.id.equals(jobId)))
        .getSingleOrNull();
    if (existing == null) return;
    await (db.update(db.printJobs)..where((t) => t.id.equals(jobId))).write(
      PrintJobsCompanion(
        status: Value(ok ? success : failed),
        retryCount: Value(ok ? existing.retryCount : existing.retryCount + 1),
        errorMessage: Value(ok ? null : error),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Mark jobs still PENDING/PRINTING that were created before [cutoff]
  /// (normally app start) as FAILED. Returns how many were changed.
  Future<int> reconcileAbandonedJobs({DateTime? cutoff}) async {
    final limit = cutoff ?? processStart;
    final count = await (db.update(db.printJobs)
          ..where((t) =>
              t.status.isIn([pending, printing]) &
              t.createdAt.isSmallerThanValue(limit)))
        .write(
      PrintJobsCompanion(
        status: const Value(failed),
        errorMessage: const Value('Not printed: app closed before completion'),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (count > 0) {
      PosLogger.instance.warning(
        'PrintJobs',
        'Marked $count abandoned print job(s) as FAILED',
      );
    }
    return count;
  }
}
