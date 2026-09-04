import 'package:drift/drift.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';

class AuditService {
  final AppDatabase db;

  AuditService(this.db);

  /// Log a system audit event
  Future<void> logEvent({
    required String action,
    required String entityType,
    String? entityId,
    required String userId,
    String? managerId,
    String detailsJson = '{}',
  }) async {
    await db
        .into(db.auditEvents)
        .insert(
          AuditEventsCompanion.insert(
            id: IdGenerator.uuid(),
            action: action,
            entityType: entityType,
            entityId: Value(entityId),
            userId: userId,
            managerId: Value(managerId),
            detailsJson: Value(detailsJson),
            createdAt: DateTime.now(),
          ),
        );
  }

  /// Get recent audit logs
  Future<List<AuditEvent>> getRecentEvents({int limit = 100}) async {
    return (db.select(db.auditEvents)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }
}
