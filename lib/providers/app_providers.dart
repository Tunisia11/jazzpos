import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/platform/environment_diagnostics_service.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/audit_service.dart';
import 'package:jazzpos/domain/services/auth_service.dart';
import 'package:jazzpos/domain/services/backup_service.dart';
import 'package:jazzpos/domain/services/catalog_service.dart';
import 'package:jazzpos/domain/services/database_integrity_service.dart';
import 'package:jazzpos/domain/services/exchange_service.dart';
import 'package:jazzpos/domain/services/import_export_service.dart';
import 'package:jazzpos/domain/services/inventory_count_service.dart';
import 'package:jazzpos/domain/services/inventory_service.dart';
import 'package:jazzpos/domain/services/pricing_service.dart';
import 'package:jazzpos/domain/services/promotion_service.dart';
import 'package:jazzpos/domain/services/purchase_service.dart';
import 'package:jazzpos/domain/services/product_image_service.dart';
import 'package:jazzpos/domain/services/report_service.dart';
import 'package:jazzpos/domain/services/return_service.dart';
import 'package:jazzpos/domain/services/sale_service.dart';
import 'package:jazzpos/domain/services/shift_service.dart';
import 'package:jazzpos/domain/services/sync_service.dart';
import 'package:jazzpos/hardware/hardware_manager.dart';

// Database Provider (singleton across app)
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final productImageServiceProvider = Provider<ProductImageService>((ref) {
  return ProductImageService();
});

// Hardware Manager Provider
final hardwareManagerProvider = Provider<HardwareManager>((ref) {
  final manager = HardwareManager.instance;
  manager.initialize();
  return manager;
});

// Domain Service Providers
final inventoryServiceProvider = Provider<InventoryService>((ref) {
  return InventoryService(ref.watch(databaseProvider));
});

final catalogServiceProvider = Provider<CatalogService>((ref) {
  return CatalogService(
    ref.watch(databaseProvider),
    ref.watch(inventoryServiceProvider),
  );
});

final saleServiceProvider = Provider<SaleService>((ref) {
  return SaleService(
    ref.watch(databaseProvider),
    ref.watch(inventoryServiceProvider),
  );
});

final returnServiceProvider = Provider<ReturnService>((ref) {
  return ReturnService(
    ref.watch(databaseProvider),
    ref.watch(inventoryServiceProvider),
  );
});

final exchangeServiceProvider = Provider<ExchangeService>((ref) {
  return ExchangeService(
    ref.watch(databaseProvider),
    ref.watch(returnServiceProvider),
    ref.watch(saleServiceProvider),
  );
});

final pricingServiceProvider = Provider<PricingService>((ref) {
  return PricingService(ref.watch(databaseProvider));
});

final promotionServiceProvider = Provider<PromotionService>((ref) {
  return PromotionService(ref.watch(databaseProvider));
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(databaseProvider));
});

final shiftServiceProvider = Provider<ShiftService>((ref) {
  return ShiftService(ref.watch(databaseProvider));
});

final purchaseServiceProvider = Provider<PurchaseService>((ref) {
  return PurchaseService(
    ref.watch(databaseProvider),
    ref.watch(inventoryServiceProvider),
  );
});

final inventoryCountServiceProvider = Provider<InventoryCountService>((ref) {
  return InventoryCountService(
    ref.watch(databaseProvider),
    ref.watch(inventoryServiceProvider),
  );
});

final reportServiceProvider = Provider<ReportService>((ref) {
  return ReportService(ref.watch(databaseProvider));
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(ref.watch(databaseProvider));
});

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref.watch(databaseProvider));
});

final databaseIntegrityServiceProvider = Provider<DatabaseIntegrityService>((
  ref,
) {
  return DatabaseIntegrityService(ref.watch(databaseProvider));
});

final importExportServiceProvider = Provider<ImportExportService>((ref) {
  return ImportExportService(
    ref.watch(databaseProvider),
    ref.watch(catalogServiceProvider),
    ref.watch(inventoryServiceProvider),
  );
});

final auditServiceProvider = Provider<AuditService>((ref) {
  return AuditService(ref.watch(databaseProvider));
});

final environmentDiagnosticsServiceProvider =
    Provider<EnvironmentDiagnosticsService>((ref) {
      return EnvironmentDiagnosticsService(
        database: ref.watch(databaseProvider),
      );
    });
