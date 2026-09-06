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
      },
    );
  }
}
