import 'package:drift/drift.dart';
import 'package:tracepos/core/logging/pos_logger.dart';
import 'package:tracepos/data/database/app_database.dart';

/// Implements the two-way conflict resolution policy:
/// - Cloud wins on Catalog (names, descriptions) and Pricing.
/// - Register wins on physical Stock counts and completed Sales.
class ConflictResolver {
  final AppDatabase db;

  const ConflictResolver(this.db);

  /// Apply remote catalog/pricing updates down to local SQLite database.
  /// Remote pricing overwrites local pricing for future sales, but local
  /// inventory quantities ([StockLevels]) are untouched.
  Future<void> applyRemoteProduct(Map<String, dynamic> remoteProduct) async {
    final productId = remoteProduct['id'] as String?;
    if (productId == null || productId.isEmpty) return;

    final name = (remoteProduct['name'] as String?) ?? 'Produit';
    final description = remoteProduct['description'] as String?;
    final defaultPrice = (remoteProduct['default_price_millimes'] as num?)?.toInt() ?? 0;
    final defaultCost = (remoteProduct['default_cost_millimes'] as num?)?.toInt() ?? 0;
    final status = (remoteProduct['status'] as String?) ?? 'ACTIVE';
    final remoteUpdatedAt = remoteProduct['updated_at'] != null
        ? DateTime.tryParse(remoteProduct['updated_at'].toString()) ?? DateTime.now()
        : DateTime.now();

    await db.transaction(() async {
      // 1. Upsert Product
      final existingProduct = await (db.select(db.products)
            ..where((t) => t.id.equals(productId)))
          .getSingleOrNull();

      if (existingProduct == null) {
        await db.into(db.products).insert(
              ProductsCompanion.insert(
                id: productId,
                name: name,
                description: Value(description),
                defaultPriceMillimes: Value(defaultPrice),
                defaultCostMillimes: Value(defaultCost),
                status: Value(status),
                createdAt: remoteUpdatedAt,
                updatedAt: remoteUpdatedAt,
              ),
            );
        PosLogger.instance.info(
          'ConflictResolver',
          'Inserted new cloud product: $name ($productId)',
        );
      } else {
        // Cloud wins on pricing & details
        await (db.update(db.products)..where((t) => t.id.equals(productId))).write(
          ProductsCompanion(
            name: Value(name),
            description: Value(description),
            defaultPriceMillimes: Value(defaultPrice),
            defaultCostMillimes: Value(defaultCost),
            status: Value(status),
            updatedAt: Value(remoteUpdatedAt),
          ),
        );
        PosLogger.instance.info(
          'ConflictResolver',
          'Updated local product from cloud: $name ($productId) -> price: $defaultPrice',
        );
      }

      // 2. Process variants (Cloud wins on price overrides, register preserves stock)
      final remoteVariants = remoteProduct['product_variants'];
      if (remoteVariants is List) {
        for (final item in remoteVariants) {
          if (item is! Map) continue;
          final variantMap = Map<String, dynamic>.from(item);
          final variantId = variantMap['id'] as String?;
          final sku = variantMap['sku'] as String?;
          final barcode = variantMap['barcode'] as String?;
          if (variantId == null || sku == null || barcode == null) continue;

          final salePriceOverride =
              (variantMap['sale_price_override_millimes'] as num?)?.toInt();
          final costPriceOverride =
              (variantMap['cost_price_override_millimes'] as num?)?.toInt();
          final isActive = (variantMap['is_active'] as bool?) ?? true;

          final existingVariant = await (db.select(db.productVariants)
                ..where((t) => t.id.equals(variantId)))
              .getSingleOrNull();

          if (existingVariant == null) {
            await db.into(db.productVariants).insert(
                  ProductVariantsCompanion.insert(
                    id: variantId,
                    productId: productId,
                    sku: sku,
                    barcode: barcode,
                    salePriceOverrideMillimes: Value(salePriceOverride),
                    costPriceOverrideMillimes: Value(costPriceOverride),
                    isActive: Value(isActive),
                    createdAt: remoteUpdatedAt,
                    updatedAt: remoteUpdatedAt,
                  ),
                );

            // Initialize default stock level at 0 if no local level exists yet
            final defaultLocation = await (db.select(db.stockLocations)
                  ..where((t) => t.isDefault.equals(true)))
                .getSingleOrNull();
            if (defaultLocation != null) {
              final existingLevel = await (db.select(db.stockLevels)
                    ..where(
                      (t) =>
                          t.variantId.equals(variantId) &
                          t.locationId.equals(defaultLocation.id),
                    ))
                  .getSingleOrNull();
              if (existingLevel == null) {
                await db.into(db.stockLevels).insert(
                      StockLevelsCompanion.insert(
                        id: '${variantId}_${defaultLocation.id}',
                        variantId: variantId,
                        locationId: defaultLocation.id,
                        quantity: const Value(0),
                        updatedAt: remoteUpdatedAt,
                      ),
                    );
              }
            }
          } else {
            // Update prices and status; KEEP local stock untouched
            await (db.update(db.productVariants)
                  ..where((t) => t.id.equals(variantId)))
                .write(
              ProductVariantsCompanion(
                salePriceOverrideMillimes: Value(salePriceOverride),
                costPriceOverrideMillimes: Value(costPriceOverride),
                isActive: Value(isActive),
                updatedAt: Value(remoteUpdatedAt),
              ),
            );
          }
        }
      }
    });
  }
}
