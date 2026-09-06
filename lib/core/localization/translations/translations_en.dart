import 'package:flutter/widgets.dart';
import '../app_localizations.dart';

class AppLocalizationsEn extends AppLocalizations {
  @override
  Locale get locale => const Locale('en');

  // --- Common & Actions ---
  @override
  String get appTitle => 'JAZZ POS';
  @override
  String get appSubtitle => 'Apparel Point of Sale & Retail Management';
  @override
  String get back => 'Back';
  @override
  String get cancel => 'Cancel';
  @override
  String get save => 'Save Changes';
  @override
  String get delete => 'Delete';
  @override
  String get archive => 'Archive';
  @override
  String get edit => 'Edit';
  @override
  String get add => 'Add';
  @override
  String get close => 'Close';
  @override
  String get confirm => 'Confirm';
  @override
  String get refresh => 'Refresh';
  @override
  String get search => 'Search';
  @override
  String get filter => 'Filter';
  @override
  String get all => 'All';
  @override
  String get none => 'None';
  @override
  String get actions => 'Actions';
  @override
  String get status => 'Status';
  @override
  String get reference => 'Reference';
  @override
  String get type => 'Type';
  @override
  String get date => 'Date';
  @override
  String get time => 'Time';
  @override
  String get quantity => 'Quantity';
  @override
  String get price => 'Price';
  @override
  String get costPrice => 'Cost Price';
  @override
  String get sellingPrice => 'Selling Price';
  @override
  String get total => 'Total';
  @override
  String get subtotal => 'Subtotal';
  @override
  String get discount => 'Discount';
  @override
  String get barcode => 'Barcode';
  @override
  String get sku => 'SKU';
  @override
  String get category => 'Category';
  @override
  String get notes => 'Notes';
  @override
  String get print => 'Print';
  @override
  String get export => 'Export';
  @override
  String get importAction => 'Import';
  @override
  String get success => 'Success';
  @override
  String get error => 'Error';
  @override
  String get warning => 'Warning';
  @override
  String get info => 'Info';
  @override
  String get loading => 'Loading...';
  @override
  String get processing => 'Processing...';
  @override
  String get yes => 'Yes';
  @override
  String get no => 'No';
  @override
  String get requiredField => 'This field is required';
  @override
  String get invalidValue => 'Invalid value';
  @override
  String get duplicateSku => 'This SKU already exists';
  @override
  String get duplicateBarcode =>
      'This barcode is already assigned to another item';

  // --- Navigation & Shell ---
  @override
  String get navPos => 'POS Cashier';
  @override
  String get navCatalog => 'Products & Sizes';
  @override
  String get navInventory => 'Stocks & Inventory';
  @override
  String get navPurchasing => 'Purchasing & Receiving';
  @override
  String get navReturns => 'Returns & Exchanges';
  @override
  String get navLabels => 'Barcode Labels';
  @override
  String get navShifts => 'Register & Z-Report';
  @override
  String get navReports => 'Financial Reports';
  @override
  String get navSettings => 'Settings & Hardware';
  @override
  String get collapseMenu => 'Collapse menu';
  @override
  String get expandMenu => 'Expand menu';
  @override
  String get lockRegister => 'Lock register';
  @override
  String get logoutSession => 'Log out';
  @override
  String get roleOwner => 'Owner';
  @override
  String get roleManager => 'Manager';
  @override
  String get roleCashier => 'Cashier';
  @override
  String get roleInventory => 'Inventory Specialist';

  // --- POS / Checkout ---
  @override
  String get register => 'Register';
  @override
  String get registerOpen => 'Register Open';
  @override
  String get registerClosed => 'Register Closed';
  @override
  String get clickToOpenRegister => 'Click to open register shift';
  @override
  String get openRegisterTitle => 'Open Register Shift';
  @override
  String get initialCashFloat => 'Opening cash float (TND)';
  @override
  String get openRegisterAction => 'Open Register';
  @override
  String get suspendedSales => 'Suspended Sales (F6)';
  @override
  String get openCashDrawer => 'Cash Drawer (F10)';
  @override
  String get drawerKickSuccess => 'Cash drawer kick signal triggered';
  @override
  String get searchProductOrBarcode => 'Search product or scan barcode...';
  @override
  String get allCategories => 'All Items';
  @override
  String get cart => 'Cart';
  @override
  String get cartEmpty => 'Cart is empty';
  @override
  String get cartEmptySubtitle =>
      'Scan a barcode or select an item from the catalog.';
  @override
  String get clearCart => 'Clear Cart';
  @override
  String get clearCartConfirm =>
      'Are you sure you want to discard the active cart?';
  @override
  String get holdSale => 'Hold Sale (F6)';
  @override
  String get holdSaleSuccess => 'Sale suspended successfully';
  @override
  String get resumeSale => 'Resume Sale';
  @override
  String get payAction => 'Checkout (F12)';
  @override
  String get paymentTitle => 'Complete Payment';
  @override
  String get paymentMethod => 'Payment Method';
  @override
  String get paymentCash => 'Cash';
  @override
  String get paymentCard => 'Card (POS)';
  @override
  String get paymentSplit => 'Split Payment';
  @override
  String get paymentCheck => 'Check';
  @override
  String get tenderedAmount => 'Amount Tendered';
  @override
  String get changeDue => 'Change Due';
  @override
  String get exactAmount => 'Exact Amount';
  @override
  String get completeSale => 'Confirm & Print Receipt';
  @override
  String get saleSuccess => 'Sale committed successfully';
  @override
  String get printReceipt => 'Print Receipt';
  @override
  String get receiptPreview => 'Receipt Preview';
  @override
  String get barcodeScannedSuccess => 'Item added';
  @override
  String get barcodeNotFound => 'No item matching barcode';
  @override
  String nArticles(int count) => '$count item${count == 1 ? '' : 's'}';
  @override
  String itemsInCart(int count) =>
      '$count item${count == 1 ? '' : 's'} in cart';
  @override
  String get quickBills => 'Quick Bills:';
  @override
  String get validatePayment => 'Validate Payment (Enter)';
  @override
  String get insufficientAmount => 'Insufficient amount tendered';
  @override
  String get invalidSplit => 'Invalid split payment';
  @override
  String get noActiveShift => 'No register shift is currently open!';
  @override
  String get invalidUserSession => 'Invalid user session';
  @override
  String get noSuspendedSales => 'No suspended sales';
  @override
  String get resumeThisSale => 'Resume this sale';
  @override
  String get replaceCart => 'Replace cart';
  @override
  String get cartNotEmptyTitle => 'Current cart not empty';
  @override
  String get cartNotEmptyBody =>
      'The current cart contains items. Resuming this suspended sale will replace the current cart. Do you want to proceed?';
  @override
  String get deleteSuspendedSaleTitle => 'Delete suspended sale';
  @override
  String deleteSuspendedSaleBody(String name) =>
      'Are you sure you want to permanently delete "$name"?';
  @override
  String get unnamedSale => 'Unnamed sale';

  // --- Catalog & Products ---
  @override
  String get productsTitle => 'Products & Catalog';
  @override
  String get newProduct => 'New Product';
  @override
  String get editProduct => 'Edit Product';
  @override
  String get deleteProduct => 'Delete Product';
  @override
  String get productName => 'Product Title';
  @override
  String get variantDescription => 'Variant / Size';
  @override
  String get size => 'Size';
  @override
  String get color => 'Color';
  @override
  String get minStockAlert => 'Low Stock Threshold';
  @override
  String get currentStock => 'Current Stock';
  @override
  String get stock => 'Stock';
  @override
  String get activeProducts => 'Active Items';
  @override
  String get archivedProducts => 'Archived Items';
  @override
  String get archiveProductConfirm =>
      'Do you want to archive this product? It will no longer appear on POS registers.';
  @override
  String get deleteProductConfirmTitle => 'Delete this product?';
  @override
  String get deleteProductConfirmBody =>
      'This will remove the product from active inventory and POS selection while permanently preserving historical sales and ledger transactions.';
  @override
  String get productSavedSuccess => 'Product saved successfully';
  @override
  String get productArchivedSuccess => 'Product archived successfully';
  @override
  String get productDeletedSuccess => 'Product deleted successfully';
  @override
  String get addOrEditPhoto => 'Add / Edit Photo';
  @override
  String get chooseImage => 'Choose File';
  @override
  String get removePhoto => 'Remove Photo';
  @override
  String get photoUpdatedSuccess => 'Photo updated successfully';
  @override
  String get noImage => 'No photo';
  @override
  String get matrixGenerator => 'Size & Color Matrix Generator (Ready-to-Wear)';
  @override
  String get generateVariants => 'Generate Variants';
  @override
  String get selectSizes => '1. Select Sizes:';
  @override
  String get selectColors => '2. Select Colors:';
  @override
  String get bulkPrice => 'Bulk Price';
  @override
  String get bulkStock => 'Bulk Initial Stock';
  @override
  String get active => 'Active';
  @override
  String get initialStock => 'Initial Stock';
  @override
  String get generalInfo => 'Product General Information';
  @override
  String get secondaryName => 'Secondary / Arabic Name (optional)';
  @override
  String get skuPrefix => 'SKU / Code Prefix';
  @override
  String get defaultCost => 'Default Cost Price (TND)';
  @override
  String get defaultPrice => 'Default Selling Price (TND)';
  @override
  String get taxRate => 'VAT Rate';
  @override
  String get noProductsFound => 'No products found in catalog';
  @override
  String get createFirstProduct => 'Create the first product';
  @override
  String get atLeastOneVariant =>
      'Please generate at least one active variant for this item';

  // --- Stocks & Inventory ---
  @override
  String get stockLevelsTitle => 'Stock Levels by Item';
  @override
  String get stockByArticle => 'Available Stock';
  @override
  String get stockTransfer => 'Transfer';
  @override
  String get inStock => 'In Stock';
  @override
  String get lowStock => 'Low Stock';
  @override
  String get outOfStock => 'Out of Stock';
  @override
  String get negativeStock => 'Negative Stock';
  @override
  String get manualStockAuditWarning =>
      'Modifying physical stock manually will adjust on-hand inventory and log a tracked audit movement.';
  @override
  String get stockAdjustmentReason => 'Manual adjustment from product card';
  @override
  String get stockCountTitle => 'Physical Inventory & Audit';
  @override
  String get initiateCount => 'Start Count Session';
  @override
  String get scanOrTypeBarcode => 'Scan barcode or enter code...';
  @override
  String get countedQty => 'Counted Qty';
  @override
  String get expectedQty => 'Book Qty';
  @override
  String get varianceQty => 'Variance';
  @override
  String get totalPiecesCounted => 'Total Items Counted';
  @override
  String get itemsWithVariance => 'Items with Discrepancy';
  @override
  String get varianceValue => 'Variance Value';
  @override
  String get validateAndApplyAudit => 'Apply & Reconcile Variances';
  @override
  String get countCompletedSuccess =>
      'Inventory session committed successfully';
  @override
  String get stockMovementsHistory => 'Stock Movements History (Audit)';
  @override
  String get startInventory => 'Start Inventory';
  @override
  String get noMovementsRecorded => 'No stock movements recorded';
  @override
  String get sourceLocation => 'Source Location';
  @override
  String get destinationLocation => 'Destination Location';
  @override
  String get transferQuantity => 'Quantity to transfer';
  @override
  String get transferReason => 'Transfer reason';
  @override
  String get atLeastTwoLocationsRequired =>
      'At least two stock locations are required';
  @override
  String get manual => 'Manual';
  @override
  String get transferSuccessful => 'Stock transfer completed successfully!';
  @override
  String get productActions => 'Product actions';
  @override
  String get deleteProductPrompt =>
      'This action will delete the product from the catalog.';
  @override
  String get protectedHistoryNote =>
      'Note: Past sales, transactions, and stock movements history remain fully protected and preserved.';
  @override
  String get filterArticlesPrompt =>
      'Filter articles by name, SKU or barcode...';
  @override
  String get noArticlesFoundInInventory => 'No articles found in inventory';

  // --- Purchasing & Receiving ---
  @override
  String get purchaseOrdersTitle => 'Purchasing & Supplier Orders';
  @override
  String get goodsReceivingTitle => 'Goods Receiving';
  @override
  String get newPurchaseOrder => 'New Purchase Order';
  @override
  String get supplier => 'Supplier';
  @override
  String get orderReference => 'Order Reference';
  @override
  String get expectedDelivery => 'Expected Delivery';
  @override
  String get receiveGoods => 'Receive Order';
  @override
  String get receivingCompleted => 'Shipment received successfully';
  @override
  String get noOrdersRecorded => 'No purchase orders or receipts recorded';
  @override
  String get registerSupplierReceipt => 'Record Supplier Receipt';
  @override
  String get invoiceOrDeliveryNote => 'Delivery Note / Invoice #';
  @override
  String get addArticles => 'Add Articles';
  @override
  String get qtyReceived => 'Qty Received';
  @override
  String get qtyDamaged => 'Damaged';
  @override
  String get validateReceiving => 'Confirm Receiving';
  @override
  String get noArticlesInReceiving =>
      'No articles in this receiving session.\nSelect or scan articles from the right.';
  @override
  String get selectSupplierPrompt => 'Please select a supplier first';
  @override
  String get addAtLeastOneArticlePrompt =>
      'Please add at least one received article';
  @override
  String get receivingSavedSuccess =>
      'Goods receiving recorded and stock updated successfully!';

  // --- Returns & Exchanges ---
  @override
  String get returnsExchangesTitle => 'Returns & Garment Exchanges';
  @override
  String get searchReceiptPrompt => 'Enter receipt # or scan barcode...';
  @override
  String get returnMode => 'Standard Return (Refund)';
  @override
  String get exchangeMode => 'Size / Item Exchange';
  @override
  String get returnConditionSellable => 'Perfect condition (Resellable)';
  @override
  String get returnConditionDamaged => 'Damaged / Defective';
  @override
  String get returnReason => 'Return Reason';
  @override
  String get replacementItem => 'Replacement Item';
  @override
  String get refundDueCustomer => 'Refund Amount Due to Customer';
  @override
  String get customerOwes => 'Balance Due from Customer';
  @override
  String get netDifferenceZero => 'Even Exchange (Difference 0.000 TND)';
  @override
  String get completeReturnAction => 'Confirm Return';
  @override
  String get completeExchangeAction => 'Confirm Exchange';
  @override
  String get returnSuccess => 'Return processed successfully';
  @override
  String get exchangeSuccess => 'Exchange finalized successfully';
  @override
  String get openRegisterSessionFirst => 'Please open a register shift first';
  @override
  String get selectArticleToReturnPrompt =>
      'Please select at least one article to return';
  @override
  String get selectReplacementArticlePrompt =>
      'Please select a replacement item';
  @override
  String get searchReceipt => 'SEARCH RECEIPT';
  @override
  String ticketNotFound(String receipt) => 'No receipt found for "$receipt"';
  @override
  String get purchasedItemsToReturn => 'Purchased items to return:';
  @override
  String get refundDetails => 'Refund Details';
  @override
  String get amountToRefund => 'Amount to Refund:';
  @override
  String get refundMethod => 'Refund Method:';
  @override
  String get paymentStoreCredit => 'Store Credit';
  @override
  String get searchTicketPlaceholder =>
      'Enter receipt number or scan receipt barcode';
  @override
  String get priceDifference => 'Price Difference:';
  @override
  String get selectNewReplacementArticle => 'Select new replacement item:';
  @override
  String get returnReasonSize => 'Incompatible size';
  @override
  String get returnReasonDefault => 'Item return';
  @override
  String get exchangeReasonDefault => 'Garment exchange (size / model)';
  @override
  String returnSuccessWithNumber(String number) =>
      'Return #$number processed successfully!';
  @override
  String exchangeSuccessWithDiff(String diff) =>
      'Exchange confirmed! Difference: $diff';

  // --- Labels ---
  @override
  String get labelStudioTitle => 'Barcode Label Studio';
  @override
  String get selectProductForLabel => 'Select an item for label preview';
  @override
  String get labelDimensions => 'Label Format (mm)';
  @override
  String get printCopies => 'Copies';
  @override
  String get printLabelsAction => 'Print Labels';
  @override
  String get labelsSentSuccess => 'Labels dispatched to printer';
  @override
  String get labelRollFormat => 'Label Roll Format (mm)';
  @override
  String get formatJewelryAccessories => '40 x 25 mm (Jewelry / Accessories)';
  @override
  String get formatStandardApparel => '40 x 30 mm (Standard Apparel)';
  @override
  String get formatLarge => '50 x 30 mm (Large Format)';
  @override
  String get formatCardboardTag => '60 x 40 mm (Hangtag / Cardboard)';
  @override
  String get byStockCount => 'By Stock';
  @override
  String nLabels(int count) => '$count label(s)';
  @override
  String get realThermalLabelPreview => 'Live Thermal Label Preview';
  @override
  String get selectArticleToPreview => 'Please select an item to preview label';
  @override
  String selectedFormat(int w, int h) => 'Selected Format: $w x $h mm';
  @override
  String labelsSentToPrinter(int count) =>
      '$count label(s) sent to TSPL/ZPL printer';
  @override
  String printError(String error) => 'Print Error: $error';

  // --- Shifts & Z-Report ---
  @override
  String get shiftManagementTitle => 'Register Shifts & Z-Report';
  @override
  String get activeShiftInfo => 'Active Register Shift';
  @override
  String get openedAt => 'Opened at';
  @override
  String get cashInDrawer => 'Theoretical Cash in Drawer';
  @override
  String get payInAction => 'Cash In (Deposit)';
  @override
  String get payOutAction => 'Cash Out (Expense)';
  @override
  String get payInTitle => 'Deposit Cash into Drawer';
  @override
  String get payOutTitle => 'Withdraw Cash from Drawer';
  @override
  String get reasonLabel => 'Reason / Purpose';
  @override
  String get closeRegisterTitle => 'Close Shift & Z-Report';
  @override
  String get countCashAction => 'Count & Close Register';
  @override
  String get countedCash => 'Actual Cash Counted';
  @override
  String get calculatedCash => 'Expected Cash';
  @override
  String get cashDifference => 'Drawer Discrepancy';
  @override
  String get printZReport => 'Print Z-Report';
  @override
  String get registerClosedSuccess =>
      'Shift closed successfully. Z-Report generated.';
  @override
  String get openRegisterShift => 'Open Register Shift';
  @override
  String get enterInitialCashFloat => 'Enter initial cash float (TND):';
  @override
  String get payInCash => 'Cash Pay-In (Change / Float)';
  @override
  String get payOutCash => 'Cash Pay-Out (Expense / Withdrawal)';
  @override
  String get amountTnd => 'Amount (TND)';
  @override
  String get reasonOrProof => 'Reason / Justification *';
  @override
  String get payInReasonExample => 'e.g. Coin change float';
  @override
  String get payOutReasonExample =>
      'e.g. Dry cleaning expense / Owner withdrawal';
  @override
  String get validateMovement => 'Confirm Cash Movement';
  @override
  String get standardShiftCloseNote => 'Standard shift closing';
  @override
  String get shiftClosedZReportSuccess =>
      'Register shift closed successfully (Z-Report generated)';
  @override
  String get refreshTotals => 'Refresh Totals';
  @override
  String get registerCurrentlyClosed => 'Register Currently Closed';
  @override
  String get registerTerminal => 'Terminal';
  @override
  String get openRegisterSessionAction => 'OPEN REGISTER SHIFT';
  @override
  String shiftOpenedAt(String time) => 'Shift opened at $time';
  @override
  String get cashSales => 'Cash Sales (+):';
  @override
  String get cardSales => 'Card Sales:';
  @override
  String get cashRefunds => 'Cash Refunds (-):';
  @override
  String get manualCashIn => 'Manual Cash In (+):';
  @override
  String get manualCashOut => 'Manual Cash Out (-):';
  @override
  String get expectedCashBalance => 'EXPECTED CASH IN DRAWER:';
  @override
  String get blindCountTitle => 'Physical Count & Closing (Z-Report)';
  @override
  String get enterCountedCashPrompt =>
      'Enter total cash physically counted in the drawer:';
  @override
  String get closeRegisterZReportAction => 'CLOSE REGISTER (Z-REPORT)';

  // --- Reports ---
  @override
  String get reportsTitle => 'Reports & Financial Analytics';
  @override
  String get salesAndMarginTab => 'Sales & Gross Margin';
  @override
  String get sizePerformanceTab => 'Size Performance';
  @override
  String get stockValuationTab => 'Stock Valuation';
  @override
  String get periodToday => 'Today';
  @override
  String get periodWeek => 'Past 7 Days';
  @override
  String get periodMonth => 'Past 30 Days';
  @override
  String get totalSales => 'Gross Revenue';
  @override
  String get grossMargin => 'Realized Gross Margin';
  @override
  String get marginRate => 'Margin Rate';
  @override
  String get totalTransactions => 'Total Transactions';
  @override
  String get averageBasket => 'Average Basket';
  @override
  String get totalCostValue => 'Inventory at Cost';
  @override
  String get totalRetailValue => 'Inventory at Retail';
  @override
  String get potentialProfit => 'Potential Gross Profit';
  @override
  String get analysisPeriod => 'Analysis Period:';
  @override
  String get netSalesRevenue => 'Net Sales Revenue';
  @override
  String get purchaseCostGoods => 'Goods Purchase Cost';
  @override
  String get financialDetailPeriod => 'Period Financial Detail';
  @override
  String get totalCompletedSalesCount => 'Total Completed Sales';
  @override
  String get grantedDiscounts => 'Discounts Given (-)';
  @override
  String get refundsAndReturns => 'Refunds & Returns (-)';
  @override
  String get actualNetSales => 'Actual Net Revenue';
  @override
  String get costOfGoodsSold => 'Cost of Goods Sold (COGS)';
  @override
  String get netGrossProfit => 'Net Gross Profit';
  @override
  String get paymentMethodBreakdown => 'Payment Method Breakdown';
  @override
  String get noPaymentsInPeriod => 'No payments during this period';
  @override
  String get noSalesForSizeAnalysis =>
      'No sales recorded during this period to analyze sizes';
  @override
  String get salesByGarmentSize => 'Sales by Garment Size';
  @override
  String get sizeDemandInsight =>
      'Identify top-selling sizes to optimize restock orders:';
  @override
  String nPieces(int count) => '$count pcs';
  @override
  String get lowStockAlertsCount => 'Low Stock Alerts (≤ 2)';
  @override
  String get outOfStockArticlesCount => 'Out of Stock Items (0)';
  @override
  String get totalUnitsInStock => 'Total Units in Stock';

  // --- Settings ---
  @override
  String get settingsTitle => 'Settings & Configuration';
  @override
  String get tabGeneral => 'GENERAL & LANGUAGE';
  @override
  String get tabHardware => 'POS HARDWARE';
  @override
  String get tabBackup => 'BACKUP & INTEGRITY';
  @override
  String get tabImportExport => 'CSV IMPORT / EXPORT';
  @override
  String get languageSection => 'Application Language';
  @override
  String get selectLanguage => 'Select display language';
  @override
  String get languageFr => 'Français (French)';
  @override
  String get languageAr => 'العربية (Arabic RTL)';
  @override
  String get languageEn => 'English';
  @override
  String get storeSection => 'Store Information';
  @override
  String get companyName => 'Company Legal Name';
  @override
  String get storeName => 'Store / Outlet Name';
  @override
  String get fiscalId => 'Tax / VAT Identification #';
  @override
  String get phone => 'Phone Number';
  @override
  String get address => 'Address';
  @override
  String get printerThermal => 'Thermal Receipt Printer (ESC/POS)';
  @override
  String get printerLabel => 'Barcode Label Printer (TSPL / ZPL)';
  @override
  String get customerDisplay => 'Customer Display (VFD / LCD)';
  @override
  String get testPrinter => 'Print Test Receipt';
  @override
  String get testLabelPrinter => 'Print Test Label';
  @override
  String get testCustomerDisplay => 'Test Customer Display';
  @override
  String get testCashDrawer => 'Open Cash Drawer';
  @override
  String get backupDatabase => 'Create Atomic SQLite Backup';
  @override
  String get databaseIntegrity => 'Database Integrity Diagnostic';
  @override
  String get runDiagnostics => 'Run Diagnostic';
  @override
  String get backupSuccess => 'Atomic SQLite backup created successfully!';
  @override
  String get diagnosticsPass =>
      'Database integrity verified. No errors detected.';
  @override
  String get importCsv => 'Import Catalog (CSV)';
  @override
  String get exportCsv => 'Export Catalog (CSV)';

  // --- Auth & Access ---
  @override
  String get loginTitle => 'Register Login';
  @override
  String get selectUser => 'Select your user account';
  @override
  String get enterPin => 'Enter 4-digit security PIN';
  @override
  String get invalidPin => 'Incorrect security PIN';
  @override
  String get screenLocked => 'Session Locked';
  @override
  String get unlockAction => 'Unlock';
  @override
  String get managerOverrideTitle => 'Manager Authorization Required';
  @override
  String get managerOverrideReason =>
      'This action requires Manager or Owner approval';
  @override
  String get authorizeAction => 'Authorize';
  @override
  String get welcomeTitle => 'Welcome to JazzPOS';
  @override
  String get noUsersConfigured =>
      'No accounts configured. Launch the initial setup wizard.';
  @override
  String get launchSetupWizard => 'Launch Setup';
  @override
  String get posAppSubtitle => 'Fashion & Apparel Point of Sale System';
  @override
  String get setupWizardButton => 'Setup Wizard / Add User';
  @override
  String pinForUser(String name) => 'PIN Code for $name';
  @override
  String get selectUserRequired => 'Please select a user';
  @override
  String get enterPinRequired => 'Please enter your PIN';
  @override
  String get loginAction => 'LOGIN';
  @override
  String activeSession(String name, String role) =>
      'Active session: $name ($role)';
  @override
  String get switchCashier => 'Switch Cashier';
  @override
  String get managerEmergencyUnlock => 'Manager Unlock';
  @override
  String get managerOverrideUnlockTitle => 'Emergency Register Unlock';
  @override
  String get managerPinInvalid => 'Invalid manager PIN code';
  @override
  String get selectVariantSubtitle => 'Select size and color';
  @override
  String unitsInStock(int count) => '$count in stock';
  @override
  String get receiptPreviewTitle => 'Receipt Preview';
  @override
  String get receiptPreviewDuplicate => 'Receipt Preview (Duplicate)';
  @override
  String get receiptPrintSuccess => 'Receipt sent to printer successfully';
  @override
  String receiptPrintError(String error) => 'Print error: $error';
  @override
  String get reprintAction => 'Reprint';
  @override
  String get printingInProgress => 'Printing...';

  // --- Formatting Helpers ---
  @override
  String get currencySymbol => 'TND';

  @override
  String categoryName(String rawName) {
    switch (rawName.trim().toLowerCase()) {
      case 'hauts & chemises':
      case 'tops & shirts':
      case 'قمصان وبلوزات':
        return 'Tops & Shirts';
      case 'pantalons & jeans':
      case 'pants & jeans':
      case 'سراويل وجينز':
        return 'Pants & Jeans';
      case 'robes & ensembles':
      case 'dresses & sets':
      case 'فساتين وأطقم':
        return 'Dresses & Sets';
      case 'vestes & manteaux':
      case 'jackets & coats':
      case 'سترات ومعاطف':
        return 'Jackets & Coats';
      case 'accessoires':
      case 'accessories':
      case 'إكسسوارات':
        return 'Accessories';
      case 'chaussures':
      case 'shoes':
      case 'أحذية':
        return 'Shoes';
      case 'hommes':
      case 'men':
      case 'رجال':
        return 'Men';
      case 'femmes':
      case 'women':
      case 'نساء':
        return 'Women';
      case 'enfants':
      case 'children':
      case 'أطفال':
        return 'Children';
      default:
        return rawName;
    }
  }

  @override
  String formatCurrency(double amount) => '${amount.toStringAsFixed(3)} TND';
  @override
  String formatStock(int count) => '$count pc${count == 1 ? '' : 's'}';
}
