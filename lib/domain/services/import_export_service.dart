import 'package:csv/csv.dart';
import 'package:drift/drift.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/constants/permissions.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'catalog_service.dart';
import 'inventory_service.dart';
import 'permission_guard.dart';

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
    final firstLine = csvContent.split(RegExp(r'\r?\n')).firstOrNull ?? '';
    final delimiter = firstLine.split(';').length > firstLine.split(',').length
        ? ';'
        : ',';
    final rows = CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false,
      fieldDelimiter: delimiter,
    ).convert(csvContent);
    if (rows.length < 2) {
      throw const ValidationException('CSV file is empty or missing headers');
    }

    String normalizeHeader(Object value) => value
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');

    final headers = <String, int>{};
    for (var index = 0; index < rows.first.length; index++) {
      headers[normalizeHeader(rows.first[index])] = index;
    }
    int? column(List<String> aliases) {
      for (final alias in aliases) {
        final index = headers[normalizeHeader(alias)];
        if (index != null) return index;
      }
      return null;
    }

    final nameColumn = column(['Product Name', 'Name']);
    final skuColumn = column(['SKU']);
    final barcodeColumn = column(['Barcode']);
    final salePriceColumn = column(['Sale Price TND', 'SalePrice']);
    if (nameColumn == null ||
        skuColumn == null ||
        barcodeColumn == null ||
        salePriceColumn == null) {
      throw const ValidationException(
        'CSV headers must include Product Name, SKU, Barcode, and Sale Price TND.',
      );
    }

    final brandColumn = column(['Brand']);
    final categoryColumn = column(['Category']);
    final sizeColumn = column(['Size']);
    final colorColumn = column(['Color']);
    final costColumn = column(['Cost Price TND', 'CostPrice']);
    final stockColumn = column(['Stock']);

    String valueAt(List<dynamic> row, int? index) {
      if (index == null || index >= row.length) return '';
      return row[index].toString().trim();
    }

    final previews = <ImportRowPreview>[];
    final seenSkus = <String>{};
    final seenBarcodes = <String>{};

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.every((c) => c.toString().trim().isEmpty)) {
        continue;
      }

      final name = valueAt(row, nameColumn);
      final brand = valueAt(row, brandColumn);
      final category = valueAt(row, categoryColumn);
      final size = valueAt(row, sizeColumn);
      final color = valueAt(row, colorColumn);
      final sku = valueAt(row, skuColumn);
      final barcode = valueAt(row, barcodeColumn);
      final costStr = valueAt(row, costColumn);
      final priceStr = valueAt(row, salePriceColumn);
      final stockStr = valueAt(row, stockColumn);

      final errors = <String>[];
      if (name.isEmpty) errors.add('Missing product name');
      if (sku.isEmpty) {
        errors.add('Missing SKU');
      } else if (!seenSkus.add(sku)) {
        errors.add('Duplicate SKU in import file: $sku');
      }
      if (barcode.isEmpty) {
        errors.add('Missing barcode');
      } else if (!seenBarcodes.add(barcode)) {
        errors.add('Duplicate barcode in import file: $barcode');
      }

      if (sku.isNotEmpty && !await catalogService.isSkuUnique(sku)) {
        errors.add('SKU already exists in database: $sku');
      }
      if (barcode.isNotEmpty &&
          !await catalogService.isBarcodeUnique(barcode)) {
        errors.add('Barcode already exists in database: $barcode');
      }

      Money parseMoney(String input, String label) {
        if (input.isEmpty) return Money.zero;
        final normalized = input
            .replaceAll(RegExp(r'tnd|dt|\s', caseSensitive: false), '')
            .replaceAll(',', '.');
        final fraction = normalized.split('.');
        if (fraction.length == 2 && fraction.last.length > 3) {
          errors.add('$label must use at most 3 decimal places: $input');
          return Money.zero;
        }
        final parsed = Money.tryParse(input);
        if (parsed == null || parsed.isNegative) {
          errors.add('Invalid $label: $input');
          return Money.zero;
        }
        return parsed;
      }

      final cost = parseMoney(costStr, 'cost price');
      final price = parseMoney(priceStr, 'sale price');
      final stock = stockStr.isEmpty ? 0 : int.tryParse(stockStr);
      if (stock == null || stock < 0) {
        errors.add('Stock must be a non-negative whole number: $stockStr');
      }

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
          stock: stock ?? 0,
          isValid: errors.isEmpty,
          errorMessage: errors.isEmpty ? null : errors.join('; '),
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
    await PermissionGuard.requirePermission(
      db,
      actorId,
      AppPermissions.editProducts,
    );
    final store = await (db.select(
      db.stores,
    )..where((table) => table.id.equals(storeId))).getSingleOrNull();
    if (store == null) {
      throw const ValidationException('Import store does not exist.');
    }
    final batchId = IdGenerator.uuid();
    final now = DateTime.now();

    final validRows = preview.previews.where((p) => p.isValid).toList();
    final invalidRows = preview.previews.where((p) => !p.isValid).toList();

    final defaultLocation = await inventoryService.getDefaultLocation(storeId);

    await db.transaction(() async {
      // 1. Record batch metadata
      await db
          .into(db.importBatches)
          .insert(
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
        await db
            .into(db.importErrors)
            .insert(
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
        await db
            .into(db.products)
            .insert(
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
          await db
              .into(db.productVariants)
              .insert(
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

    PosLogger.instance.info(
      'Import',
      'Import batch $batchId finished: ${validRows.length} imported, ${invalidRows.length} errors',
    );
    return batchId;
  }

  /// Export Catalog to CSV string
  Future<String> exportCatalogCsv() async {
    final variants = await db.select(db.productVariants).get();
    final rows = <List<dynamic>>[
      [
        'Product Name',
        'SKU',
        'Barcode',
        'Sale Price TND',
        'Cost Price TND',
        'Stock',
        'Status',
      ],
    ];

    for (final v in variants) {
      final p = await (db.select(
        db.products,
      )..where((tbl) => tbl.id.equals(v.productId))).getSingle();
      final stock = await inventoryService.getStock(v.id);
      final salePrice = Money.fromMillimes(
        v.salePriceOverrideMillimes ?? p.defaultPriceMillimes,
      );
      final costPrice = Money.fromMillimes(
        v.costPriceOverrideMillimes ?? p.defaultCostMillimes,
      );

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

    return const ListToCsvConverter(fieldDelimiter: ';').convert(rows);
  }
}
