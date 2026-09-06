import 'package:drift/drift.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/data/database/app_database.dart';

class IntegrityReport {
  final bool isHealthy;
  final List<String> issues;
  final List<String> warnings;
  final int totalSales;
  final int totalProducts;
  final int totalVariants;
  final int totalMovements;

  const IntegrityReport({
    required this.isHealthy,
    required this.issues,
    required this.warnings,
    required this.totalSales,
    required this.totalProducts,
    required this.totalVariants,
    required this.totalMovements,
  });
}

class DatabaseIntegrityService {
  final AppDatabase db;

  DatabaseIntegrityService(this.db);

  /// Run comprehensive POS database diagnostics and integrity audit
  Future<IntegrityReport> runDiagnostics() async {
    final issues = <String>[];
    final warnings = <String>[];

    // 1. SQLite PRAGMA integrity check
    try {
      final rows = await db.customSelect('PRAGMA integrity_check;').get();
      for (final r in rows) {
        final val = r.data.values.first.toString();
        if (val != 'ok') {
          issues.add('SQLite integrity error: $val');
        }
      }
    } catch (e) {
      issues.add('Failed to run PRAGMA integrity_check: $e');
    }

    // 2. Foreign key check
    try {
      final fkRows = await db.customSelect('PRAGMA foreign_key_check;').get();
      if (fkRows.isNotEmpty) {
        issues.add('Found ${fkRows.length} foreign key constraint violations.');
      }
    } catch (e) {
      warnings.add('Foreign key check: $e');
    }

    // 3. Check orphan sale lines
    final orphanLines = await db.customSelect('''
      SELECT sl.id FROM sale_lines sl
      LEFT JOIN sales s ON sl.sale_id = s.id
      WHERE s.id IS NULL;
    ''').get();
    if (orphanLines.isNotEmpty) {
      issues.add(
        'Found ${orphanLines.length} orphan sale lines with missing parent sale',
      );
    }

    // 4. Check payments without sales
    final orphanPayments = await db.customSelect('''
      SELECT sp.id FROM sale_payments sp
      LEFT JOIN sales s ON sp.sale_id = s.id
      WHERE s.id IS NULL;
    ''').get();
    if (orphanPayments.isNotEmpty) {
      issues.add(
        'Found ${orphanPayments.length} orphan payment records with missing parent sale',
      );
    }

    // 5. Check duplicate barcodes in product_variants
    final duplicateBarcodes = await db.customSelect('''
      SELECT barcode, COUNT(*) as cnt FROM product_variants
      GROUP BY barcode HAVING cnt > 1;
    ''').get();
    if (duplicateBarcodes.isNotEmpty) {
      issues.add(
        'Found ${duplicateBarcodes.length} duplicate barcodes in active variants',
      );
    }

    // 6. Compare the cached per-location balances with the immutable stock
    // movement ledger. A transfer has both a source and a destination, so its
    // signed quantity alone is not sufficient to calculate either location.
    final movementRows = await db.select(db.stockMovements).get();
    final expectedByLevel = <String, int>{};
    for (final movement in movementRows) {
      final amount = movement.quantityDelta.abs();
      if (movement.fromLocationId != null) {
        final key = '${movement.variantId}|${movement.fromLocationId}';
        expectedByLevel[key] = (expectedByLevel[key] ?? 0) - amount;
      }
      if (movement.toLocationId != null) {
        final key = '${movement.variantId}|${movement.toLocationId}';
        expectedByLevel[key] = (expectedByLevel[key] ?? 0) + amount;
      }
    }
    final cachedLevels = await db.select(db.stockLevels).get();
    final cachedByLevel = <String, int>{};
    for (final level in cachedLevels) {
      final key = '${level.variantId}|${level.locationId}';
      cachedByLevel[key] = (cachedByLevel[key] ?? 0) + level.quantity;
    }
    final allLevelKeys = {...expectedByLevel.keys, ...cachedByLevel.keys};
    final ledgerMismatches = allLevelKeys.where(
      (key) => (expectedByLevel[key] ?? 0) != (cachedByLevel[key] ?? 0),
    );
    if (ledgerMismatches.isNotEmpty) {
      issues.add(
        'Found ${ledgerMismatches.length} stock level(s) that differ from the stock movement ledger.',
      );
    }

    // 7. Metrics
    final salesCount = (await db.select(db.sales).get()).length;
    final productsCount = (await db.select(db.products).get()).length;
    final variantsCount = (await db.select(db.productVariants).get()).length;
    final movementsCount = (await db.select(db.stockMovements).get()).length;

    final healthy = issues.isEmpty;
    PosLogger.instance.info(
      'Integrity',
      'Integrity check finished. Status: ${healthy ? "HEALTHY" : "ISSUES FOUND"}',
    );

    return IntegrityReport(
      isHealthy: healthy,
      issues: issues,
      warnings: warnings,
      totalSales: salesCount,
      totalProducts: productsCount,
      totalVariants: variantsCount,
      totalMovements: movementsCount,
    );
  }

  /// Self-repair cached stock levels by rebuilding from the immutable stock movements ledger!
  Future<int> rebuildStockLevelsFromMovements() async {
    PosLogger.instance.info(
      'Integrity',
      'Rebuilding cached stock levels from immutable stock movements ledger...',
    );

    final variants = await db.select(db.productVariants).get();
    int repairedCount = 0;

    await db.transaction(() async {
      for (final v in variants) {
        final movements = await (db.select(
          db.stockMovements,
        )..where((tbl) => tbl.variantId.equals(v.id))).get();
        final stockLevels = await (db.select(
          db.stockLevels,
        )..where((tbl) => tbl.variantId.equals(v.id))).get();
        final expectedByLocation = <String, int>{};
        for (final movement in movements) {
          final amount = movement.quantityDelta.abs();
          if (movement.fromLocationId != null) {
            final locationId = movement.fromLocationId!;
            expectedByLocation[locationId] =
                (expectedByLocation[locationId] ?? 0) - amount;
          }
          if (movement.toLocationId != null) {
            final locationId = movement.toLocationId!;
            expectedByLocation[locationId] =
                (expectedByLocation[locationId] ?? 0) + amount;
          }
        }
        final levelByLocation = {
          for (final level in stockLevels) level.locationId: level,
        };
        final locationIds = {
          ...expectedByLocation.keys,
          ...levelByLocation.keys,
        };
        for (final locationId in locationIds) {
          final expected = expectedByLocation[locationId] ?? 0;
          final existing = levelByLocation[locationId];
          if (existing == null) {
            await db
                .into(db.stockLevels)
                .insert(
                  StockLevelsCompanion.insert(
                    id: '${v.id}-$locationId',
                    variantId: v.id,
                    locationId: locationId,
                    quantity: Value(expected),
                    updatedAt: DateTime.now(),
                  ),
                );
            repairedCount++;
          } else if (existing.quantity != expected) {
            await (db.update(
              db.stockLevels,
            )..where((tbl) => tbl.id.equals(existing.id))).write(
              StockLevelsCompanion(
                quantity: Value(expected),
                updatedAt: Value(DateTime.now()),
              ),
            );
            repairedCount++;
          }
        }
      }
    });

    PosLogger.instance.info(
      'Integrity',
      'Rebuilt stock levels: repaired $repairedCount discrepancies',
    );
    return repairedCount;
  }
}
