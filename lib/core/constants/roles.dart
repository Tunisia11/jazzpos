import 'permissions.dart';

/// User roles in the POS system.
class AppRoles {
  static const String owner = 'OWNER';
  static const String manager = 'MANAGER';
  static const String cashier = 'CASHIER';
  static const String stockManager = 'STOCK_MANAGER';

  static const List<String> allRoles = [owner, manager, cashier, stockManager];

  /// Default permissions per role
  static Set<String> defaultPermissionsForRole(String role) {
    switch (role) {
      case owner:
        return Set.from(AppPermissions.allPermissions);

      case manager:
        return {
          AppPermissions.viewCost,
          AppPermissions.changeSalePrice,
          AppPermissions.editProducts,
          AppPermissions.manageInventory,
          AppPermissions.applyManualDiscount,
          AppPermissions.authorizeLargeDiscount,
          AppPermissions.processReturn,
          AppPermissions.noReceiptReturn,
          AppPermissions.voidSale,
          AppPermissions.openDrawer,
          AppPermissions.manualStockAdjustment,
          AppPermissions.manageSuppliers,
          AppPermissions.manageShifts,
          AppPermissions.viewReports,
          AppPermissions.hardwareConfig,
          AppPermissions.managePromotions,
        };

      case stockManager:
        return {
          AppPermissions.viewCost,
          AppPermissions.editProducts,
          AppPermissions.manageInventory,
          AppPermissions.manualStockAdjustment,
          AppPermissions.manageSuppliers,
          AppPermissions.viewReports,
        };

      case cashier:
      default:
        return {
          AppPermissions.applyManualDiscount,
          AppPermissions.processReturn,
          AppPermissions.openDrawer,
        };
    }
  }
}
