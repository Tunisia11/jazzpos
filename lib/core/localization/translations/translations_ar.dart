import 'package:flutter/widgets.dart';
import '../app_localizations.dart';

class AppLocalizationsAr extends AppLocalizations {
  @override
  Locale get locale => const Locale('ar');

  // --- Common & Actions ---
  @override
  String get appTitle => 'جاز بوس';
  @override
  String get appSubtitle => 'نقطة البيع وإدارة متاجر الملابس';
  @override
  String get back => 'رجوع';
  @override
  String get cancel => 'إلغاء';
  @override
  String get save => 'حفظ';
  @override
  String get delete => 'حذف';
  @override
  String get archive => 'أرشفة';
  @override
  String get edit => 'تعديل';
  @override
  String get add => 'إضافة';
  @override
  String get close => 'إغلاق';
  @override
  String get confirm => 'تأكيد';
  @override
  String get refresh => 'تحديث';
  @override
  String get search => 'بحث';
  @override
  String get filter => 'تصفية';
  @override
  String get all => 'الكل';
  @override
  String get none => 'لا يوجد';
  @override
  String get actions => 'إجراءات';
  @override
  String get status => 'الحالة';
  @override
  String get reference => 'المرجع';
  @override
  String get type => 'النوع';
  @override
  String get date => 'التاريخ';
  @override
  String get time => 'الوقت';
  @override
  String get quantity => 'الكمية';
  @override
  String get price => 'السعر';
  @override
  String get costPrice => 'سعر التكلفة';
  @override
  String get sellingPrice => 'سعر البيع';
  @override
  String get total => 'المجموع الإجمالي';
  @override
  String get subtotal => 'المجموع الفرعي';
  @override
  String get discount => 'الخصم';
  @override
  String get barcode => 'الباركود';
  @override
  String get sku => 'رمز الصنف (SKU)';
  @override
  String get category => 'الفئة';
  @override
  String get notes => 'ملاحظات';
  @override
  String get print => 'طباعة';
  @override
  String get export => 'تصدير';
  @override
  String get importAction => 'استيراد';
  @override
  String get success => 'تم بنجاح';
  @override
  String get error => 'خطأ';
  @override
  String get warning => 'تنبيه';
  @override
  String get info => 'معلومات';
  @override
  String get loading => 'جاري التحميل...';
  @override
  String get processing => 'جاري التنفيذ...';
  @override
  String get yes => 'نعم';
  @override
  String get no => 'لا';
  @override
  String get requiredField => 'هذا الحقل إجباري';
  @override
  String get invalidValue => 'قيمة غير صالحة';
  @override
  String get duplicateSku => 'رمز الصنف (SKU) موجود مسبقاً';
  @override
  String get duplicateBarcode => 'هذا الباركود مستخدم لمنتج آخر بالفعل';

  // --- Navigation & Shell ---
  @override
  String get navPos => 'نقطة البيع (POS)';
  @override
  String get navCatalog => 'المنتجات والمقاسات';
  @override
  String get navInventory => 'المخزون والمستودع';
  @override
  String get navPurchasing => 'المشتريات والتوريد';
  @override
  String get navReturns => 'المرتجعات والتبديل';
  @override
  String get navLabels => 'طباعة الباركود';
  @override
  String get navShifts => 'إقفال الصندوق (Z)';
  @override
  String get navReports => 'التقارير المالية';
  @override
  String get navSettings => 'الإعدادات والأجهزة';
  @override
  String get collapseMenu => 'طي القائمة';
  @override
  String get expandMenu => 'توسيع القائمة';
  @override
  String get lockRegister => 'قفل الشاشة';
  @override
  String get logoutSession => 'تسجيل الخروج';
  @override
  String get roleOwner => 'المالك';
  @override
  String get roleManager => 'المدير';
  @override
  String get roleCashier => 'أمين الصندوق';
  @override
  String get roleInventory => 'مسؤول المخزن';

  // --- POS / Checkout ---
  @override
  String get register => 'الصندوق';
  @override
  String get registerOpen => 'الصندوق مفتوح';
  @override
  String get registerClosed => 'الصندوق مغلق';
  @override
  String get clickToOpenRegister => 'اضغط لفتح وردية الصندوق';
  @override
  String get openRegisterTitle => 'فتح وردية الصندوق';
  @override
  String get initialCashFloat => 'الرصيد الافتتاحي للصندوق (د.ت)';
  @override
  String get openRegisterAction => 'فتح الوردية';
  @override
  String get suspendedSales => 'الفواتير المعلقة (F6)';
  @override
  String get openCashDrawer => 'فتح الدرج (F10)';
  @override
  String get drawerKickSuccess => 'تم إرسال إشارة فتح الدرج بنجاح';
  @override
  String get searchProductOrBarcode => 'ابحث عن منتج أو امسح الباركود...';
  @override
  String get allCategories => 'جميع الأصناف';
  @override
  String get cart => 'سلة المشتريات';
  @override
  String get cartEmpty => 'السلة فارغة';
  @override
  String get cartEmptySubtitle =>
      'امسح الباركود أو اختر منتجاً من القائمة لإضافته.';
  @override
  String get clearCart => 'تفريغ السلة';
  @override
  String get clearCartConfirm =>
      'هل أنت متأكد من رغبتك في حذف جميع عناصر السلة؟';
  @override
  String get holdSale => 'تعليق الفاتورة (F6)';
  @override
  String get holdSaleSuccess => 'تم تعليق الفاتورة بنجاح';
  @override
  String get resumeSale => 'استئناف الفاتورة';
  @override
  String get payAction => 'دفع الحساب (F12)';
  @override
  String get paymentTitle => 'سداد الفاتورة';
  @override
  String get paymentMethod => 'طريقة الدفع';
  @override
  String get paymentCash => 'نقداً';
  @override
  String get paymentCard => 'بطاقة بنكية (TPE)';
  @override
  String get paymentSplit => 'دفع مشترك';
  @override
  String get paymentCheck => 'شيك';
  @override
  String get tenderedAmount => 'المبلغ المستلم';
  @override
  String get changeDue => 'الباقي للزبون';
  @override
  String get exactAmount => 'المبلغ بالتمام';
  @override
  String get completeSale => 'تأكيد البيع وطباعة الإيصال';
  @override
  String get saleSuccess => 'تم تسجيل عملية البيع بنجاح';
  @override
  String get printReceipt => 'طباعة الإيصال';
  @override
  String get receiptPreview => 'معاينة الإيصال';
  @override
  String get barcodeScannedSuccess => 'تمت إضافة المنتج';
  @override
  String get barcodeNotFound => 'لم يتم العثور على منتج بهذا الباركود';
  @override
  String nArticles(int count) =>
      '$count ${count > 2 && count < 11 ? 'منتجات' : 'منتج'}';
  @override
  String itemsInCart(int count) =>
      '$count ${count > 2 && count < 11 ? 'قطع' : 'قطعة'} في السلة';
  @override
  String get quickBills => 'أوراق نقدية سريعة:';
  @override
  String get validatePayment => 'تأكيد الدفع (Entrée)';
  @override
  String get insufficientAmount => 'المبلغ المدفوع غير كافٍ';
  @override
  String get invalidSplit => 'تقسيم الدفع غير صالح';
  @override
  String get noActiveShift => 'لا توجد جلسة صندوق مفتوحة!';
  @override
  String get invalidUserSession => 'جلسة المستخدم غير صالحة';
  @override
  String get noSuspendedSales => 'لا توجد مبيعات معلقة';
  @override
  String get resumeThisSale => 'استئناف هذا البيع';
  @override
  String get replaceCart => 'استبدال السلة';
  @override
  String get cartNotEmptyTitle => 'السلة الحالية غير فارغة';
  @override
  String get cartNotEmptyBody =>
      'تحتوي السلة الحالية على عناصر. سيؤدي استئناف هذا البيع إلى استبدال السلة الحالية. هل ترغب بالمتابعة؟';
  @override
  String get deleteSuspendedSaleTitle => 'حذف البيع المعلق';
  @override
  String deleteSuspendedSaleBody(String name) =>
      'هل أنت متأكد من رغبتك في حذف "$name" نهائياً؟';
  @override
  String get unnamedSale => 'بيع بدون اسم';

  // --- Catalog & Products ---
  @override
  String get productsTitle => 'دليل المنتجات والأصناف';
  @override
  String get newProduct => 'منتج جديد';
  @override
  String get editProduct => 'تعديل المنتج';
  @override
  String get deleteProduct => 'حذف المنتج';
  @override
  String get productName => 'اسم المنتج';
  @override
  String get variantDescription => 'المقاس / اللون';
  @override
  String get size => 'المقاس';
  @override
  String get color => 'اللون';
  @override
  String get minStockAlert => 'حد التنبيه بنقص المخزون';
  @override
  String get currentStock => 'الكمية الحالية';
  @override
  String get stock => 'المخزون';
  @override
  String get activeProducts => 'المنتجات النشطة';
  @override
  String get archivedProducts => 'المنتجات المؤرشفة';
  @override
  String get archiveProductConfirm =>
      'هل تريد أرشفة هذا المنتج؟ لن يظهر في نقطة البيع مجدداً.';
  @override
  String get deleteProductConfirmTitle => 'حذف هذا المنتج؟';
  @override
  String get deleteProductConfirmBody =>
      'سيتم إخفاء المنتج من المخزون النشط ونقطة البيع مع الحفاظ التام على سجل المبيعات والبيانات المحاسبية السابقة.';
  @override
  String get productSavedSuccess => 'تم حفظ المنتج بنجاح';
  @override
  String get productArchivedSuccess => 'تم أرشفة المنتج بنجاح';
  @override
  String get productDeletedSuccess => 'تم حذف المنتج بنجاح';
  @override
  String get addOrEditPhoto => 'إضافة / تعديل الصورة';
  @override
  String get chooseImage => 'اختيار صورة';
  @override
  String get removePhoto => 'إزالة الصورة';
  @override
  String get photoUpdatedSuccess => 'تم تحديث صورة المنتج بنجاح';
  @override
  String get noImage => 'بدون صورة';
  @override
  String get matrixGenerator =>
      'منشئ مصفوفة المقاسات والألوان (الملابس الجاهزة)';
  @override
  String get generateVariants => 'توليد الأصناف المتغيرة';
  @override
  String get selectSizes => '١. اختر المقاسات:';
  @override
  String get selectColors => '٢. اختر الألوان:';
  @override
  String get bulkPrice => 'تطبيق السعر للكل';
  @override
  String get bulkStock => 'تطبيق المخزون الأولي للكل';
  @override
  String get active => 'نشط';
  @override
  String get initialStock => 'المخزون الأولي';
  @override
  String get generalInfo => 'المعلومات العامة للمنتج';
  @override
  String get secondaryName => 'الاسم الثانوي / بالعربية (اختياري)';
  @override
  String get skuPrefix => 'رمز أو بادئة SKU';
  @override
  String get defaultCost => 'سعر الشراء الافتراضي (د.ت)';
  @override
  String get defaultPrice => 'سعر البيع الافتراضي (د.ت)';
  @override
  String get taxRate => 'نسبة الأداء على القيمة المضافة';
  @override
  String get noProductsFound => 'لم يتم العثور على أي منتج في الدليل';
  @override
  String get createFirstProduct => 'إنشاء أول منتج';
  @override
  String get atLeastOneVariant =>
      'يرجى توليد صنف نشط واحد على الأقل لهذا المنتج';

  // --- Stocks & Inventory ---
  @override
  String get stockLevelsTitle => 'مستويات المخزون حسب الصنف';
  @override
  String get stockByArticle => 'المخزون المتوفر';
  @override
  String get stockTransfer => 'تحويل مخزني';
  @override
  String get inStock => 'متوفر';
  @override
  String get lowStock => 'مخزون منخفض';
  @override
  String get outOfStock => 'نفد المخزون';
  @override
  String get negativeStock => 'مخزون سالب';
  @override
  String get manualStockAuditWarning =>
      'تعديل الكمية يدوياً سيقوم بضبط المخزون الفعلي وتسجيل حركة مخزنية رسمية مع التتبع والتدقيق.';
  @override
  String get stockAdjustmentReason => 'تعديل يدوي مباشر من بطاقة المنتج';
  @override
  String get stockCountTitle => 'الجرد الفعلي والتدقيق';
  @override
  String get initiateCount => 'بدء جلسة جرد جديدة';
  @override
  String get scanOrTypeBarcode => 'امسح الباركود أو أدخل الرمز يدوياً...';
  @override
  String get countedQty => 'الكمية المحصورة';
  @override
  String get expectedQty => 'الكمية الدفترية';
  @override
  String get varianceQty => 'الفارق';
  @override
  String get totalPiecesCounted => 'إجمالي القطع المحصورة';
  @override
  String get itemsWithVariance => 'المنتجات ذات الفوارق';
  @override
  String get varianceValue => 'قيمة الفارق';
  @override
  String get validateAndApplyAudit => 'اعتماد وتطبيق الفروقات';
  @override
  String get countCompletedSuccess => 'تم إتمام وتثبيت عملية الجرد بنجاح';
  @override
  String get stockMovementsHistory => 'سجل حركات المخزون (تدقيق)';
  @override
  String get startInventory => 'بدء جرد المخزون';
  @override
  String get noMovementsRecorded => 'لا توجد حركات مخزون مسجلة';
  @override
  String get sourceLocation => 'موقع المصدر';
  @override
  String get destinationLocation => 'موقع الوجهة';
  @override
  String get transferQuantity => 'الكمية المراد تحويلها';
  @override
  String get transferReason => 'سبب التحويل';
  @override
  String get atLeastTwoLocationsRequired => 'يلزم وجود موقعي مخزون على الأقل';
  @override
  String get manual => 'يدوي';
  @override
  String get transferSuccessful => 'تم تحويل المخزون بنجاح!';
  @override
  String get productActions => 'إجراءات المنتج';
  @override
  String get deleteProductPrompt =>
      'سيؤدي هذا الإجراء إلى حذف المنتج من الدليل.';
  @override
  String get protectedHistoryNote =>
      'ملاحظة: تظل سجلات المبيعات والمعاملات وحركات المخزون السابقة محفوظة ومحمية بالكامل.';
  @override
  String get filterArticlesPrompt =>
      'تصفية المنتجات بالاسم أو رمز SKU أو الباركود...';
  @override
  String get noArticlesFoundInInventory =>
      'لم يتم العثور على أي منتج في المخزون';

  // --- Purchasing & Receiving ---
  @override
  String get purchaseOrdersTitle => 'أوامر الشراء والموردين';
  @override
  String get goodsReceivingTitle => 'استلام وتوريد البضاعة';
  @override
  String get newPurchaseOrder => 'طلب شراء جديد';
  @override
  String get supplier => 'المورد';
  @override
  String get orderReference => 'رقم الطلب';
  @override
  String get expectedDelivery => 'تاريخ الوصول المتوقع';
  @override
  String get receiveGoods => 'استلام الشحنة';
  @override
  String get receivingCompleted => 'تم تسجيل استلام الشحنة بنجاح';
  @override
  String get noOrdersRecorded => 'لا توجد أوامر شراء أو استلامات مسجلة';
  @override
  String get registerSupplierReceipt => 'تسجيل استلام بضاعة من مورد';
  @override
  String get invoiceOrDeliveryNote => 'رقم وصل التسليم / الفاتورة';
  @override
  String get addArticles => 'إضافة منتجات';
  @override
  String get qtyReceived => 'الكمية المستلمة';
  @override
  String get qtyDamaged => 'تالف / معيب';
  @override
  String get validateReceiving => 'اعتماد وتثبيت الاستلام';
  @override
  String get noArticlesInReceiving =>
      'لا توجد منتجات في هذا الاستلام.\nاختر أو امسح المنتجات من القائمة يميناً.';
  @override
  String get selectSupplierPrompt => 'يرجى اختيار المورد أولاً';
  @override
  String get addAtLeastOneArticlePrompt => 'يرجى إضافة منتج واحد على الأقل';
  @override
  String get receivingSavedSuccess =>
      'تم تسجيل استلام البضاعة وتحديث المخزون بنجاح!';

  // --- Returns & Exchanges ---
  @override
  String get returnsExchangesTitle => 'المرتجعات واستبدال الملابس';
  @override
  String get searchReceiptPrompt =>
      'أدخل رقم الإيصال أو امسح الباركود الخاص به...';
  @override
  String get returnMode => 'إرجاع عادي (استرداد نقدي)';
  @override
  String get exchangeMode => 'استبدال مقاس / صنف';
  @override
  String get returnConditionSellable => 'سليم وقابل لإعادة البيع';
  @override
  String get returnConditionDamaged => 'تالف / به عيب مصنعي';
  @override
  String get returnReason => 'سبب الإرجاع';
  @override
  String get replacementItem => 'المنتج البديل';
  @override
  String get refundDueCustomer => 'المبلغ المستحق إرجاعه للزبون';
  @override
  String get customerOwes => 'المبلغ المتبقي على الزبون دفعه';
  @override
  String get netDifferenceZero => 'تبديل متطابق القيمة (الفارق 0.000 د.ت)';
  @override
  String get completeReturnAction => 'تأكيد عملية الإرجاع';
  @override
  String get completeExchangeAction => 'تأكيد عملية الاستبدال';
  @override
  String get returnSuccess => 'تم تسجيل عملية الإرجاع بنجاح';
  @override
  String get exchangeSuccess => 'تمت عملية الاستبدال بنجاح';
  @override
  String get openRegisterSessionFirst => 'يرجى أولاً فتح جلسة كاشير نشطة';
  @override
  String get selectArticleToReturnPrompt =>
      'يرجى تحديد عنصر واحد على الأقل للإرجاع';
  @override
  String get selectReplacementArticlePrompt => 'يرجى تحديد المنتج البديل';
  @override
  String get searchReceipt => 'بحث عن الإيصال';
  @override
  String ticketNotFound(String receipt) =>
      'لم يتم العثور على إيصال بالرقم "$receipt"';
  @override
  String get purchasedItemsToReturn => 'المنتجات المشتراة المراد إرجاعها:';
  @override
  String get refundDetails => 'تفاصيل الاسترداد النقدي';
  @override
  String get amountToRefund => 'المبلغ المستحق إرجاعه:';
  @override
  String get refundMethod => 'طريقة الإرجاع:';
  @override
  String get paymentStoreCredit => 'رصيد متجر';
  @override
  String get searchTicketPlaceholder =>
      'أدخل رقم الإيصال أو امسح باركود وصل الشراء';
  @override
  String get priceDifference => 'فارق السعر:';
  @override
  String get selectNewReplacementArticle => 'اختر المنتج البديل الجديد:';
  @override
  String get returnReasonSize => 'المقاس غير مناسب';
  @override
  String get returnReasonDefault => 'إرجاع صنف';
  @override
  String get exchangeReasonDefault => 'استبدال ملابس (مقاس / موديل)';
  @override
  String returnSuccessWithNumber(String number) =>
      'تم تأكيد الإرجاع رقم #$number بنجاح!';
  @override
  String exchangeSuccessWithDiff(String diff) =>
      'تم تأكيد الاستبدال! الفارق: $diff';

  // --- Labels ---
  @override
  String get labelStudioTitle => 'استوديو طباعة الباركود';
  @override
  String get selectProductForLabel => 'اختر منتجاً لتصميم الملصق';
  @override
  String get labelDimensions => 'مقاس الملصق (مم)';
  @override
  String get printCopies => 'عدد النسخ';
  @override
  String get printLabelsAction => 'طباعة الملصقات';
  @override
  String get labelsSentSuccess => 'تم إرسال الملصقات إلى الطابعة بنجاح';
  @override
  String get labelRollFormat => 'مقاس بكرة الملصقات (مم)';
  @override
  String get formatJewelryAccessories => '40 x 25 مم (إكسسوارات ومجوهرات)';
  @override
  String get formatStandardApparel => '40 x 30 مم (ملابس قياسي)';
  @override
  String get formatLarge => '50 x 30 مم (مقاس كبير)';
  @override
  String get formatCardboardTag => '60 x 40 مم (بطاقات كرتونية)';
  @override
  String get byStockCount => 'حسب المخزون';
  @override
  String nLabels(int count) => '$count ملصق(ات)';
  @override
  String get realThermalLabelPreview => 'معاينة حية للملصق الحراري';
  @override
  String get selectArticleToPreview => 'يرجى تحديد منتج لمعاينة ملصقه';
  @override
  String selectedFormat(int w, int h) => 'المقاس المحدد: $w x $h مم';
  @override
  String labelsSentToPrinter(int count) =>
      'تم إرسال $count ملصق(ات) لطابعة TSPL/ZPL';
  @override
  String printError(String error) => 'خطأ في الطباعة: $error';

  // --- Shifts & Z-Report ---
  @override
  String get shiftManagementTitle => 'إدارة الصندوق والتقرير اليومي (Z)';
  @override
  String get activeShiftInfo => 'الوردية الحالية المفتوحة';
  @override
  String get openedAt => 'فُتحت في';
  @override
  String get cashInDrawer => 'النقد المتوقع داخل الدرج';
  @override
  String get payInAction => 'إيداع نقدي بالصندوق';
  @override
  String get payOutAction => 'سحب نقدي (مصروفات)';
  @override
  String get payInTitle => 'إيداع مبالغ نقدية بالصندوق';
  @override
  String get payOutTitle => 'سحب مبالغ نقدية من الصندوق';
  @override
  String get reasonLabel => 'السبب / البيان';
  @override
  String get closeRegisterTitle => 'إغلاق الوردية والتقرير النهائي (Z)';
  @override
  String get countCashAction => 'جرد النقد وإغلاق الصندوق';
  @override
  String get countedCash => 'المبلغ الفعلي المحصي';
  @override
  String get calculatedCash => 'المبلغ المتوقع بالنظام';
  @override
  String get cashDifference => 'عجز / زيادة الصندوق';
  @override
  String get printZReport => 'طباعة تقرير Z';
  @override
  String get registerClosedSuccess => 'تم إغلاق الوردية وتوليد التقرير بنجاح';
  @override
  String get openRegisterShift => 'فتح جلسة كاشير جديدة';
  @override
  String get enterInitialCashFloat => 'أدخل العهدة النقدية الابتدائية (د.ت):';
  @override
  String get payInCash => 'إيداع نقدي (فكة / تعزيز)';
  @override
  String get payOutCash => 'سحب نقدي (مصاريف / استقطاع)';
  @override
  String get amountTnd => 'المبلغ (د.ت)';
  @override
  String get reasonOrProof => 'السبب / المبرر *';
  @override
  String get payInReasonExample => 'مثال: فكة نقدية معدنية';
  @override
  String get payOutReasonExample => 'مثال: مصاريف غسيل / سحب المدير';
  @override
  String get validateMovement => 'تأكيد حركة النقد';
  @override
  String get standardShiftCloseNote => 'إغلاق وردية عادي';
  @override
  String get shiftClosedZReportSuccess =>
      'تم إغلاق الوردية وتوليد التقرير Z بنجاح';
  @override
  String get refreshTotals => 'تحديث الإجماليات';
  @override
  String get registerCurrentlyClosed => 'الصندوق مغلق حالياً';
  @override
  String get registerTerminal => 'النقطة';
  @override
  String get openRegisterSessionAction => 'فتح جلسة الكاشير';
  @override
  String shiftOpenedAt(String time) => 'فُتحت الوردية في $time';
  @override
  String get cashSales => 'المبيعات النقدية (+):';
  @override
  String get cardSales => 'مبيعات البطاقة البنكية:';
  @override
  String get cashRefunds => 'المبالغ المستردة نقداً (-):';
  @override
  String get manualCashIn => 'إيداعات نقدية يدوية (+):';
  @override
  String get manualCashOut => 'سحوبات نقدية يدوية (-):';
  @override
  String get expectedCashBalance => 'الرصيد النقدي المتوقع بالدرج:';
  @override
  String get blindCountTitle => 'الجرد الفعلي والإغلاق (تقرير Z)';
  @override
  String get enterCountedCashPrompt =>
      'أدخل إجمالي النقد المعدود فعلياً في الدرج:';
  @override
  String get closeRegisterZReportAction => 'إغلاق الوردية (تقرير Z)';

  // --- Reports ---
  @override
  String get reportsTitle => 'التقارير والإحصائيات المالية';
  @override
  String get salesAndMarginTab => 'المبيعات وهامش الربح';
  @override
  String get sizePerformanceTab => 'أداء المقاسات الأكثر مبيعاً';
  @override
  String get stockValuationTab => 'تقييم قيمة المخزون';
  @override
  String get periodToday => 'اليوم';
  @override
  String get periodWeek => 'آخر 7 أيام';
  @override
  String get periodMonth => 'آخر 30 يوماً';
  @override
  String get totalSales => 'إجمالي الإيرادات';
  @override
  String get grossMargin => 'هامش الربح الإجمالي';
  @override
  String get marginRate => 'نسبة الهامش';
  @override
  String get totalTransactions => 'عدد العمليات';
  @override
  String get averageBasket => 'متوسط قيمة السلة';
  @override
  String get totalCostValue => 'قيمة المخزون بالتكلفة';
  @override
  String get totalRetailValue => 'قيمة المخزون بسعر البيع';
  @override
  String get potentialProfit => 'الربح الإجمالي المتوقع';
  @override
  String get analysisPeriod => 'فترة التحليل:';
  @override
  String get netSalesRevenue => 'صافي الإيرادات';
  @override
  String get purchaseCostGoods => 'تكلفة شراء البضائع';
  @override
  String get financialDetailPeriod => 'التفاصيل المالية للفترة';
  @override
  String get totalCompletedSalesCount => 'إجمالي المبيعات المكتملة';
  @override
  String get grantedDiscounts => 'الخصومات الممنوحة (-)';
  @override
  String get refundsAndReturns => 'المرتجعات والمستردات (-)';
  @override
  String get actualNetSales => 'صافي الإيرادات الفعلي';
  @override
  String get costOfGoodsSold => 'تكلفة البضاعة المباعة (COGS)';
  @override
  String get netGrossProfit => 'صافي الربح الإجمالي';
  @override
  String get paymentMethodBreakdown => 'التوزيع حسب طرق الدفع';
  @override
  String get noPaymentsInPeriod => 'لا توجد مدفوعات خلال هذه الفترة';
  @override
  String get noSalesForSizeAnalysis =>
      'لا توجد مبيعات مسجلة في هذه الفترة لتحليل المقاسات';
  @override
  String get salesByGarmentSize => 'المبيعات حسب مقاسات الملابس';
  @override
  String get sizeDemandInsight =>
      'حدد المقاسات الأكثر طلباً لتحسين خطة إعادة التموين:';
  @override
  String nPieces(int count) => '$count قطعة';
  @override
  String get lowStockAlertsCount => 'تنبيهات المخزون المنخفض (≤ 2)';
  @override
  String get outOfStockArticlesCount => 'منتجات نفدت من المخزون (0)';
  @override
  String get totalUnitsInStock => 'إجمالي القطع بالمخزن';

  // --- Settings ---
  @override
  String get settingsTitle => 'الإعدادات وتجهيزات النظام';
  @override
  String get tabGeneral => 'العام واللغة';
  @override
  String get tabHardware => 'أجهزة نقطة البيع';
  @override
  String get tabBackup => 'النسخ الاحتياطي والسلامة';
  @override
  String get tabImportExport => 'استيراد وتصدير CSV';
  @override
  String get languageSection => 'لغة التطبيق';
  @override
  String get selectLanguage => 'اختر لغة العرض';
  @override
  String get languageFr => 'Français (الفرنسية)';
  @override
  String get languageAr => 'العربية (RTL)';
  @override
  String get languageEn => 'English (الإنجليزية)';
  @override
  String get storeSection => 'بيانات المتجر';
  @override
  String get companyName => 'اسم الشركة / المؤسسة';
  @override
  String get storeName => 'اسم الفرع / المتجر';
  @override
  String get fiscalId => 'المعرف الجبائي / الرقم الضريبي';
  @override
  String get phone => 'رقم الهاتف';
  @override
  String get address => 'العنوان';
  @override
  String get printerThermal => 'طابعة الإيصالات الحرارية (ESC/POS)';
  @override
  String get printerLabel => 'طابعة ملصقات الباركود (TSPL / ZPL)';
  @override
  String get customerDisplay => 'شاشة عرض الزبون (VFD / LCD)';
  @override
  String get testPrinter => 'طباعة إيصال اختباري';
  @override
  String get testLabelPrinter => 'طباعة ملصق اختباري';
  @override
  String get testCustomerDisplay => 'فحص شاشة العرض';
  @override
  String get testCashDrawer => 'اختبار فتح الدرج';
  @override
  String get backupDatabase => 'إنشاء نسخة احتياطية محلية متكاملة';
  @override
  String get databaseIntegrity => 'فحص سلامة قاعدة البيانات';
  @override
  String get runDiagnostics => 'بدء الفحص والتشخيص';
  @override
  String get backupSuccess => 'تم إنشاء النسخة الاحتياطية بنجاح!';
  @override
  String get diagnosticsPass => 'قاعدة البيانات سليمة تماماً وبدون أي أخطاء.';
  @override
  String get importCsv => 'استيراد دليل المنتجات (CSV)';
  @override
  String get exportCsv => 'تصدير دليل المنتجات (CSV)';

  // --- Auth & Access ---
  @override
  String get loginTitle => 'تسجيل الدخول إلى الصندوق';
  @override
  String get selectUser => 'اختر المستخدم';
  @override
  String get enterPin => 'أدخل الرمز السري PIN (4 أرقام)';
  @override
  String get invalidPin => 'الرمز السري غير صحيح';
  @override
  String get screenLocked => 'الجلسة مقفلة';
  @override
  String get unlockAction => 'إلغاء القفل';
  @override
  String get managerOverrideTitle => 'مطلوب إذن المسؤول';
  @override
  String get managerOverrideReason =>
      'يتطلب هذا الإجراء مصادقة من المدير أو المالك';
  @override
  String get authorizeAction => 'منح الصلاحية';
  @override
  String get welcomeTitle => 'مرحبًا بك في JazzPOS';
  @override
  String get noUsersConfigured =>
      'لم يتم إعداد أي مستخدم. يرجى بدء معالج الإعداد الأولي.';
  @override
  String get launchSetupWizard => 'بدء الإعداد الأولي';
  @override
  String get posAppSubtitle => 'نظام نقاط البيع للأزياء والملابس الجاهزة';
  @override
  String get setupWizardButton => 'معالج الإعداد / إضافة مستخدم';
  @override
  String pinForUser(String name) => 'الرمز السري لـ $name';
  @override
  String get selectUserRequired => 'يرجى اختيار مستخدم';
  @override
  String get enterPinRequired => 'يرجى إدخال الرمز السري PIN';
  @override
  String get loginAction => 'تسجيل الدخول';
  @override
  String activeSession(String name, String role) =>
      'الجلسة النشطة: $name ($role)';
  @override
  String get switchCashier => 'تبديل أمين الصندوق';
  @override
  String get managerEmergencyUnlock => 'إلغاء قفل المدير';
  @override
  String get managerOverrideUnlockTitle => 'إلغاء قفل الصندوق في حالات الطوارئ';
  @override
  String get managerPinInvalid => 'الرمز السري للمسؤول غير صحيح';
  @override
  String get selectVariantSubtitle => 'حدد المقاس واللون';
  @override
  String unitsInStock(int count) => '$count في المخزن';
  @override
  String get receiptPreviewTitle => 'معاينة إيصال الصندوق';
  @override
  String get receiptPreviewDuplicate => 'معاينة الإيصال (نسخة مطابقة)';
  @override
  String get receiptPrintSuccess => 'تم إرسال الإيصال إلى الطابعة بنجاح';
  @override
  String receiptPrintError(String error) => 'خطأ في الطباعة: $error';
  @override
  String get reprintAction => 'إعادة الطباعة';
  @override
  String get printingInProgress => 'جارٍ الطباعة...';

  // --- Formatting Helpers ---
  @override
  String get currencySymbol => 'د.ت';

  @override
  String categoryName(String rawName) {
    switch (rawName.trim().toLowerCase()) {
      case 'hauts & chemises':
      case 'tops & shirts':
      case 'قمصان وبلوزات':
        return 'قمصان وبلوزات';
      case 'pantalons & jeans':
      case 'pants & jeans':
      case 'سراويل وجينز':
        return 'سراويل وجينز';
      case 'robes & ensembles':
      case 'dresses & sets':
      case 'فساتين وأطقم':
        return 'فساتين وأطقم';
      case 'vestes & manteaux':
      case 'jackets & coats':
      case 'سترات ومعاطف':
        return 'سترات ومعاطف';
      case 'accessoires':
      case 'accessories':
      case 'إكسسوارات':
        return 'إكسسوارات';
      case 'chaussures':
      case 'shoes':
      case 'أحذية':
        return 'أحذية';
      case 'hommes':
      case 'men':
      case 'رجال':
        return 'رجال';
      case 'femmes':
      case 'women':
      case 'نساء':
        return 'نساء';
      case 'enfants':
      case 'children':
      case 'أطفال':
        return 'أطفال';
      default:
        return rawName;
    }
  }

  @override
  String formatCurrency(double amount) => '${amount.toStringAsFixed(3)} د.ت';
  @override
  String formatStock(int count) =>
      '$count ${count > 2 && count < 11 ? 'قطع' : 'قطعة'}';
}
