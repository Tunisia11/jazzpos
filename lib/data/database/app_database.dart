import 'package:drift/drift.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'database_connection.dart';
import 'tables/company_tables.dart';
import 'tables/user_tables.dart';
import 'tables/catalog_tables.dart';
import 'tables/inventory_tables.dart';
import 'tables/sale_tables.dart';
import 'tables/purchasing_tables.dart';
import 'tables/promotion_tables.dart';
import 'tables/hardware_tables.dart';
import 'tables/sync_and_audit_tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    // Company & Store hierarchy
    Companies,
    Stores,
    Registers,
    // Users & Security
    Users,
    UserPermissions,
    // Catalog & Variants
    Categories,
    Brands,
    Collections,
    Products,
    AttributeTypes,
    AttributeValues,
    ProductVariants,
    VariantAttributeValues,
    BarcodeAliases,
    PriceHistories,
    // Inventory
    StockLocations,
    StockLevels,
    StockMovements,
    InventoryCounts,
    InventoryCountLines,
    StockTransfers,
    StockTransferLines,
    // Sales & Shifts
    Shifts,
    CashMovements,
    Customers,
    Sales,
    SaleLines,
    SalePayments,
    Returns,
    ReturnLines,
    Exchanges,
    SuspendedCarts,
    Reservations,
    ReservationLines,
    // Purchasing
    Suppliers,
    PurchaseOrders,
    PurchaseOrderLines,
    GoodsReceipts,
    GoodsReceiptLines,
    // Promotions
    Promotions,
    PromotionRules,
    // Hardware
    HardwareDevices,
    PrintJobs,
    LabelTemplates,
    // Sync, Audit & Backup
    AuditEvents,
    SyncOutbox,
    AppSettings,
    BackupRecords,
    ImportBatches,
    ImportErrors,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? createDatabaseConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        PosLogger.instance.info(
          'Database',
          'Database created with schema version $schemaVersion',
        );

        // Create performance indexes for instant barcode, SKU and sale lookups
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_variant_barcode ON product_variants(barcode);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_variant_sku ON product_variants(sku);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_barcode_aliases_barcode ON barcode_aliases(barcode);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_products_name ON products(name);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_stock_movements_variant ON stock_movements(variant_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_stock_levels_variant ON stock_levels(variant_id, location_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sales_receipt ON sales(receipt_number);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sales_idempotency ON sales(idempotency_key);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sales_created_at ON sales(created_at);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sale_lines_sale_id ON sale_lines(sale_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sync_outbox_status ON sync_outbox(status);',
        );
      },
      onUpgrade: (Migrator m, int from, int to) async {
        PosLogger.instance.info(
          'Database',
          'Upgrading database from $from to $to',
        );
        if (from < 2) {
          await m.addColumn(products, products.imageUrl);
          await m.addColumn(products, products.deletedAt);
          await m.addColumn(productVariants, productVariants.imageUrl);
          await m.addColumn(productVariants, productVariants.deletedAt);
        }
      },
      beforeOpen: (details) async {
        // Enforce foreign keys on every connection
        await customStatement('PRAGMA foreign_keys = ON;');

        // Auto-heal any legacy or external text ISO strings into integer unix timestamps
        // across all schema tables non-destructively, protecting against FormatException.
        const tablesWithDates = [
          ('companies', ['created_at', 'updated_at']),
          ('stores', ['created_at', 'updated_at']),
          ('registers', ['created_at', 'updated_at']),
          ('users', ['created_at', 'updated_at']),
          ('products', ['created_at', 'updated_at', 'deleted_at']),
          ('product_variants', ['created_at', 'updated_at', 'deleted_at']),
          ('stock_levels', ['updated_at']),
          ('stock_movements', ['created_at']),
          ('inventory_counts', ['created_at', 'approved_at']),
          ('stock_transfers', ['created_at', 'received_at']),
          ('shifts', ['opened_at', 'closed_at']),
          ('customers', ['created_at']),
          ('sales', ['created_at']),
          ('sale_lines', ['created_at']),
          ('sale_payments', ['created_at']),
          ('returns', ['created_at']),
          ('return_lines', ['created_at']),
          ('exchanges', ['created_at']),
          ('suspended_carts', ['created_at']),
          ('reservations', ['created_at', 'expires_at']),
          ('suppliers', ['created_at']),
          ('purchase_orders', ['created_at', 'updated_at']),
          ('goods_receipts', ['created_at']),
          ('promotions', ['start_date', 'end_date']),
          ('hardware_devices', ['created_at', 'updated_at']),
          ('audit_events', ['created_at']),
          ('sync_outbox', ['created_at', 'updated_at']),
          ('backup_records', ['created_at']),
          ('import_batches', ['created_at']),
          ('import_errors', ['created_at']),
        ];

        for (final entry in tablesWithDates) {
          final table = entry.$1;
          final cols = entry.$2;
          for (final col in cols) {
            try {
              await customStatement(
                "UPDATE $table SET $col = CAST(strftime('%s', $col) AS INTEGER) "
                "WHERE $col IS NOT NULL AND typeof($col) = 'text';",
              );
            } catch (_) {
              // Safe skip if table or column does not exist yet during migration
            }
          }
        }

        // Guarantee that if 'REG-01' is ever referenced, it exists in registers
        // table, preventing foreign key constraint violations.
        try {
          await customStatement('''
            INSERT OR IGNORE INTO registers (id, store_id, name, code, created_at, updated_at)
            SELECT 'REG-01', s.id, 'Caisse 01', 'REG-01', CAST(strftime('%s', 'now') AS INTEGER), CAST(strftime('%s', 'now') AS INTEGER)
            FROM stores s LIMIT 1;
          ''');
        } catch (_) {}
      },
    );
  }
}
