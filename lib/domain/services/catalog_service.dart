import 'package:drift/drift.dart';
import 'package:tracepos/core/constants/app_constants.dart';
import 'package:tracepos/core/constants/permissions.dart';
import 'package:tracepos/core/errors/failure.dart';
import 'package:tracepos/core/logging/pos_logger.dart';
import 'package:tracepos/core/money/money.dart';
import 'package:tracepos/core/utils/id_generator.dart';
import 'package:tracepos/data/database/app_database.dart';
import '../models/variant_matrix.dart';
import 'inventory_service.dart';
import 'permission_guard.dart';

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
  final int minStockAlert;
  final String? categoryId;
  final String? categoryName;
  final String? imageUrl;

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
    this.minStockAlert = 2,
    this.categoryId,
    this.categoryName,
    this.imageUrl,
  });
}

class CatalogService {
  final AppDatabase db;
  final InventoryService inventoryService;

  CatalogService(this.db, this.inventoryService);

  /// Check if an SKU already exists
  Future<bool> isSkuUnique(String sku, {String? excludeVariantId}) async {
    final query = db.select(db.productVariants)
      ..where((tbl) => tbl.sku.equals(sku.trim()));
    if (excludeVariantId != null) {
      query.where((tbl) => tbl.id.isNotValue(excludeVariantId));
    }
    final match = await query.getSingleOrNull();
    return match == null;
  }

  /// Check if a barcode already exists in product_variants or barcode_aliases
  Future<bool> isBarcodeUnique(
    String barcode, {
    String? excludeVariantId,
  }) async {
    final clean = barcode.trim();
    final vQuery = db.select(db.productVariants)
      ..where((tbl) => tbl.barcode.equals(clean));
    if (excludeVariantId != null) {
      vQuery.where((tbl) => tbl.id.isNotValue(excludeVariantId));
    }
    if (await vQuery.getSingleOrNull() != null) return false;

    final aQuery = db.select(db.barcodeAliases)
      ..where((tbl) => tbl.barcode.equals(clean));
    if (excludeVariantId != null) {
      aQuery.where((tbl) => tbl.variantId.isNotValue(excludeVariantId));
    }
    return await aQuery.getSingleOrNull() == null;
  }

  /// Find conflicting product or variant if barcode already in use
  Future<String?> findConflictForBarcode(
    String barcode, {
    String? excludeVariantId,
  }) async {
    final clean = barcode.trim();
    if (clean.isEmpty) return null;

    final vQuery = db.select(db.productVariants).join([
      innerJoin(
        db.products,
        db.products.id.equalsExp(db.productVariants.productId),
      ),
    ])..where(db.productVariants.barcode.equals(clean));
    if (excludeVariantId != null) {
      vQuery.where(db.productVariants.id.isNotValue(excludeVariantId));
    }
    final vRow = await vQuery.getSingleOrNull();
    if (vRow != null) {
      final p = vRow.readTable(db.products);
      final v = vRow.readTable(db.productVariants);
      return '${p.name} (${v.sku})';
    }

    final aQuery = db.select(db.barcodeAliases).join([
      innerJoin(
        db.productVariants,
        db.productVariants.id.equalsExp(db.barcodeAliases.variantId),
      ),
      innerJoin(
        db.products,
        db.products.id.equalsExp(db.productVariants.productId),
      ),
    ])..where(db.barcodeAliases.barcode.equals(clean));
    if (excludeVariantId != null) {
      aQuery.where(db.barcodeAliases.variantId.isNotValue(excludeVariantId));
    }
    final aRow = await aQuery.getSingleOrNull();
    if (aRow != null) {
      final p = aRow.readTable(db.products);
      final v = aRow.readTable(db.productVariants);
      return '${p.name} (${v.sku})';
    }

    return null;
  }

  /// Generate a unique, deterministic, collision-safe product SKU
  Future<String> generateNextProductSku({
    String? categoryId,
    String? prefix,
  }) async {
    String cleanPrefix = prefix?.trim().toUpperCase() ?? '';

    if (cleanPrefix.isEmpty && categoryId != null) {
      final cat = await (db.select(db.categories)
            ..where((tbl) => tbl.id.equals(categoryId)))
          .getSingleOrNull();
      if (cat != null) {
        if (cat.code != null && cat.code!.trim().isNotEmpty) {
          cleanPrefix = cat.code!.trim().toUpperCase();
        } else {
          // Derive 3-4 char abbreviation from category name
          final nameClean = cat.name
              .toUpperCase()
              .replaceAll(RegExp(r'[^A-Z0-9]'), '');
          cleanPrefix = nameClean.length >= 4
              ? nameClean.substring(0, 4)
              : (nameClean.isNotEmpty ? nameClean : 'ART');
        }
      }
    }

    if (cleanPrefix.isEmpty) {
      cleanPrefix = 'ART';
    }

    cleanPrefix = cleanPrefix.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (cleanPrefix.isEmpty) cleanPrefix = 'ART';

    // Find the max sequence number among existing variants starting with this prefix
    final allVariants = await (db.select(db.productVariants)).get();
    int maxSeq = 0;
    final prefixPattern = RegExp('^$cleanPrefix-(\\d{6})');

    for (final v in allVariants) {
      final match = prefixPattern.firstMatch(v.sku);
      if (match != null) {
        final num = int.tryParse(match.group(1) ?? '0') ?? 0;
        if (num > maxSeq) maxSeq = num;
      }
    }

    int candidateSeq = maxSeq + 1;
    String candidateSku =
        '$cleanPrefix-${candidateSeq.toString().padLeft(6, '0')}';

    while (!await isSkuUnique(candidateSku)) {
      candidateSeq++;
      candidateSku =
          '$cleanPrefix-${candidateSeq.toString().padLeft(6, '0')}';
    }

    return candidateSku;
  }

  /// Generate a unique EAN-13 barcode with valid check digit and collision verification
  Future<String> generateUniqueEan13({String prefix = '200'}) async {
    int attempts = 0;
    while (attempts < 100) {
      attempts++;
      final barcode = IdGenerator.generateEan13(prefix: prefix);
      if (await isBarcodeUnique(barcode)) {
        return barcode;
      }
    }
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    final data = prefix + ts.substring(ts.length - (12 - prefix.length));
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final digit = int.parse(data[i]);
      sum += (i % 2 == 0) ? digit : digit * 3;
    }
    final checkDigit = (10 - (sum % 10)) % 10;
    return '$data$checkDigit';
  }

  /// Create a new category
  Future<Category> createCategory({
    required String name,
    String? code,
    String? parentId,
    required String actorId,
  }) async {
    await PermissionGuard.requirePermission(
      db,
      actorId,
      AppPermissions.editProducts,
    );
    final id = IdGenerator.uuid();
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw const ValidationException('Le nom de la catégorie ne peut pas être vide.');
    }
    final cleanCode = code?.trim().toUpperCase();

    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        id: id,
        name: cleanName,
        code: Value(cleanCode != null && cleanCode.isNotEmpty ? cleanCode : null),
        parentId: Value(parentId),
      ),
    );

    PosLogger.instance.info('Catalog', 'Created category "$cleanName" ($id)');
    return (await (db.select(db.categories)..where((t) => t.id.equals(id))).getSingle());
  }

  /// Update an existing category
  Future<void> updateCategory({
    required String id,
    required String name,
    String? code,
    required String actorId,
  }) async {
    await PermissionGuard.requirePermission(
      db,
      actorId,
      AppPermissions.editProducts,
    );
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw const ValidationException('Le nom de la catégorie ne peut pas être vide.');
    }
    final cleanCode = code?.trim().toUpperCase();

    await (db.update(db.categories)..where((t) => t.id.equals(id))).write(
      CategoriesCompanion(
        name: Value(cleanName),
        code: Value(cleanCode != null && cleanCode.isNotEmpty ? cleanCode : null),
      ),
    );

    PosLogger.instance.info('Catalog', 'Updated category $id -> "$cleanName"');
  }

  /// Delete or archive category safely without corrupting existing products
  Future<void> deleteCategory({
    required String id,
    String? reassignToCategoryId,
    required String actorId,
  }) async {
    await PermissionGuard.requirePermission(
      db,
      actorId,
      AppPermissions.editProducts,
    );

    await db.transaction(() async {
      // 1. Safely reassign or unlink products referencing this category
      if (reassignToCategoryId != null &&
          reassignToCategoryId.isNotEmpty &&
          reassignToCategoryId != id) {
        await (db.update(db.products)..where((tbl) => tbl.categoryId.equals(id))).write(
          ProductsCompanion(categoryId: Value(reassignToCategoryId)),
        );
      } else {
        await (db.update(db.products)..where((tbl) => tbl.categoryId.equals(id))).write(
          const ProductsCompanion(categoryId: Value(null)),
        );
      }

      // 2. Unlink any child categories referencing this category
      await (db.update(db.categories)..where((tbl) => tbl.parentId.equals(id))).write(
        const CategoriesCompanion(parentId: Value(null)),
      );

      // 3. Delete category
      await (db.delete(db.categories)..where((tbl) => tbl.id.equals(id))).go();
    });

    PosLogger.instance.info('Catalog', 'Deleted category $id safely');
  }

  /// STRICT SCANNER-SPECIFIC EXACT LOOKUP (Mandatory POS Safety).
  ///
  /// Barcode scanning MUST NEVER add the wrong product.
  /// Evaluation order:
  ///   1. Exact primary barcode (exact string match preserving leading zeros)
  ///   2. Exact barcode alias
  ///   3. Optional exact SKU (case-insensitive full equality only)
  ///
  /// NEVER falls back to partial SKU, partial barcode, product name,
  /// or fuzzy search. Returns null if unknown.
  Future<VariantSearchResult?> findVariantByExactBarcode(
    String rawBarcode,
  ) async {
    final clean = rawBarcode.trim();
    if (clean.isEmpty) return null;

    // 1. Exact primary barcode in product_variants (active variant & active product)
    final exactBarcodeQuery = await (db.select(db.productVariants).join([
      innerJoin(
        db.products,
        db.products.id.equalsExp(db.productVariants.productId),
      ),
    ])..where(
      db.productVariants.barcode.equals(clean) &
          db.productVariants.isActive.equals(true) &
          db.products.status.equals('ACTIVE'),
    )..limit(1)).get();

    if (exactBarcodeQuery.isNotEmpty) {
      final v = exactBarcodeQuery.first.readTable(db.productVariants);
      final p = exactBarcodeQuery.first.readTable(db.products);
      return _buildSearchResult(v, product: p);
    }

    // 2. Exact barcode in barcode_aliases
    final aliasQuery = await (db.select(db.barcodeAliases).join([
      innerJoin(
        db.productVariants,
        db.productVariants.id.equalsExp(db.barcodeAliases.variantId),
      ),
      innerJoin(
        db.products,
        db.products.id.equalsExp(db.productVariants.productId),
      ),
    ])..where(
      db.barcodeAliases.barcode.equals(clean) &
          db.barcodeAliases.isActive.equals(true) &
          db.productVariants.isActive.equals(true) &
          db.products.status.equals('ACTIVE'),
    )..limit(1)).get();

    if (aliasQuery.isNotEmpty) {
      final v = aliasQuery.first.readTable(db.productVariants);
      final p = aliasQuery.first.readTable(db.products);
      return _buildSearchResult(v, product: p);
    }

    // 3. Optional exact SKU match only (case-insensitive full equality)
    final exactSkuQuery = await (db.select(db.productVariants).join([
      innerJoin(
        db.products,
        db.products.id.equalsExp(db.productVariants.productId),
      ),
    ])..where(
      db.productVariants.sku.equals(clean.toUpperCase()) &
          db.productVariants.isActive.equals(true) &
          db.products.status.equals('ACTIVE'),
    )..limit(1)).get();

    if (exactSkuQuery.isNotEmpty) {
      final v = exactSkuQuery.first.readTable(db.productVariants);
      final p = exactSkuQuery.first.readTable(db.products);
      return _buildSearchResult(v, product: p);
    }

    // Unknown barcode: do NOT add anything.
    return null;
  }

  /// Multi-tier instant search: Barcode exact -> SKU exact -> Name -> Brand -> Category
  Future<List<VariantSearchResult>> searchVariants(
    String query, {
    int limit = 50,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return getAllActiveVariants(limit: limit);
    }

    final results = <VariantSearchResult>[];
    final seenVariantIds = <String>{};

    // Tier 1: Exact Barcode in product_variants (active variant & active product)
    final exactBarcode =
        await (db.select(db.productVariants).join([
              innerJoin(
                db.products,
                db.products.id.equalsExp(db.productVariants.productId),
              ),
            ])..where(
              db.productVariants.barcode.equals(q) &
                  db.productVariants.isActive.equals(true) &
                  db.products.status.equals('ACTIVE'),
            ))
            .get();
    for (final row in exactBarcode) {
      final v = row.readTable(db.productVariants);
      final p = row.readTable(db.products);
      if (seenVariantIds.add(v.id)) {
        results.add(await _buildSearchResult(v, product: p));
      }
    }

    // Tier 1b: Exact Barcode in barcode_aliases
    final aliasMatch =
        await (db.select(db.barcodeAliases).join([
              innerJoin(
                db.productVariants,
                db.productVariants.id.equalsExp(db.barcodeAliases.variantId),
              ),
              innerJoin(
                db.products,
                db.products.id.equalsExp(db.productVariants.productId),
              ),
            ])..where(
              db.barcodeAliases.barcode.equals(q) &
                  db.barcodeAliases.isActive.equals(true) &
                  db.productVariants.isActive.equals(true) &
                  db.products.status.equals('ACTIVE'),
            ))
            .get();
    for (final row in aliasMatch) {
      final v = row.readTable(db.productVariants);
      final p = row.readTable(db.products);
      if (seenVariantIds.add(v.id)) {
        results.add(await _buildSearchResult(v, product: p));
      }
    }

    // If exact barcode matched, return immediately for instant POS scanning!
    if (results.isNotEmpty) return results;

    // Tier 2: Exact SKU
    final exactSku =
        await (db.select(db.productVariants).join([
              innerJoin(
                db.products,
                db.products.id.equalsExp(db.productVariants.productId),
              ),
            ])..where(
              db.productVariants.sku.equals(q.toUpperCase()) &
                  db.productVariants.isActive.equals(true) &
                  db.products.status.equals('ACTIVE'),
            ))
            .get();
    for (final row in exactSku) {
      final v = row.readTable(db.productVariants);
      final p = row.readTable(db.products);
      if (seenVariantIds.add(v.id)) {
        results.add(await _buildSearchResult(v, product: p));
      }
    }

    // Tier 3: SKU prefix or contains
    final partialSku =
        await (db.select(db.productVariants).join([
                innerJoin(
                  db.products,
                  db.products.id.equalsExp(db.productVariants.productId),
                ),
              ])
              ..where(
                db.productVariants.sku.like('%$q%') &
                    db.productVariants.isActive.equals(true) &
                    db.products.status.equals('ACTIVE'),
              )
              ..limit(limit))
            .get();
    for (final row in partialSku) {
      final v = row.readTable(db.productVariants);
      final p = row.readTable(db.products);
      if (seenVariantIds.add(v.id) && results.length < limit) {
        results.add(await _buildSearchResult(v, product: p));
      }
    }

    // Tier 4: Product Name match
    final products =
        await (db.select(db.products)
              ..where(
                (tbl) =>
                    (tbl.name.like('%$q%') | tbl.secondaryName.like('%$q%')) &
                    tbl.status.equals('ACTIVE'),
              )
              ..limit(limit))
            .get();

    for (final p in products) {
      final variants =
          await (db.select(db.productVariants)..where(
                (tbl) => tbl.productId.equals(p.id) & tbl.isActive.equals(true),
              ))
              .get();
      for (final v in variants) {
        if (seenVariantIds.add(v.id) && results.length < limit) {
          results.add(await _buildSearchResult(v, product: p));
        }
      }
    }

    return results;
  }

  Future<List<VariantSearchResult>> getAllActiveVariants({
    int limit = 50,
  }) async {
    final query =
        db.select(db.productVariants).join([
            innerJoin(
              db.products,
              db.products.id.equalsExp(db.productVariants.productId),
            ),
          ])
          ..where(
            db.productVariants.isActive.equals(true) &
                db.products.status.equals('ACTIVE'),
          )
          ..limit(limit);

    final rows = await query.get();
    final results = <VariantSearchResult>[];
    for (final row in rows) {
      final v = row.readTable(db.productVariants);
      final p = row.readTable(db.products);
      results.add(await _buildSearchResult(v, product: p));
    }
    return results;
  }

  Future<VariantSearchResult> _buildSearchResult(
    ProductVariant variant, {
    Product? product,
  }) async {
    final prod =
        product ??
        await (db.select(
          db.products,
        )..where((tbl) => tbl.id.equals(variant.productId))).getSingle();
    final stock = await inventoryService.getStock(variant.id);

    // Fetch attribute values for variant description
    final attrQuery = db.select(db.variantAttributeValues).join([
      innerJoin(
        db.attributeValues,
        db.attributeValues.id.equalsExp(
          db.variantAttributeValues.attributeValueId,
        ),
      ),
    ])..where(db.variantAttributeValues.variantId.equals(variant.id));

    final rows = await attrQuery.get();
    final descList = rows
        .map((r) => r.readTable(db.attributeValues).value)
        .toList();
    final desc = descList.isEmpty ? 'Standard' : descList.join(' / ');

    final salePriceMillimes =
        variant.salePriceOverrideMillimes ?? prod.defaultPriceMillimes;
    final costPriceMillimes =
        variant.costPriceOverrideMillimes ?? prod.defaultCostMillimes;

    Category? category;
    if (prod.categoryId != null) {
      category = await (db.select(
        db.categories,
      )..where((tbl) => tbl.id.equals(prod.categoryId!))).getSingleOrNull();
    }

    final imageUrl = variant.imageUrl ?? prod.imageUrl;

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
      minStockAlert: variant.minStockAlert,
      categoryId: prod.categoryId,
      categoryName: category?.name,
      imageUrl: imageUrl,
    );
  }

  /// Create product with variant matrix and initial stock movements
  Future<String> createProductWithMatrix({
    String? productId,
    required String name,
    String? secondaryName,
    String? description,
    String? brandId,
    String? categoryId,
    String? collectionId,
    String? imageUrl,
    required Money defaultCost,
    required Money defaultPrice,
    double taxRatePercent = 0.0,
    required List<MatrixVariantItem> variants,
    required String actorId,
    String? storeId,
  }) async {
    await PermissionGuard.requirePermission(
      db,
      actorId,
      AppPermissions.editProducts,
    );
    final effectiveProductId = productId ?? IdGenerator.uuid();
    final now = DateTime.now();

    await db.transaction(() async {
      // 1. Insert product
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: effectiveProductId,
              name: name,
              secondaryName: Value(secondaryName),
              description: Value(description),
              brandId: Value(brandId),
              categoryId: Value(categoryId),
              collectionId: Value(collectionId),
              imageUrl: Value(imageUrl),
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

        await db
            .into(db.productVariants)
            .insert(
              ProductVariantsCompanion.insert(
                id: item.id,
                productId: effectiveProductId,
                sku: item.sku,
                barcode: item.barcode,
                costPriceOverrideMillimes: Value(
                  item.costPrice.millimes != defaultCost.millimes
                      ? item.costPrice.millimes
                      : null,
                ),
                salePriceOverrideMillimes: Value(
                  item.salePrice.millimes != defaultPrice.millimes
                      ? item.salePrice.millimes
                      : null,
                ),
                minStockAlert: Value(item.minStockAlert),
                createdAt: now,
                updatedAt: now,
              ),
            );

        // Attribute mappings
        for (final entry in item.selectedAttributes.entries) {
          await db
              .into(db.variantAttributeValues)
              .insert(
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
      await db
          .into(db.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: IdGenerator.uuid(),
              action: 'PRODUCT_CREATED',
              entityType: 'PRODUCT',
              entityId: Value(effectiveProductId),
              userId: actorId,
              detailsJson: Value(
                '{"name":"$name","variantsCount":${variants.length}}',
              ),
              createdAt: now,
            ),
          );

      // 4. Record outbox event for sync
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              id: IdGenerator.uuid(),
              entityType: 'PRODUCT',
              operation: 'INSERT',
              payloadJson: '{"id":"$effectiveProductId","name":"$name"}',
              createdAt: now,
              updatedAt: now,
            ),
          );
    });

    PosLogger.instance.info(
      'Catalog',
      'Created product $name ($effectiveProductId) with ${variants.length} variants',
    );
    return effectiveProductId;
  }

  /// Archive product (never physically delete products used in historical sales)
  Future<void> archiveProduct(String productId, String actorId) async {
    await PermissionGuard.requirePermission(
      db,
      actorId,
      AppPermissions.editProducts,
    );
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(
        db.products,
      )..where((tbl) => tbl.id.equals(productId))).write(
        ProductsCompanion(
          status: const Value('ARCHIVED'),
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      await (db.update(
        db.productVariants,
      )..where((tbl) => tbl.productId.equals(productId))).write(
        ProductVariantsCompanion(
          isActive: const Value(false),
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      await db
          .into(db.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: IdGenerator.uuid(),
              action: 'PRODUCT_ARCHIVED',
              entityType: 'PRODUCT',
              entityId: Value(productId),
              userId: actorId,
              createdAt: now,
            ),
          );
    });
  }

  /// Soft-delete an article or specific variant while protecting historical sales
  Future<void> softDeleteProduct({
    required String productId,
    String? variantId,
    required String actorId,
  }) async {
    await PermissionGuard.requirePermission(
      db,
      actorId,
      AppPermissions.editProducts,
    );
    final now = DateTime.now();
    await db.transaction(() async {
      if (variantId != null) {
        await (db.update(
          db.productVariants,
        )..where((tbl) => tbl.id.equals(variantId))).write(
          ProductVariantsCompanion(
            isActive: const Value(false),
            deletedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }

      final activeRemaining =
          await (db.select(db.productVariants)..where(
                (tbl) =>
                    tbl.productId.equals(productId) & tbl.isActive.equals(true),
              ))
              .get();

      if (variantId == null || activeRemaining.isEmpty) {
        await (db.update(
          db.products,
        )..where((tbl) => tbl.id.equals(productId))).write(
          ProductsCompanion(
            status: const Value('ARCHIVED'),
            deletedAt: Value(now),
            updatedAt: Value(now),
          ),
        );

        await (db.update(
          db.productVariants,
        )..where((tbl) => tbl.productId.equals(productId))).write(
          ProductVariantsCompanion(
            isActive: const Value(false),
            deletedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }

      await db
          .into(db.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: IdGenerator.uuid(),
              action: 'PRODUCT_ARCHIVED',
              entityType: 'PRODUCT',
              entityId: Value(productId),
              userId: actorId,
              detailsJson: Value('{"variantId":"${variantId ?? ""}"}'),
              createdAt: now,
            ),
          );
    });
  }

  /// Update product image reference
  Future<void> updateProductImage({
    required String productId,
    String? variantId,
    required String? imageUrl,
    required String actorId,
  }) async {
    await PermissionGuard.requirePermission(
      db,
      actorId,
      AppPermissions.editProducts,
    );
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(
        db.products,
      )..where((tbl) => tbl.id.equals(productId))).write(
        ProductsCompanion(imageUrl: Value(imageUrl), updatedAt: Value(now)),
      );

      if (variantId != null) {
        await (db.update(
          db.productVariants,
        )..where((tbl) => tbl.id.equals(variantId))).write(
          ProductVariantsCompanion(
            imageUrl: Value(imageUrl),
            updatedAt: Value(now),
          ),
        );
      }

      await db
          .into(db.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: IdGenerator.uuid(),
              action: imageUrl != null
                  ? 'PRODUCT_IMAGE_UPDATED'
                  : 'PRODUCT_IMAGE_REMOVED',
              entityType: 'PRODUCT',
              entityId: Value(productId),
              userId: actorId,
              detailsJson: Value('{"imageUrl":"${imageUrl ?? ""}"}'),
              createdAt: now,
            ),
          );
    });
  }

  /// Full update of an article and variant from the stock management screen
  Future<void> updateProductFull({
    required String productId,
    required String variantId,
    required String name,
    required String sku,
    required String barcode,
    String? sizeOrVariant,
    required Money salePrice,
    required Money costPrice,
    String? categoryId,
    required int newStock,
    required int minStockAlert,
    String? imageUrl,
    required String actorId,
    String? locationId,
    String? stockAdjustmentReason,
  }) async {
    await PermissionGuard.requirePermission(
      db,
      actorId,
      AppPermissions.editProducts,
    );
    final cleanName = name.trim();
    final cleanSku = sku.trim().toUpperCase();
    final cleanBarcode = barcode.trim();

    if (cleanName.isEmpty) {
      throw const ValidationException('Le nom du produit est requis.');
    }
    if (cleanSku.isEmpty) {
      throw const ValidationException('Le code SKU est requis.');
    }
    if (cleanBarcode.isEmpty) {
      throw const ValidationException('Le code-barres est requis.');
    }

    // Check SKU uniqueness
    if (!await isSkuUnique(cleanSku, excludeVariantId: variantId)) {
      throw DuplicateException('Le code SKU "$cleanSku" est déjà utilisé.');
    }

    // Check Barcode uniqueness
    if (!await isBarcodeUnique(cleanBarcode, excludeVariantId: variantId)) {
      throw DuplicateException(
        'Le code-barres "$cleanBarcode" est déjà utilisé.',
      );
    }

    final variant = await (db.select(
      db.productVariants,
    )..where((tbl) => tbl.id.equals(variantId))).getSingle();
    final product = await (db.select(
      db.products,
    )..where((tbl) => tbl.id.equals(productId))).getSingle();

    final currentStock = await inventoryService.getStock(
      variantId,
      locationId: locationId,
    );
    final stockDelta = newStock - currentStock;

    final oldSalePriceMillimes =
        variant.salePriceOverrideMillimes ?? product.defaultPriceMillimes;
    final priceChanged = oldSalePriceMillimes != salePrice.millimes;

    final now = DateTime.now();

    await db.transaction(() async {
      // 1. Update Product
      await (db.update(
        db.products,
      )..where((tbl) => tbl.id.equals(productId))).write(
        ProductsCompanion(
          name: Value(cleanName),
          categoryId: Value(categoryId),
          defaultPriceMillimes: Value(salePrice.millimes),
          defaultCostMillimes: Value(costPrice.millimes),
          imageUrl: Value(imageUrl ?? product.imageUrl),
          updatedAt: Value(now),
        ),
      );

      // 2. Update Variant
      await (db.update(
        db.productVariants,
      )..where((tbl) => tbl.id.equals(variantId))).write(
        ProductVariantsCompanion(
          sku: Value(cleanSku),
          barcode: Value(cleanBarcode),
          salePriceOverrideMillimes: Value(salePrice.millimes),
          costPriceOverrideMillimes: Value(costPrice.millimes),
          minStockAlert: Value(minStockAlert),
          imageUrl: Value(imageUrl ?? variant.imageUrl),
          updatedAt: Value(now),
        ),
      );

      // 3. Price History if changed
      if (priceChanged) {
        await db
            .into(db.priceHistories)
            .insert(
              PriceHistoriesCompanion.insert(
                id: IdGenerator.uuid(),
                variantId: variantId,
                oldPriceMillimes: oldSalePriceMillimes,
                newPriceMillimes: salePrice.millimes,
                reason: const Value('Mise à jour fiche article'),
                userId: actorId,
                createdAt: now,
              ),
            );

        await db
            .into(db.auditEvents)
            .insert(
              AuditEventsCompanion.insert(
                id: IdGenerator.uuid(),
                action: 'PRICE_CHANGED',
                entityType: 'VARIANT',
                entityId: Value(variantId),
                userId: actorId,
                detailsJson: Value(
                  '{"oldPrice":$oldSalePriceMillimes,"newPrice":${salePrice.millimes},"reason":"Mise à jour fiche article"}',
                ),
                createdAt: now,
              ),
            );
      }

      // 4. Update Variant Attribute (Size / Variant) if provided
      if (sizeOrVariant != null && sizeOrVariant.trim().isNotEmpty) {
        final cleanDesc = sizeOrVariant.trim();
        var sizeType = await (db.select(
          db.attributeTypes,
        )..where((tbl) => tbl.code.equals('SIZE'))).getSingleOrNull();
        sizeType ??= (await db.select(db.attributeTypes).get()).firstOrNull;

        if (sizeType != null) {
          var attrVal =
              await (db.select(db.attributeValues)..where(
                    (tbl) =>
                        tbl.attributeTypeId.equals(sizeType!.id) &
                        tbl.value.equals(cleanDesc),
                  ))
                  .getSingleOrNull();

          if (attrVal == null) {
            final attrValId = IdGenerator.uuid();
            await db
                .into(db.attributeValues)
                .insert(
                  AttributeValuesCompanion.insert(
                    id: attrValId,
                    attributeTypeId: sizeType.id,
                    value: cleanDesc,
                    code: cleanDesc.toUpperCase(),
                  ),
                );
            attrVal = await (db.select(
              db.attributeValues,
            )..where((tbl) => tbl.id.equals(attrValId))).getSingle();
          }

          await (db.delete(
            db.variantAttributeValues,
          )..where((tbl) => tbl.variantId.equals(variantId))).go();

          await db
              .into(db.variantAttributeValues)
              .insert(
                VariantAttributeValuesCompanion.insert(
                  variantId: variantId,
                  attributeValueId: attrVal.id,
                ),
              );
        }
      }

      // 5. Critical: Stock manual adjustment audit movement if changed!
      if (stockDelta != 0) {
        final locId =
            locationId ??
            (await inventoryService.getDefaultLocation('STORE-01')).id;
        await inventoryService.adjustStock(
          variantId: variantId,
          locationId: locId,
          newQuantity: newStock,
          actorId: actorId,
          reason:
              stockAdjustmentReason ??
              'Ajustement manuel via fiche article (ancien: $currentStock, nouveau: $newStock)',
        );
      }

      // 6. Record audit event
      await db
          .into(db.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: IdGenerator.uuid(),
              action: 'PRODUCT_UPDATED',
              entityType: 'PRODUCT',
              entityId: Value(productId),
              userId: actorId,
              detailsJson: Value(
                '{"name":"$cleanName","sku":"$cleanSku","stockDelta":$stockDelta,"newStock":$newStock}',
              ),
              createdAt: now,
            ),
          );
    });

    PosLogger.instance.info(
      'Catalog',
      'Updated product $cleanName ($productId, variant $variantId), stockDelta=$stockDelta',
    );
  }

  /// Change variant price with audit history
  Future<void> updateVariantPrice({
    required String variantId,
    required Money newPrice,
    required String actorId,
    String? reason,
  }) async {
    await PermissionGuard.requirePermission(
      db,
      actorId,
      AppPermissions.changeSalePrice,
    );
    final variant = await (db.select(
      db.productVariants,
    )..where((tbl) => tbl.id.equals(variantId))).getSingle();
    final product = await (db.select(
      db.products,
    )..where((tbl) => tbl.id.equals(variant.productId))).getSingle();

    final oldPriceMillimes =
        variant.salePriceOverrideMillimes ?? product.defaultPriceMillimes;
    if (oldPriceMillimes == newPrice.millimes) return;

    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(
        db.productVariants,
      )..where((tbl) => tbl.id.equals(variantId))).write(
        ProductVariantsCompanion(
          salePriceOverrideMillimes: Value(newPrice.millimes),
          updatedAt: Value(now),
        ),
      );

      await db
          .into(db.priceHistories)
          .insert(
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

      await db
          .into(db.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: IdGenerator.uuid(),
              action: 'PRICE_CHANGED',
              entityType: 'VARIANT',
              entityId: Value(variantId),
              userId: actorId,
              detailsJson: Value(
                '{"oldPrice":$oldPriceMillimes,"newPrice":${newPrice.millimes},"reason":"$reason"}',
              ),
              createdAt: now,
            ),
          );
    });
  }
}
