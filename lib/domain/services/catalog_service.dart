import 'package:drift/drift.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';
import '../models/variant_matrix.dart';
import 'inventory_service.dart';

class VariantSearchResult {
  final String variantId;
  final String productId;
  final String productName;
  final String variantDescription;
  final String sku;
  final String barcode;
  final Money salePrice;
  final Money costPrice;
  final int stock;
  final double taxRatePercent;

  const VariantSearchResult({
    required this.variantId,
    required this.productId,
    required this.productName,
    required this.variantDescription,
    required this.sku,
    required this.barcode,
    required this.salePrice,
    required this.costPrice,
    required this.stock,
    required this.taxRatePercent,
  });
}

class CatalogService {
  final AppDatabase db;
  final InventoryService inventoryService;

  CatalogService(this.db, this.inventoryService);

  /// Check if an SKU already exists
  Future<bool> isSkuUnique(String sku, {String? excludeVariantId}) async {
    final query = db.select(db.productVariants)..where((tbl) => tbl.sku.equals(sku.trim()));
    if (excludeVariantId != null) {
      query.where((tbl) => tbl.id.isNotValue(excludeVariantId));
    }
    final match = await query.getSingleOrNull();
    return match == null;
  }

  /// Check if a barcode already exists in product_variants or barcode_aliases
  Future<bool> isBarcodeUnique(String barcode, {String? excludeVariantId}) async {
    final clean = barcode.trim();
    final vQuery = db.select(db.productVariants)..where((tbl) => tbl.barcode.equals(clean));
    if (excludeVariantId != null) {
      vQuery.where((tbl) => tbl.id.isNotValue(excludeVariantId));
    }
    if (await vQuery.getSingleOrNull() != null) return false;

    final aQuery = db.select(db.barcodeAliases)..where((tbl) => tbl.barcode.equals(clean));
    if (excludeVariantId != null) {
      aQuery.where((tbl) => tbl.variantId.isNotValue(excludeVariantId));
    }
    return await aQuery.getSingleOrNull() == null;
  }

  /// Multi-tier instant search: Barcode exact -> SKU exact -> Name -> Brand -> Category
  Future<List<VariantSearchResult>> searchVariants(String query, {int limit = 50}) async {
    final q = query.trim();
    if (q.isEmpty) {
      return getAllActiveVariants(limit: limit);
    }

    final results = <VariantSearchResult>[];
    final seenVariantIds = <String>{};

    // Tier 1: Exact Barcode in product_variants
    final exactBarcode = await (db.select(db.productVariants)..where((tbl) => tbl.barcode.equals(q) & tbl.isActive.equals(true))).get();
    for (final v in exactBarcode) {
      if (seenVariantIds.add(v.id)) {
        results.add(await _buildSearchResult(v));
      }
    }

    // Tier 1b: Exact Barcode in barcode_aliases
    final aliasMatch = await (db.select(db.barcodeAliases)..where((tbl) => tbl.barcode.equals(q) & tbl.isActive.equals(true))).get();
    for (final alias in aliasMatch) {
      if (!seenVariantIds.contains(alias.variantId)) {
        final v = await (db.select(db.productVariants)..where((tbl) => tbl.id.equals(alias.variantId) & tbl.isActive.equals(true))).getSingleOrNull();
        if (v != null && seenVariantIds.add(v.id)) {
          results.add(await _buildSearchResult(v));
        }
      }
    }

    // If exact barcode matched, return immediately for instant POS scanning!
    if (results.isNotEmpty) return results;

    // Tier 2: Exact SKU
    final exactSku = await (db.select(db.productVariants)..where((tbl) => tbl.sku.equals(q.toUpperCase()) & tbl.isActive.equals(true))).get();
    for (final v in exactSku) {
      if (seenVariantIds.add(v.id)) {
        results.add(await _buildSearchResult(v));
      }
    }

    // Tier 3: SKU prefix or contains
    final partialSku = await (db.select(db.productVariants)
          ..where((tbl) => tbl.sku.like('%$q%') & tbl.isActive.equals(true))
          ..limit(limit))
        .get();
    for (final v in partialSku) {
      if (seenVariantIds.add(v.id) && results.length < limit) {
        results.add(await _buildSearchResult(v));
      }
    }

    // Tier 4: Product Name match
    final products = await (db.select(db.products)
          ..where((tbl) => (tbl.name.like('%$q%') | tbl.secondaryName.like('%$q%')) & tbl.status.equals('ACTIVE'))
          ..limit(limit))
        .get();

    for (final p in products) {
      final variants = await (db.select(db.productVariants)..where((tbl) => tbl.productId.equals(p.id) & tbl.isActive.equals(true))).get();
      for (final v in variants) {
        if (seenVariantIds.add(v.id) && results.length < limit) {
          results.add(await _buildSearchResult(v, product: p));
        }
      }
    }

    return results;
  }

  Future<List<VariantSearchResult>> getAllActiveVariants({int limit = 50}) async {
    final variants = await (db.select(db.productVariants)
          ..where((tbl) => tbl.isActive.equals(true))
          ..limit(limit))
        .get();
    final results = <VariantSearchResult>[];
    for (final v in variants) {
      results.add(await _buildSearchResult(v));
    }
    return results;
  }

  Future<VariantSearchResult> _buildSearchResult(ProductVariant variant, {Product? product}) async {
    final prod = product ?? await (db.select(db.products)..where((tbl) => tbl.id.equals(variant.productId))).getSingle();
    final stock = await inventoryService.getStock(variant.id);

    // Fetch attribute values for variant description
    final attrQuery = db.select(db.variantAttributeValues).join([
      innerJoin(db.attributeValues, db.attributeValues.id.equalsExp(db.variantAttributeValues.attributeValueId)),
    ])..where(db.variantAttributeValues.variantId.equals(variant.id));

    final rows = await attrQuery.get();
    final descList = rows.map((r) => r.readTable(db.attributeValues).value).toList();
    final desc = descList.isEmpty ? 'Standard' : descList.join(' / ');

    final salePriceMillimes = variant.salePriceOverrideMillimes ?? prod.defaultPriceMillimes;
    final costPriceMillimes = variant.costPriceOverrideMillimes ?? prod.defaultCostMillimes;

    return VariantSearchResult(
      variantId: variant.id,
      productId: prod.id,
      productName: prod.name,
      variantDescription: desc,
      sku: variant.sku,
      barcode: variant.barcode,
      salePrice: Money.fromMillimes(salePriceMillimes),
      costPrice: Money.fromMillimes(costPriceMillimes),
      stock: stock,
      taxRatePercent: prod.taxRatePercent,
    );
  }

  /// Create product with variant matrix and initial stock movements
  Future<String> createProductWithMatrix({
    required String name,
    String? secondaryName,
    String? description,
    String? brandId,
    String? categoryId,
    String? collectionId,
    required Money defaultCost,
    required Money defaultPrice,
    double taxRatePercent = 0.0,
    required List<MatrixVariantItem> variants,
    required String actorId,
    String? storeId,
  }) async {
    final productId = IdGenerator.uuid();
    final now = DateTime.now();

    await db.transaction(() async {
      // 1. Insert product
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: productId,
              name: name,
              secondaryName: Value(secondaryName),
              description: Value(description),
              brandId: Value(brandId),
              categoryId: Value(categoryId),
              collectionId: Value(collectionId),
              defaultCostMillimes: Value(defaultCost.millimes),
              defaultPriceMillimes: Value(defaultPrice.millimes),
              taxRatePercent: Value(taxRatePercent),
              createdAt: now,
              updatedAt: now,
            ),
          );

      // 2. Insert variants and attributes
      StockLocation? defaultLocation;
      if (storeId != null) {
        defaultLocation = await inventoryService.getDefaultLocation(storeId);
      }

      for (final item in variants) {
        if (!item.isEnabled) continue;

        // Collision check
        if (!await isSkuUnique(item.sku)) {
          throw DuplicateException('SKU already exists: ${item.sku}');
        }
        if (!await isBarcodeUnique(item.barcode)) {
          throw DuplicateException('Barcode already exists: ${item.barcode}');
        }

        await db.into(db.productVariants).insert(
              ProductVariantsCompanion.insert(
                id: item.id,
                productId: productId,
                sku: item.sku,
                barcode: item.barcode,
                costPriceOverrideMillimes: Value(item.costPrice.millimes != defaultCost.millimes ? item.costPrice.millimes : null),
                salePriceOverrideMillimes: Value(item.salePrice.millimes != defaultPrice.millimes ? item.salePrice.millimes : null),
                minStockAlert: Value(item.minStockAlert),
                createdAt: now,
                updatedAt: now,
              ),
            );

        // Attribute mappings
        for (final entry in item.selectedAttributes.entries) {
          await db.into(db.variantAttributeValues).insert(
                VariantAttributeValuesCompanion.insert(
                  variantId: item.id,
                  attributeValueId: entry.value.id,
                ),
              );
        }

        // Initial stock movement if specified
        if (item.initialStock > 0 && defaultLocation != null) {
          await inventoryService.recordMovement(
            variantId: item.id,
            movementType: AppConstants.movementInitial,
            quantityDelta: item.initialStock,
            toLocationId: defaultLocation.id,
            unitCostMillimes: item.costPrice.millimes,
            actorId: actorId,
            reason: 'Initial stock on product creation',
          );
        }
      }

      // 3. Record audit event
      await db.into(db.auditEvents).insert(
            AuditEventsCompanion.insert(
              id: IdGenerator.uuid(),
              action: 'PRODUCT_CREATED',
              entityType: 'PRODUCT',
              entityId: Value(productId),
              userId: actorId,
              detailsJson: Value('{"name":"$name","variantsCount":${variants.length}}'),
              createdAt: now,
            ),
          );

      // 4. Record outbox event for sync
      await db.into(db.syncOutbox).insert(
            SyncOutboxCompanion.insert(
              id: IdGenerator.uuid(),
              entityType: 'PRODUCT',
              operation: 'INSERT',
              payloadJson: '{"id":"$productId","name":"$name"}',
              createdAt: now,
              updatedAt: now,
            ),
          );
    });

    PosLogger.instance.info('Catalog', 'Created product $name ($productId) with ${variants.length} variants');
    return productId;
  }

  /// Archive product (never physically delete products used in historical sales)
  Future<void> archiveProduct(String productId, String actorId) async {
    final now = DateTime.now();
    await (db.update(db.products)..where((tbl) => tbl.id.equals(productId))).write(
      ProductsCompanion(
        status: const Value('ARCHIVED'),
        updatedAt: Value(now),
      ),
    );

    await db.into(db.auditEvents).insert(
          AuditEventsCompanion.insert(
            id: IdGenerator.uuid(),
            action: 'PRODUCT_ARCHIVED',
            entityType: 'PRODUCT',
            entityId: Value(productId),
            userId: actorId,
            createdAt: now,
          ),
        );
  }

  /// Change variant price with audit history
  Future<void> updateVariantPrice({
    required String variantId,
    required Money newPrice,
    required String actorId,
    String? reason,
  }) async {
    final variant = await (db.select(db.productVariants)..where((tbl) => tbl.id.equals(variantId))).getSingle();
    final product = await (db.select(db.products)..where((tbl) => tbl.id.equals(variant.productId))).getSingle();

    final oldPriceMillimes = variant.salePriceOverrideMillimes ?? product.defaultPriceMillimes;
    if (oldPriceMillimes == newPrice.millimes) return;

    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.productVariants)..where((tbl) => tbl.id.equals(variantId))).write(
        ProductVariantsCompanion(
          salePriceOverrideMillimes: Value(newPrice.millimes),
          updatedAt: Value(now),
        ),
      );

      await db.into(db.priceHistories).insert(
            PriceHistoriesCompanion.insert(
              id: IdGenerator.uuid(),
              variantId: variantId,
              oldPriceMillimes: oldPriceMillimes,
              newPriceMillimes: newPrice.millimes,
              reason: Value(reason ?? 'Manual price update'),
              userId: actorId,
              createdAt: now,
            ),
          );

      await db.into(db.auditEvents).insert(
            AuditEventsCompanion.insert(
              id: IdGenerator.uuid(),
              action: 'PRICE_CHANGED',
              entityType: 'VARIANT',
              entityId: Value(variantId),
              userId: actorId,
              detailsJson: Value('{"oldPrice":$oldPriceMillimes,"newPrice":${newPrice.millimes},"reason":"$reason"}'),
              createdAt: now,
            ),
          );
    });
  }
}
