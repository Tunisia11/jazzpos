/// Application-wide constants and enumerations.
class AppConstants {
  static const String appName = 'JazzPOS';
  static const String appVersion = '1.0.0+1';
  static const String currencyCode = 'TND';
  static const int currencyDecimals = 3;

  // Stock location types
  static const String locationShopFloor = 'SHOP_FLOOR';
  static const String locationBackRoom = 'BACK_ROOM';
  static const String locationDamaged = 'DAMAGED';
  static const String locationWarehouse = 'WAREHOUSE';

  // Negative stock policies
  static const String negativeStockBlock = 'BLOCK';
  static const String negativeStockWarn = 'WARN';
  static const String negativeStockOverride = 'MANAGER_OVERRIDE';

  // Payment methods
  static const String paymentCash = 'CASH';
  static const String paymentCard = 'CARD';
  static const String paymentMixed = 'MIXED';
  static const String paymentStoreCredit = 'STORE_CREDIT';
  static const String paymentOther = 'OTHER';

  // Sale statuses
  static const String saleCompleted = 'COMPLETED';
  static const String saleVoided = 'VOIDED';
  static const String saleExchanged = 'EXCHANGED';
  static const String saleRefunded = 'REFUNDED';
  static const String salePartiallyRefunded = 'PARTIALLY_REFUNDED';

  // Stock movement types
  static const String movementInitial = 'INITIAL';
  static const String movementPurchaseReceipt = 'PURCHASE_RECEIPT';
  static const String movementSale = 'SALE';
  static const String movementReturn = 'RETURN';
  static const String movementExchangeReturn = 'EXCHANGE_RETURN';
  static const String movementExchangeSale = 'EXCHANGE_SALE';
  static const String movementDamage = 'DAMAGE';
  static const String movementLoss = 'LOSS';
  static const String movementManualAdjustment = 'MANUAL_ADJUSTMENT';
  static const String movementStockCount = 'STOCK_COUNT';
  static const String movementTransferIn = 'TRANSFER_IN';
  static const String movementTransferOut = 'TRANSFER_OUT';
  static const String movementSupplierReturn = 'SUPPLIER_RETURN';

  // Return condition
  static const String returnConditionSellable = 'SELLABLE';
  static const String returnConditionDamaged = 'DAMAGED';

  // Shift status
  static const String shiftOpen = 'OPEN';
  static const String shiftClosed = 'CLOSED';

  // Cash movements
  static const String cashPayIn = 'PAY_IN';
  static const String cashPayOut = 'PAY_OUT';
  static const String cashDrop = 'CASH_DROP';

  // Sync outbox status
  static const String syncPending = 'PENDING';
  static const String syncInProgress = 'IN_PROGRESS';
  static const String syncSynced = 'SYNCED';
  static const String syncFailed = 'FAILED';

  // Device types
  static const String deviceReceiptPrinter = 'RECEIPT_PRINTER';
  static const String deviceLabelPrinter = 'LABEL_PRINTER';
  static const String deviceScanner = 'SCANNER';
  static const String deviceCashDrawer = 'CASH_DRAWER';
  static const String deviceCustomerDisplay = 'CUSTOMER_DISPLAY';

  // Device connection types
  static const String connUsb = 'USB';
  static const String connNetwork = 'NETWORK';
  static const String connSerial = 'SERIAL';
  static const String connWindowsDriver = 'WINDOWS_DRIVER';
  static const String connSimulated = 'SIMULATED';

  // Settings Keys
  static const String keyStoreName = 'store_name';
  static const String keyStoreAddress = 'store_address';
  static const String keyStorePhone = 'store_phone';
  static const String keyStoreFiscalId = 'store_fiscal_id';
  static const String keyNegativeStockPolicy = 'negative_stock_policy';
  static const String keyMaxCashierDiscountPercent = 'max_cashier_discount_percent';
  static const String keyAllowNoReceiptReturns = 'allow_no_receipt_returns';
  static const String keyAutoLockSeconds = 'auto_lock_seconds';
  static const String keyReceiptFooterMessage = 'receipt_footer_message';
  static const String keyLabelPaperSize = 'label_paper_size'; // 40x25, 40x30, 50x30, 60x40
  static const String keyCloudSyncEnabled = 'cloud_sync_enabled';
  static const String keyCloudSupabaseUrl = 'cloud_supabase_url';
  static const String keyCloudSupabaseKey = 'cloud_supabase_key';
  static const String keyKioskMode = 'kiosk_mode';
}
