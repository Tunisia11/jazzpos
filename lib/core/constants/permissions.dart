/// Granular system permissions for POS operations.
class AppPermissions {
  static const String viewCost = 'view_cost';
  static const String changeSalePrice = 'change_sale_price';
  static const String editProducts = 'edit_products';
  static const String manageInventory = 'manage_inventory';
  static const String applyManualDiscount = 'apply_manual_discount';
  static const String authorizeLargeDiscount = 'authorize_large_discount';
  static const String processReturn = 'process_return';
  static const String noReceiptReturn = 'no_receipt_return';
  static const String voidSale = 'void_sale';
  static const String openDrawer = 'open_drawer';
  static const String manualStockAdjustment = 'manual_stock_adjustment';
  static const String manageSuppliers = 'manage_suppliers';
  static const String manageShifts = 'manage_shifts';
  static const String viewReports = 'view_reports';
  static const String manageSettings = 'manage_settings';
  static const String manageUsers = 'manage_users';
  static const String hardwareConfig = 'hardware_config';
  static const String backupRestore = 'backup_restore';
  static const String managePromotions = 'manage_promotions';

  static const List<String> allPermissions = [
    viewCost,
    changeSalePrice,
    editProducts,
    manageInventory,
    applyManualDiscount,
    authorizeLargeDiscount,
    processReturn,
    noReceiptReturn,
    voidSale,
    openDrawer,
    manualStockAdjustment,
    manageSuppliers,
    manageShifts,
    viewReports,
    manageSettings,
    manageUsers,
    hardwareConfig,
    backupRestore,
    managePromotions,
  ];
}
