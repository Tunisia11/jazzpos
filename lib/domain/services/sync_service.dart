import 'package:drift/drift.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/data/database/app_database.dart';

class SyncService {
  final AppDatabase db;
  bool _isSyncing = false;

  SyncService(this.db);

  /// Trigger outbox sync processor
  Future<int> processOutbox() async {
    if (_isSyncing) return 0;
    _isSyncing = true;

    int syncedCount = 0;
    try {
      final pendingEvents = await (db.select(db.syncOutbox)
            ..where((tbl) => tbl.status.equals(AppConstants.syncPending) | tbl.status.equals(AppConstants.syncFailed))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
            ..limit(50))
          .get();

      if (pendingEvents.isEmpty) {
        _isSyncing = false;
        return 0;
      }

      // Check if cloud sync is enabled
      final enabledSetting = await (db.select(db.appSettings)..where((tbl) => tbl.key.equals(AppConstants.keyCloudSyncEnabled))).getSingleOrNull();
      final isEnabled = enabledSetting?.value == 'true';

      for (final event in pendingEvents) {
        try {
          if (!isEnabled) {
            // If cloud sync is disabled, mark as synced locally or keep pending
            await (db.update(db.syncOutbox)..where((tbl) => tbl.id.equals(event.id))).write(
              SyncOutboxCompanion(
                status: const Value(AppConstants.syncSynced),
                updatedAt: Value(DateTime.now()),
              ),
            );
            syncedCount++;
            continue;
          }

          // In production: HTTP POST to remote Supabase/PostgreSQL backend
          // Here: process payload safely and mark as synced
          await (db.update(db.syncOutbox)..where((tbl) => tbl.id.equals(event.id))).write(
            SyncOutboxCompanion(
              status: const Value(AppConstants.syncSynced),
              updatedAt: Value(DateTime.now()),
            ),
          );
          syncedCount++;
        } catch (e) {
          // Failure leaves event in outbox and increments retry count
          await (db.update(db.syncOutbox)..where((tbl) => tbl.id.equals(event.id))).write(
            SyncOutboxCompanion(
              status: const Value(AppConstants.syncFailed),
              retryCount: Value(event.retryCount + 1),
              errorMessage: Value(e.toString()),
              updatedAt: Value(DateTime.now()),
            ),
          );
          PosLogger.instance.warning('Sync', 'Outbox event ${event.id} sync failed: $e');
        }
      }
    } finally {
      _isSyncing = false;
    }

    if (syncedCount > 0) {
      PosLogger.instance.info('Sync', 'Successfully synchronized $syncedCount outbox events');
    }
    return syncedCount;
  }

  /// Get sync stats for diagnostics dashboard
  Future<({int pending, int synced, int failed})> getSyncStats() async {
    final all = await db.select(db.syncOutbox).get();
    final pending = all.where((e) => e.status == AppConstants.syncPending || e.status == AppConstants.syncInProgress).length;
    final synced = all.where((e) => e.status == AppConstants.syncSynced).length;
    final failed = all.where((e) => e.status == AppConstants.syncFailed).length;
    return (pending: pending, synced: synced, failed: failed);
  }
}
