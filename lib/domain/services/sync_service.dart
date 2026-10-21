import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/sync/cloud_sync_backend.dart';
import 'package:jazzpos/domain/sync/conflict_resolver.dart';
import 'package:jazzpos/domain/sync/supabase_sync_backend.dart';

class SyncService {
  final AppDatabase db;
  final CloudSyncBackend backend;
  final ConflictResolver _conflictResolver;
  bool _isSyncing = false;
  Timer? _periodicTimer;

  SyncService(this.db, {CloudSyncBackend? backend})
      : backend = backend ?? SupabaseSyncBackend(),
        _conflictResolver = ConflictResolver(db);

  bool get isSyncing => _isSyncing;

  /// Retrieve active cloud synchronization configuration and state.
  Future<({bool enabled, String url, String key, DateTime? lastSyncAt})>
      getCloudConfig() async {
    final settings = await (db.select(db.appSettings)
          ..where((t) => t.key.isIn([
                AppConstants.keyCloudSyncEnabled,
                AppConstants.keyCloudSupabaseUrl,
                AppConstants.keyCloudSupabaseKey,
                'cloud_last_sync_at',
              ])))
        .get();

    final map = {for (final s in settings) s.key: s.value};
    final enabled = map[AppConstants.keyCloudSyncEnabled] == 'true';
    final url = map[AppConstants.keyCloudSupabaseUrl] ?? '';
    final key = map[AppConstants.keyCloudSupabaseKey] ?? '';
    final lastSyncStr = map['cloud_last_sync_at'];
    final lastSyncAt =
        lastSyncStr != null ? DateTime.tryParse(lastSyncStr) : null;

    return (enabled: enabled, url: url, key: key, lastSyncAt: lastSyncAt);
  }

  /// Persist cloud synchronization credentials and parameters.
  Future<void> saveCloudConfig({
    required bool enabled,
    required String url,
    required String key,
  }) async {
    Future<void> upsert(String k, String v) async {
      final now = DateTime.now();
      final existing = await (db.select(db.appSettings)
            ..where((t) => t.key.equals(k)))
          .getSingleOrNull();
      if (existing != null) {
        await (db.update(db.appSettings)..where((t) => t.key.equals(k))).write(
          AppSettingsCompanion(value: Value(v), updatedAt: Value(now)),
        );
      } else {
        await db.into(db.appSettings).insert(
              AppSettingsCompanion.insert(key: k, value: v, updatedAt: now),
            );
      }
    }

    await upsert(AppConstants.keyCloudSyncEnabled, enabled ? 'true' : 'false');
    await upsert(AppConstants.keyCloudSupabaseUrl, url.trim());
    await upsert(AppConstants.keyCloudSupabaseKey, key.trim());

    if (backend is SupabaseSyncBackend) {
      final sb = backend as SupabaseSyncBackend;
      sb.supabaseUrl = url.trim();
      sb.apiKey = key.trim();
    }
  }

  /// Test connection to cloud backend using provided or saved credentials.
  Future<bool> testConnection({String? url, String? key}) async {
    final config = await getCloudConfig();
    final targetUrl = url ?? config.url;
    final targetKey = key ?? config.key;
    return backend.testConnection(targetUrl, targetKey);
  }

  /// Perform a full bidirectional sync: push local outbox events, then pull catalog/price updates.
  Future<({int pushed, int pulled, String? error})> syncNow() async {
    if (_isSyncing) {
      return (pushed: 0, pulled: 0, error: 'Synchronisation déjà en cours');
    }
    _isSyncing = true;

    int pushedCount = 0;
    int pulledCount = 0;
    String? syncError;

    try {
      final config = await getCloudConfig();
      if (!config.enabled) {
        return (pushed: 0, pulled: 0, error: 'Cloud sync is disabled');
      }

      if (config.url.isEmpty || config.key.isEmpty) {
        return (
          pushed: 0,
          pulled: 0,
          error: 'Identifiants Supabase non configurés',
        );
      }

      if (backend is SupabaseSyncBackend) {
        final sb = backend as SupabaseSyncBackend;
        sb.supabaseUrl = config.url;
        sb.apiKey = config.key;
      }

      // 1. PUSH PHASE: Drain outbox to remote backend (skipping dead-letter records)
      final pendingEvents = await (db.select(db.syncOutbox)
            ..where((tbl) =>
                (tbl.status.equals(AppConstants.syncPending) |
                 tbl.status.equals(AppConstants.syncFailed)) &
                tbl.retryCount.isSmallerThanValue(5))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
            ..limit(50))
          .get();

      for (final event in pendingEvents) {
        try {
          if (event.entityType == 'SALE') {
            await _pushSaleEvent(event);
          } else if (event.entityType == 'RETURN') {
            await _pushReturnEvent(event);
          } else if (event.entityType == 'PRODUCT') {
            await _pushProductEvent(event);
          }

          // Mark outbox row as SYNCED
          await (db.update(db.syncOutbox)
                ..where((tbl) => tbl.id.equals(event.id)))
              .write(
            SyncOutboxCompanion(
              status: const Value(AppConstants.syncSynced),
              updatedAt: Value(DateTime.now()),
            ),
          );
          pushedCount++;
        } catch (e) {
          final nextRetryCount = event.retryCount + 1;
          final isDeadLetter = nextRetryCount >= 5;
          await (db.update(db.syncOutbox)
                ..where((tbl) => tbl.id.equals(event.id)))
              .write(
            SyncOutboxCompanion(
              status: Value(
                isDeadLetter
                    ? AppConstants.syncDeadLetter
                    : AppConstants.syncFailed,
              ),
              retryCount: Value(nextRetryCount),
              errorMessage: Value(e.toString()),
              updatedAt: Value(DateTime.now()),
            ),
          );
          PosLogger.instance.warning(
            'Sync',
            'Failed to push outbox event ${event.id} (attempt $nextRetryCount${isDeadLetter ? ' - moved to Dead Letter Queue' : ''}): $e',
          );
        }
      }

      // 2. PULL PHASE: Fetch remote catalog and pricing updates
      bool pullSucceeded = false;
      try {
        final updates =
            await backend.pullCatalogUpdates(since: config.lastSyncAt);
        for (final product in updates) {
          await _conflictResolver.applyRemoteProduct(product);
          pulledCount++;
        }
        pullSucceeded = true;
      } catch (e) {
        PosLogger.instance.warning('Sync', 'Failed to pull catalog updates: $e');
      }

      // 3. Update last sync timestamp ONLY if pull succeeded
      if (pullSucceeded) {
        final now = DateTime.now();
        final lastSyncRow = await (db.select(db.appSettings)
              ..where((t) => t.key.equals('cloud_last_sync_at')))
            .getSingleOrNull();
        if (lastSyncRow != null) {
          await (db.update(db.appSettings)
                ..where((t) => t.key.equals('cloud_last_sync_at')))
            .write(
          AppSettingsCompanion(
            value: Value(now.toIso8601String()),
            updatedAt: Value(now),
          ),
        );
        } else {
          await db.into(db.appSettings).insert(
                AppSettingsCompanion.insert(
                  key: 'cloud_last_sync_at',
                  value: now.toIso8601String(),
                  updatedAt: now,
                ),
              );
        }
      }
    } catch (e) {
      syncError = e.toString();
      PosLogger.instance.error('Sync', 'Error during syncNow: $e');
    } finally {
      _isSyncing = false;
    }

    return (pushed: pushedCount, pulled: pulledCount, error: syncError);
  }

  Future<void> _pushSaleEvent(SyncOutboxData event) async {
    String? saleId;
    try {
      final payload = jsonDecode(event.payloadJson);
      saleId = payload['id'] as String?;
    } catch (_) {}

    if (saleId == null || saleId.isEmpty) {
      throw const SyncException('Invalid sale payload: missing id');
    }

    final sale = await (db.select(db.sales)
          ..where((t) => t.id.equals(saleId!)))
        .getSingleOrNull();
    if (sale == null) {
      throw SyncException('Local sale record not found: $saleId');
    }

    final lines =
        await (db.select(db.saleLines)..where((t) => t.saleId.equals(saleId!)))
            .get();
    final payments = await (db.select(db.salePayments)
          ..where((t) => t.saleId.equals(saleId!)))
        .get();

    final salePayload = {
      'id': sale.id,
      'receipt_number': sale.receiptNumber,
      'store_id': sale.storeId,
      'register_id': sale.registerId,
      'shift_id': sale.shiftId,
      'cashier_id': sale.cashierId,
      'customer_id': sale.customerId,
      'subtotal_millimes': sale.subtotalMillimes,
      'discount_millimes': sale.discountMillimes,
      'tax_millimes': sale.taxMillimes,
      'total_millimes': sale.totalMillimes,
      'status': sale.status,
      'notes': sale.notes,
      'idempotency_key': sale.idempotencyKey,
      'created_at': sale.createdAt.toUtc().toIso8601String(),
      'lines': lines
          .map((l) => {
                'id': l.id,
                'sale_id': l.saleId,
                'variant_id': l.variantId,
                'product_name': l.productName,
                'variant_description': l.variantDescription,
                'sku': l.sku,
                'barcode': l.barcode,
                'quantity': l.quantity,
                'unit_price_millimes': l.unitPriceMillimes,
                'total_millimes': l.totalMillimes,
              })
          .toList(),
      'payments': payments
          .map((p) => {
                'id': p.id,
                'sale_id': p.saleId,
                'payment_method': p.paymentMethod,
                'amount_millimes': p.amountMillimes,
                'tendered_millimes': p.tenderedMillimes,
                'change_millimes': p.changeMillimes,
                'created_at': p.createdAt.toUtc().toIso8601String(),
              })
          .toList(),
    };

    await backend.pushSale(salePayload);

    // Mark sale row as offlineSynced
    await (db.update(db.sales)..where((t) => t.id.equals(sale.id))).write(
      const SalesCompanion(offlineSynced: Value(true)),
    );
  }

  Future<void> _pushReturnEvent(SyncOutboxData event) async {
    String? returnId;
    try {
      final decoded = jsonDecode(event.payloadJson);
      returnId = decoded['id'] as String?;
    } catch (_) {}

    if (returnId == null || returnId.isEmpty) {
      throw const SyncException('Invalid return payload: missing id');
    }

    final ret = await (db.select(db.returns)..where((t) => t.id.equals(returnId!)))
        .getSingleOrNull();
    if (ret == null) {
      throw SyncException('Local return record not found: $returnId');
    }

    final returnPayload = {
      'id': ret.id,
      'return_number': ret.returnNumber,
      'store_id': ret.storeId,
      'register_id': ret.registerId,
      'shift_id': ret.shiftId,
      'cashier_id': ret.cashierId,
      'reason': ret.reason,
      'total_refund_millimes': ret.totalRefundMillimes,
      'refund_method': ret.refundMethod,
      'created_at': ret.createdAt.toUtc().toIso8601String(),
    };

    await backend.pushReturn(returnPayload);
  }

  Future<void> _pushProductEvent(SyncOutboxData event) async {
    Map<String, dynamic>? payload;
    try {
      payload = jsonDecode(event.payloadJson);
    } catch (e) {
      throw SyncException('Invalid product payload: $e');
    }
    if (payload == null) {
      throw const SyncException('Invalid product payload: empty');
    }
    await backend.pushProductUpdate(payload);
  }

  /// Original processOutbox method for backward compatibility
  Future<int> processOutbox() async {
    final result = await syncNow();
    return result.pushed;
  }

  /// Start periodic background sync.
  void startPeriodicSync({Duration interval = const Duration(minutes: 1)}) {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(interval, (_) => syncNow());
  }

  /// Stop periodic background sync.
  void stopPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  void dispose() {
    stopPeriodicSync();
  }

  /// Get sync stats for diagnostics dashboard
  Future<
      ({
        int pending,
        int synced,
        int failed,
        DateTime? lastSyncAt,
        bool isSyncing,
      })> getSyncStats() async {
    final all = await db.select(db.syncOutbox).get();
    final pending = all
        .where(
          (e) =>
              e.status == AppConstants.syncPending ||
              e.status == AppConstants.syncInProgress,
        )
        .length;
    final synced = all.where((e) => e.status == AppConstants.syncSynced).length;
    final failed = all.where((e) => e.status == AppConstants.syncFailed).length;

    final config = await getCloudConfig();
    return (
      pending: pending,
      synced: synced,
      failed: failed,
      lastSyncAt: config.lastSyncAt,
      isSyncing: _isSyncing,
    );
  }
}
