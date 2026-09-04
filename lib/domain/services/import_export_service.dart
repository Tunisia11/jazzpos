import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:drift/drift.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'catalog_service.dart';
import 'inventory_service.dart';

class ImportRowPreview {
  final int rowNumber;
  final String productName;
  final String? brand;
  final String? category;
  final String? size;
  final String? color;
  final String sku;
  final String barcode;
  final Money costPrice;
  final Money salePrice;
  final int stock;
  final bool isValid;
  final String? errorMessage;

  const ImportRowPreview({
    required this.rowNumber,
    required this.productName,
    this.brand,
    this.category,
    this.size,
    this.color,
    required this.sku,
    required this.barcode,
    required this.costPrice,
    required this.salePrice,
    required this.stock,
    required this.isValid,
    this.errorMessage,
  });
}

class ImportPreviewResult {
  final int totalRows;
  final int validRows;
  final int invalidRows;
  final List<ImportRowPreview> previews;

  const ImportPreviewResult({
    required this.totalRows,
    required this.validRows,
    required this.invalidRows,
    required this.previews,
  });
}

class ImportExportService {
  final AppDatabase db;
  final CatalogService catalogService;
  final InventoryService inventoryService;

  ImportExportService(this.db, this.catalogService, this.inventoryService);

  /// Parse and preview CSV product import without modifying database
  Future<ImportPreviewResult> previewCsvImport(String csvContent) async {
    final rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false).convert(csvContent);
    if (rows.length < 2) {
      throw const ValidationException('CSV file is empty or missing headers');
    }

    // Expect header: Name, Brand, Category, Size, Color, SKU, Barcode, CostPrice, SalePrice, Stock
    final previews = <ImportRowPreview>[];
    final seenSkus = <String>{};
    final seenBarcodes = <String>{};

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.every((c) => c.toString().trim().isEmpty)) continue;

      final name = row.isNotEmpty ? row[0].toString().trim() : '';
      final brand = row.length > 1 ? row[1].toString().trim() : null;
      final category = row.length > 2 ? row[2].toString().trim() : null;
      final size = row.length > 3 ? row[3].toString().trim() : null;
      final color = row.length > 4 ? row[4].toString().trim() : null;
      final sku = row.length > 5 ? row[5].toString().trim() : '';
      final barcode = row.length > 6 ? row[6].toString().trim() : '';
      final costStr = row.length > 7 ? row[7].toString().trim() : '0';
      final priceStr = row.length > 8 ? row[8].toString().trim() : '0';
      final stockStr = row.length > 9 ? row[9].toString().trim() : '0';

      String? error;
      if (name.isEmpty) error = 'Missing product name';
      if (sku.isEmpty) error = 'Missing SKU';
      if (barcode.isEmpty) error = 'Missing barcode';

      if (!seenSkus.add(sku)) {
        error = 'Duplicate SKU in import file: $sku';
      }
      if (!seenBarcodes.add(barcode)) {
        error = 'Duplicate barcode in import file: $barcode';
      }

      if (error == null && !await catalogService.isSkuUnique(sku)) {
        error = 'SKU already exists in database: $sku';
      }
      if (error == null && !await catalogService.isBarcodeUnique(barcode)) {
        error = 'Barcode already exists in database: $barcode';
      }

      final cost = Money.parse(costStr);
      final price = Money.parse(priceStr);
      final stock = int.tryParse(stockStr) ?? 0;

      previews.add(
        ImportRowPreview(
          rowNumber: i + 1,
          productName: name,
          brand: brand,
          category: category,
          size: size,
          color: color,
          sku: sku,
          barcode: barcode,
          costPrice: cost,
          salePrice: price,
          stock: stock,
          isValid: error == null,
          errorMessage: error,
        ),
      );
    }

    final valid = previews.where((p) => p.isValid).length;
    final invalid = previews.length - valid;

    return ImportPreviewResult(
      totalRows: previews.length,
      validRows: valid,
      invalidRows: invalid,
      previews: previews,
    );
  }

  /// Commit validated import preview to the database
  Future<String> commitImport({
    required ImportPreviewResult preview,
    required String fileName,
    required String actorId,
    required String storeId,
  }) async {
    final batchId = IdGenerator.uuid();
    final now = DateTime.now();

    final validRows = preview.previews.where((p) => p.isValid).toList();
    final invalidRows = preview.previews.where((p) => !p.isValid).toList();

    final defaultLocation = await inventoryService.getDefaultLocation(storeId);

    await db.transaction(() async {
      // 1. Record batch metadata
      await db.into(db.importBatches).insert(
            ImportBatchesCompanion.insert(
              id: batchId,
              fileName: fileName,
              totalRows: preview.totalRows,
              importedRows: validRows.length,
              errorRows: invalidRows.length,
              status: 'COMPLETED',
              userId: actorId,
              createdAt: now,
            ),
          );

      // Record errors
      for (final err in invalidRows) {
        await db.into(db.importErrors).insert(
              ImportErrorsCompanion.insert(
                id: IdGenerator.uuid(),
                importBatchId: batchId,
                rowNumber: err.rowNumber,
                rawData: '${err.productName},${err.sku},${err.barcode}',
                errorMessage: err.errorMessage ?? 'Unknown error',
              ),
            );
      }

      // Group valid rows by Product Name
      final grouped = <String, List<ImportRowPreview>>{};
      for (final r in validRows) {
        grouped.putIfAbsent(r.productName, () => []).add(r);
      }

      for (final entry in grouped.entries) {
        final prodName = entry.key;
        final items = entry.value;
        final first = items.first;

        final productId = IdGenerator.uuid();
        await db.into(db.products).insert(
              ProductsCompanion.insert(
                id: productId,
                name: prodName,
                defaultCostMillimes: Value(first.costPrice.millimes),
                defaultPriceMillimes: Value(first.salePrice.millimes),
                createdAt: now,
                updatedAt: now,
              ),
            );

        for (final item in items) {
          final variantId = IdGenerator.uuid();
          await db.into(db.productVariants).insert(
                ProductVariantsCompanion.insert(
                  id: variantId,
                  productId: productId,
                  sku: item.sku,
                  barcode: item.barcode,
                  costPriceOverrideMillimes: Value(item.costPrice.millimes),
                  salePriceOverrideMillimes: Value(item.salePrice.millimes),
                  createdAt: now,
                  updatedAt: now,
                ),
              );

          if (item.stock > 0) {
            await inventoryService.recordMovement(
              variantId: variantId,
              movementType: AppConstants.movementInitial,
              quantityDelta: item.stock,
              toLocationId: defaultLocation.id,
              unitCostMillimes: item.costPrice.millimes,
              actorId: actorId,
              reason: 'Import batch: $fileName',
            );
          }
        }
      }
    });

    PosLogger.instance.info('Import', 'Import batch $batchId finished: ${validRows.length} imported, ${invalidRows.length} errors');
    return batchId;
  }

  /// Export Catalog to CSV string
  Future<String> exportCatalogCsv() async {
    final variants = await db.select(db.productVariants).get();
    final rows = <List<dynamic>>[
      ['Product Name', 'SKU', 'Barcode', 'Sale Price TND', 'Cost Price TND', 'Stock', 'Status']
    ];

    for (final v in variants) {
      final p = await (db.select(db.products)..where((tbl) => tbl.id.equals(v.productId))).getSingle();
      final stock = await inventoryService.getStock(v.id);
      final salePrice = Money.fromMillimes(v.salePriceOverrideMillimes ?? p.defaultPriceMillimes);
      final costPrice = Money.fromMillimes(v.costPriceOverrideMillimes ?? p.defaultCostMillimes);

      rows.add([
        p.name,
        v.sku,
        v.barcode,
        salePrice.format(includeCurrency: false),
        costPrice.format(includeCurrency: false),
        stock,
        v.isActive ? 'ACTIVE' : 'INACTIVE',
      ]);
    }

    return const ListToCsvConverter().convert(rows);
  }
}
