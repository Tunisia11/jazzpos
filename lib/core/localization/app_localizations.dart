import 'package:flutter/widgets.dart';

abstract class AppLocalizations {
  static AppLocalizations of(BuildContext context) {
    final loc = Localizations.of<AppLocalizations>(context, AppLocalizations);
    if (loc == null) {
      throw FlutterError(
        'AppLocalizations not found in context. Make sure AppLocalizations.delegate is in localizationsDelegates.',
      );
    }
    return loc;
  }

  static const List<Locale> supportedLocales = [
    Locale('fr'),
    Locale('ar'),
    Locale('en'),
  ];

  Locale get locale;
  bool get isRtl => locale.languageCode == 'ar';
  TextDirection get textDirection =>
      isRtl ? TextDirection.rtl : TextDirection.ltr;

  // --- Common & Actions ---
  String get appTitle;
  String get appSubtitle;
  String get back;
  String get cancel;
  String get save;
  String get delete;
  String get archive;
  String get edit;
  String get add;
  String get close;
  String get confirm;
  String get refresh;
  String get search;
  String get filter;
  String get all;
  String get none;
  String get actions;
  String get status;
  String get reference;
  String get type;
  String get date;
  String get time;
  String get quantity;
  String get price;
  String get costPrice;
  String get sellingPrice;
  String get total;
  String get subtotal;
  String get discount;
  String get barcode;
  String get sku;
  String get category;
  String get notes;
  String get print;
  String get export;
  String get importAction;
  String get success;
  String get error;
  String get warning;
  String get info;
  String get loading;
  String get processing;
  String get yes;
  String get no;
  String get requiredField;
  String get invalidValue;
  String get duplicateSku;
  String get duplicateBarcode;

  // --- Navigation & Shell ---
  String get navPos;
  String get navCatalog;
  String get navInventory;
  String get navPurchasing;
  String get navReturns;
  String get navLabels;
  String get navShifts;
  String get navReports;
  String get navSettings;
  String get collapseMenu;
  String get expandMenu;
  String get lockRegister;
  String get logoutSession;
  String get roleOwner;
  String get roleManager;
  String get roleCashier;
  String get roleInventory;

  // --- POS / Checkout ---
  String get register;
  String get registerOpen;
  String get registerClosed;
  String get clickToOpenRegister;
  String get openRegisterTitle;
  String get initialCashFloat;
  String get openRegisterAction;
  String get suspendedSales;
  String get openCashDrawer;
  String get drawerKickSuccess;
  String get searchProductOrBarcode;
  String get allCategories;
  String get cart;
  String get cartEmpty;
  String get cartEmptySubtitle;
  String get clearCart;
  String get clearCartConfirm;
  String get holdSale;
  String get holdSaleSuccess;
  String get resumeSale;
  String get payAction;
  String get paymentTitle;
  String get paymentMethod;
  String get paymentCash;
  String get paymentCard;
  String get paymentSplit;
  String get paymentCheck;
  String get tenderedAmount;
  String get changeDue;
  String get exactAmount;
  String get completeSale;
  String get saleSuccess;
  String get printReceipt;
  String get receiptPreview;
  String get barcodeScannedSuccess;
  String get barcodeNotFound;
  String nArticles(int count);
  String itemsInCart(int count);
  String get quickBills;
  String get validatePayment;
  String get insufficientAmount;
  String get invalidSplit;
  String get noActiveShift;
  String get invalidUserSession;
  String get noSuspendedSales;
  String get resumeThisSale;
  String get replaceCart;
  String get cartNotEmptyTitle;
  String get cartNotEmptyBody;
  String get deleteSuspendedSaleTitle;
  String deleteSuspendedSaleBody(String name);
  String get unnamedSale;

  // --- Catalog & Products ---
  String get productsTitle;
  String get newProduct;
  String get editProduct;
  String get deleteProduct;
  String get productName;
  String get variantDescription;
  String get size;
  String get color;
  String get minStockAlert;
  String get currentStock;
  String get stock;
  String get activeProducts;
  String get archivedProducts;
  String get archiveProductConfirm;
  String get deleteProductConfirmTitle;
  String get deleteProductConfirmBody;
  String get productSavedSuccess;
  String get productArchivedSuccess;
  String get productDeletedSuccess;
  String get addOrEditPhoto;
  String get chooseImage;
  String get removePhoto;
  String get photoUpdatedSuccess;
  String get noImage;
  String get matrixGenerator;
  String get generateVariants;
  String get selectSizes;
  String get selectColors;
  String get bulkPrice;
  String get bulkStock;
  String get active;
  String get initialStock;
  String get generalInfo;
  String get secondaryName;
  String get skuPrefix;
  String get defaultCost;
  String get defaultPrice;
  String get taxRate;
  String get noProductsFound;
  String get createFirstProduct;
  String get atLeastOneVariant;

  // --- Stocks & Inventory ---
  String get stockLevelsTitle;
  String get stockByArticle;
  String get stockTransfer;
  String get inStock;
  String get lowStock;
  String get outOfStock;
  String get negativeStock;
  String get manualStockAuditWarning;
  String get stockAdjustmentReason;
  String get stockCountTitle;
  String get initiateCount;
  String get scanOrTypeBarcode;
  String get countedQty;
  String get expectedQty;
  String get varianceQty;
  String get totalPiecesCounted;
  String get itemsWithVariance;
  String get varianceValue;
  String get validateAndApplyAudit;
  String get countCompletedSuccess;
  String get stockMovementsHistory;
  String get startInventory;
  String get noMovementsRecorded;
  String get sourceLocation;
  String get destinationLocation;
  String get transferQuantity;
  String get transferReason;
  String get atLeastTwoLocationsRequired;
  String get manual;
  String get transferSuccessful;
  String get productActions;
  String get deleteProductPrompt;
  String get protectedHistoryNote;
  String get filterArticlesPrompt;
  String get noArticlesFoundInInventory;

  // --- Purchasing & Receiving ---
  String get purchaseOrdersTitle;
  String get goodsReceivingTitle;
  String get newPurchaseOrder;
  String get supplier;
  String get orderReference;
  String get expectedDelivery;
  String get receiveGoods;
  String get receivingCompleted;
  String get noOrdersRecorded;
  String get registerSupplierReceipt;
  String get invoiceOrDeliveryNote;
  String get addArticles;
  String get qtyReceived;
  String get qtyDamaged;
  String get validateReceiving;
  String get noArticlesInReceiving;
  String get selectSupplierPrompt;
  String get addAtLeastOneArticlePrompt;
  String get receivingSavedSuccess;

  // --- Returns & Exchanges ---
  String get returnsExchangesTitle;
  String get searchReceiptPrompt;
  String get returnMode;
  String get exchangeMode;
  String get returnConditionSellable;
  String get returnConditionDamaged;
  String get returnReason;
  String get replacementItem;
  String get refundDueCustomer;
  String get customerOwes;
  String get netDifferenceZero;
  String get completeReturnAction;
  String get completeExchangeAction;
  String get returnSuccess;
  String get exchangeSuccess;
  String get openRegisterSessionFirst;
  String get selectArticleToReturnPrompt;
  String get selectReplacementArticlePrompt;
  String get searchReceipt;
  String ticketNotFound(String receipt);
  String get purchasedItemsToReturn;
  String get refundDetails;
  String get amountToRefund;
  String get refundMethod;
  String get paymentStoreCredit;
  String get searchTicketPlaceholder;
  String get priceDifference;
  String get selectNewReplacementArticle;
  String get returnReasonSize;
  String get returnReasonDefault;
  String get exchangeReasonDefault;
  String returnSuccessWithNumber(String number);
  String exchangeSuccessWithDiff(String diff);

  // --- Labels ---
  String get labelStudioTitle;
  String get selectProductForLabel;
  String get labelDimensions;
  String get printCopies;
  String get printLabelsAction;
  String get labelsSentSuccess;
  String get labelRollFormat;
  String get formatJewelryAccessories;
  String get formatStandardApparel;
  String get formatLarge;
  String get formatCardboardTag;
  String get byStockCount;
  String nLabels(int count);
  String get realThermalLabelPreview;
  String get selectArticleToPreview;
  String selectedFormat(int w, int h);
  String labelsSentToPrinter(int count);
  String printError(String error);

  // --- Shifts & Z-Report ---
  String get shiftManagementTitle;
  String get activeShiftInfo;
  String get openedAt;
  String get cashInDrawer;
  String get payInAction;
  String get payOutAction;
  String get payInTitle;
  String get payOutTitle;
  String get reasonLabel;
  String get closeRegisterTitle;
  String get countCashAction;
  String get countedCash;
  String get calculatedCash;
  String get cashDifference;
  String get printZReport;
  String get registerClosedSuccess;
  String get openRegisterShift;
  String get enterInitialCashFloat;
  String get payInCash;
  String get payOutCash;
  String get amountTnd;
  String get reasonOrProof;
  String get payInReasonExample;
  String get payOutReasonExample;
  String get validateMovement;
  String get standardShiftCloseNote;
  String get shiftClosedZReportSuccess;
  String get refreshTotals;
  String get registerCurrentlyClosed;
  String get registerTerminal;
  String get openRegisterSessionAction;
  String shiftOpenedAt(String time);
  String get cashSales;
  String get cardSales;
  String get cashRefunds;
  String get manualCashIn;
  String get manualCashOut;
  String get expectedCashBalance;
  String get blindCountTitle;
  String get enterCountedCashPrompt;
  String get closeRegisterZReportAction;

  // --- Reports ---
  String get reportsTitle;
  String get salesAndMarginTab;
  String get sizePerformanceTab;
  String get stockValuationTab;
  String get periodToday;
  String get periodWeek;
  String get periodMonth;
  String get totalSales;
  String get grossMargin;
  String get marginRate;
  String get totalTransactions;
  String get averageBasket;
  String get totalCostValue;
  String get totalRetailValue;
  String get potentialProfit;
  String get analysisPeriod;
  String get netSalesRevenue;
  String get purchaseCostGoods;
  String get financialDetailPeriod;
  String get totalCompletedSalesCount;
  String get grantedDiscounts;
  String get refundsAndReturns;
  String get actualNetSales;
  String get costOfGoodsSold;
  String get netGrossProfit;
  String get paymentMethodBreakdown;
  String get noPaymentsInPeriod;
  String get noSalesForSizeAnalysis;
  String get salesByGarmentSize;
  String get sizeDemandInsight;
  String nPieces(int count);
  String get lowStockAlertsCount;
  String get outOfStockArticlesCount;
  String get totalUnitsInStock;

  // --- Settings ---
  String get settingsTitle;
  String get tabGeneral;
  String get tabHardware;
  String get tabBackup;
  String get tabImportExport;
  String get languageSection;
  String get selectLanguage;
  String get languageFr;
  String get languageAr;
  String get languageEn;
  String get storeSection;
  String get companyName;
  String get storeName;
  String get fiscalId;
  String get phone;
  String get address;
  String get printerThermal;
  String get printerLabel;
  String get customerDisplay;
  String get testPrinter;
  String get testLabelPrinter;
  String get testCustomerDisplay;
  String get testCashDrawer;
  String get backupDatabase;
  String get databaseIntegrity;
  String get runDiagnostics;
  String get backupSuccess;
  String get diagnosticsPass;
  String get importCsv;
  String get exportCsv;

  // --- Auth & Access ---
  String get loginTitle;
  String get selectUser;
  String get enterPin;
  String get invalidPin;
  String get screenLocked;
  String get unlockAction;
  String get managerOverrideTitle;
  String get managerOverrideReason;
  String get authorizeAction;
  String get welcomeTitle;
  String get noUsersConfigured;
  String get launchSetupWizard;
  String get posAppSubtitle;
  String get setupWizardButton;
  String pinForUser(String name);
  String get selectUserRequired;
  String get enterPinRequired;
  String get loginAction;
  String activeSession(String name, String role);
  String get switchCashier;
  String get managerEmergencyUnlock;
  String get managerOverrideUnlockTitle;
  String get managerPinInvalid;
  String get selectVariantSubtitle;
  String unitsInStock(int count);
  String get receiptPreviewTitle;
  String get receiptPreviewDuplicate;
  String get receiptPrintSuccess;
  String receiptPrintError(String error);
  String get reprintAction;
  String get printingInProgress;

  // --- Formatting Helpers ---
  String get currencySymbol;
  String categoryName(String rawName);
  String formatCurrency(double amount);
  String formatStock(int count);
}

extension LocalizationExtension on BuildContext {
  AppLocalizations get loc => AppLocalizations.of(this);
  bool get isRtl => Directionality.of(this) == TextDirection.rtl;
}
