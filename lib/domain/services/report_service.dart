import 'package:drift/drift.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/constants/permissions.dart';
import 'package:jazzpos/domain/services/permission_guard.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/data/database/app_database.dart';

class SalesReportSummary {
  final DateTime startDate;
  final DateTime endDate;
  final int totalSalesCount;
  final Money grossSales;
  final Money totalDiscounts;
  final Money totalRefunds;
  final Money netSales;
  final Money totalCost;
  final Money grossProfit;
  final double grossMarginPercent;
  final Map<String, Money> salesByPaymentMethod;
  final Map<String, int> salesByCashier;

  const SalesReportSummary({
    required this.startDate,
    required this.endDate,
    required this.totalSalesCount,
    required this.grossSales,
    required this.totalDiscounts,
    required this.totalRefunds,
    required this.netSales,
    required this.totalCost,
    required this.grossProfit,
    required this.grossMarginPercent,
    required this.salesByPaymentMethod,
    required this.salesByCashier,
  });
}

class ClothingSizePerformance {
  final String size;
  final int unitsSold;
  final Money revenue;

  const ClothingSizePerformance({
    required this.size,
    required this.unitsSold,
    required this.revenue,
  });
}

class InventoryValuationReport {
  final int totalVariants;
  final int totalUnitsInStock;
  final Money valuationAtCost;
  final Money valuationAtRetail;
  final Money potentialProfit;
  final int lowStockCount;
  final int outOfStockCount;

  const InventoryValuationReport({
    required this.totalVariants,
    required this.totalUnitsInStock,
    required this.valuationAtCost,
    required this.valuationAtRetail,
    required this.potentialProfit,
    required this.lowStockCount,
    required this.outOfStockCount,
  });
}

class OrderLineDetail {
  final SaleLine line;
  final String? imageUrl;
  const OrderLineDetail(this.line, this.imageUrl);
}

class OrderDetails {
  final Sale sale;
  final List<OrderLineDetail> lines;
  final List<SalePayment> payments;
  final String cashierName;
  final String registerCode;
  final Customer? customer;
  final Company? company;
  final Store? store;
  final List<Return> returns;

  const OrderDetails({
    required this.sale,
    required this.lines,
    required this.payments,
    required this.cashierName,
    required this.registerCode,
    required this.customer,
    required this.company,
    required this.store,
    required this.returns,
  });

  Money get refunded => returns.fold(
    Money.zero,
    (sum, r) => sum + Money.fromMillimes(r.totalRefundMillimes),
  );

  int get itemCount => lines.fold(0, (a, l) => a + l.line.quantity);
}

class DashboardBucket {
  final String label;
  final int millimes;
  const DashboardBucket(this.label, this.millimes);
}

class DashboardTransaction {
  final String saleId;
  final List<String?> imageUrls;
  final String receiptNumber;
  final DateTime time;
  final int itemCount;
  final String paymentMethod;
  final Money total;
  final String status;

  const DashboardTransaction({
    required this.saleId,
    this.imageUrls = const [],
    required this.receiptNumber,
    required this.time,
    required this.itemCount,
    required this.paymentMethod,
    required this.total,
    required this.status,
  });
}

class DashboardSummary {
  final SalesReportSummary current;
  final SalesReportSummary previous;
  final List<DashboardBucket> buckets;
  final List<DashboardTransaction> recent;
  final InventoryValuationReport stock;

  const DashboardSummary({
    required this.current,
    required this.previous,
    required this.buckets,
    required this.recent,
    required this.stock,
  });

  Money get averageBasket => current.totalSalesCount == 0
      ? Money.zero
      : Money.fromMillimes(
          (current.netSales.millimes / current.totalSalesCount).round(),
        );
}

class ReportService {
  final AppDatabase db;

  ReportService(this.db);

  /// Generate Sales & Profit summary for a date range from local data
  Future<SalesReportSummary> getSalesReport({
    required String actorId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    await PermissionGuard.requirePermission(
      db,
      actorId,
      AppPermissions.viewReports,
    );
    // 1. Fetch sales in date range
    final sales =
        await (db.select(db.sales)..where(
              (tbl) =>
                  tbl.createdAt.isBiggerOrEqualValue(startDate) &
                  tbl.createdAt.isSmallerOrEqualValue(endDate) &
                  tbl.status.isIn([
                    AppConstants.saleCompleted,
                    AppConstants.salePartiallyRefunded,
                    AppConstants.saleRefunded,
                  ]),
            ))
            .get();

    final saleIds = sales.map((s) => s.id).toList();

    // 2. Fetch sale lines
    final lines = saleIds.isEmpty
        ? <SaleLine>[]
        : await (db.select(
            db.saleLines,
          )..where((tbl) => tbl.saleId.isIn(saleIds))).get();

    // 3. Fetch refunds in date range
    final returns =
        await (db.select(db.returns)..where(
              (tbl) =>
                  tbl.createdAt.isBiggerOrEqualValue(startDate) &
                  tbl.createdAt.isSmallerOrEqualValue(endDate),
            ))
            .get();

    final returnIds = returns.map((r) => r.id).toList();
    final returnLines = returnIds.isEmpty
        ? <ReturnLine>[]
        : await (db.select(
            db.returnLines,
          )..where((tbl) => tbl.returnId.isIn(returnIds))).get();
    final originalSaleLineIds = returnLines
        .map((line) => line.originalSaleLineId)
        .whereType<String>()
        .toSet()
        .toList();
    final originalSaleLines = originalSaleLineIds.isEmpty
        ? <SaleLine>[]
        : await (db.select(
            db.saleLines,
          )..where((tbl) => tbl.id.isIn(originalSaleLineIds))).get();
    final costByOriginalLineId = {
      for (final line in originalSaleLines) line.id: line.unitCostMillimes,
    };

    // 4. Fetch payments
    final payments = saleIds.isEmpty
        ? <SalePayment>[]
        : await (db.select(
            db.salePayments,
          )..where((tbl) => tbl.saleId.isIn(saleIds))).get();

    Money gross = Money.zero;
    // `sales.discountMillimes` is the canonical discount total.  It includes
    // both line discounts and cart-level discounts, whereas sale_lines only
    // retains the former.
    final discounts = sales.fold(
      Money.zero,
      (sum, sale) => sum + Money.fromMillimes(sale.discountMillimes),
    );
    Money costs = Money.zero;

    for (final l in lines) {
      gross += Money.fromMillimes(l.originalPriceMillimes * l.quantity);
      costs += Money.fromMillimes(l.unitCostMillimes * l.quantity);
    }

    // Returned receipt lines are placed back in inventory. Reverse their
    // original COGS in the period of the return so a full return is neither a
    // negative sale nor a permanent cost of goods sold.
    for (final line in returnLines) {
      final originalUnitCost = line.originalSaleLineId == null
          ? null
          : costByOriginalLineId[line.originalSaleLineId!];
      if (originalUnitCost != null) {
        costs -= Money.fromMillimes(originalUnitCost * line.quantity);
      }
    }

    Money totalRefunds = returns.fold(
      Money.zero,
      (s, r) => s + Money.fromMillimes(r.totalRefundMillimes),
    );
    final netSales = (gross - discounts) - totalRefunds;
    final profit = netSales - costs;
    final marginPct = netSales > Money.zero
        ? (profit.millimes / netSales.millimes) * 100
        : 0.0;

    final byPayment = <String, Money>{};
    for (final p in payments) {
      byPayment[p.paymentMethod] =
          (byPayment[p.paymentMethod] ?? Money.zero) +
          Money.fromMillimes(p.amountMillimes);
    }

    final byCashier = <String, int>{};
    for (final s in sales) {
      byCashier[s.cashierId] = (byCashier[s.cashierId] ?? 0) + 1;
    }

    return SalesReportSummary(
      startDate: startDate,
      endDate: endDate,
      totalSalesCount: sales.length,
      grossSales: gross,
      totalDiscounts: discounts,
      totalRefunds: totalRefunds,
      netSales: netSales,
      totalCost: costs,
      grossProfit: profit,
      grossMarginPercent: marginPct,
      salesByPaymentMethod: byPayment,
      salesByCashier: byCashier,
    );
  }


  /// variantId -> best available image (variant photo, else product photo).
  Future<Map<String, String?>> _imagesForVariants(Iterable<String> ids) async {
    final unique = ids.toSet().toList();
    if (unique.isEmpty) return {};
    final variants = await (db.select(
      db.productVariants,
    )..where((t) => t.id.isIn(unique))).get();
    final productIds = variants.map((v) => v.productId).toSet().toList();
    final products = productIds.isEmpty
        ? <Product>[]
        : await (db.select(db.products)..where((t) => t.id.isIn(productIds)))
              .get();
    final productImage = {for (final p in products) p.id: p.imageUrl};
    return {
      for (final v in variants) v.id: v.imageUrl ?? productImage[v.productId],
    };
  }

  /// Full detail of one sale for the order-details screen.
  Future<OrderDetails> getOrderDetails({
    required String actorId,
    required String saleId,
  }) async {
    await PermissionGuard.requirePermission(
      db,
      actorId,
      AppPermissions.viewReports,
    );
    final sale = await (db.select(
      db.sales,
    )..where((t) => t.id.equals(saleId))).getSingleOrNull();
    if (sale == null) {
      throw const ValidationException('Commande introuvable.');
    }
    final lines = await (db.select(
      db.saleLines,
    )..where((t) => t.saleId.equals(saleId))).get();
    final payments = await (db.select(
      db.salePayments,
    )..where((t) => t.saleId.equals(saleId))).get();
    final images = await _imagesForVariants(lines.map((l) => l.variantId));
    final cashier = await (db.select(
      db.users,
    )..where((t) => t.id.equals(sale.cashierId))).getSingleOrNull();
    final register = await (db.select(
      db.registers,
    )..where((t) => t.id.equals(sale.registerId))).getSingleOrNull();
    final store = await (db.select(
      db.stores,
    )..where((t) => t.id.equals(sale.storeId))).getSingleOrNull();
    final company = store == null
        ? null
        : await (db.select(
            db.companies,
          )..where((t) => t.id.equals(store.companyId))).getSingleOrNull();
    final customer = sale.customerId == null
        ? null
        : await (db.select(
            db.customers,
          )..where((t) => t.id.equals(sale.customerId!))).getSingleOrNull();
    final returns = await (db.select(db.returns)
          ..where((t) => t.originalSaleId.equals(saleId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    return OrderDetails(
      sale: sale,
      lines: [for (final l in lines) OrderLineDetail(l, images[l.variantId])],
      payments: payments,
      cashierName: cashier?.displayName ?? '—',
      registerCode: register?.code ?? '—',
      customer: customer,
      company: company,
      store: store,
      returns: returns,
    );
  }

  /// Everything the dashboard shows for the last [days] days (1 = today),
  /// plus the equally long period before it for trend arrows.
  Future<DashboardSummary> getDashboardSummary({
    required String actorId,
    int days = 1,
    DateTime? now,
  }) async {
    await PermissionGuard.requirePermission(
      db,
      actorId,
      AppPermissions.viewReports,
    );
    final clock = now ?? DateTime.now();
    final startOfToday = DateTime(clock.year, clock.month, clock.day);
    final start = startOfToday.subtract(Duration(days: days - 1));
    final end = startOfToday
        .add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));
    final prevStart = start.subtract(Duration(days: days));
    final prevEnd = start.subtract(const Duration(microseconds: 1));

    final current = await getSalesReport(
      actorId: actorId,
      startDate: start,
      endDate: end,
    );
    final previous = await getSalesReport(
      actorId: actorId,
      startDate: prevStart,
      endDate: prevEnd,
    );

    final counted = [
      AppConstants.saleCompleted,
      AppConstants.salePartiallyRefunded,
      AppConstants.saleRefunded,
    ];
    final periodSales =
        await (db.select(db.sales)..where(
              (t) =>
                  t.createdAt.isBiggerOrEqualValue(start) &
                  t.createdAt.isSmallerOrEqualValue(end) &
                  t.status.isIn(counted),
            ))
            .get();

    // Buckets: hours for a single day, days for longer ranges.
    final buckets = <DashboardBucket>[];
    if (days == 1) {
      var first = 8, last = 22;
      for (final sale in periodSales) {
        final h = sale.createdAt.hour;
        if (h < first) first = h;
        if (h > last) last = h;
      }
      for (var h = first; h <= last; h++) {
        final sum = periodSales
            .where((x) => x.createdAt.hour == h)
            .fold<int>(0, (a, x) => a + x.totalMillimes);
        buckets.add(
          DashboardBucket('${h.toString().padLeft(2, '0')}h', sum),
        );
      }
    } else {
      for (var i = 0; i < days; i++) {
        final day = start.add(Duration(days: i));
        final sum = periodSales
            .where(
              (x) =>
                  x.createdAt.year == day.year &&
                  x.createdAt.month == day.month &&
                  x.createdAt.day == day.day,
            )
            .fold<int>(0, (a, x) => a + x.totalMillimes);
        buckets.add(
          DashboardBucket(
            '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}',
            sum,
          ),
        );
      }
    }

    final latest =
        await (db.select(db.sales)
              ..where((t) => t.status.isNotValue(AppConstants.saleVoided))
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(5))
            .get();
    final ids = latest.map((e) => e.id).toList();
    final lines = ids.isEmpty
        ? <SaleLine>[]
        : await (db.select(db.saleLines)..where((t) => t.saleId.isIn(ids)))
              .get();
    final pays = ids.isEmpty
        ? <SalePayment>[]
        : await (db.select(db.salePayments)..where((t) => t.saleId.isIn(ids)))
              .get();
    final images = await _imagesForVariants(lines.map((l) => l.variantId));
    final recent = [
      for (final sale in latest)
        DashboardTransaction(
          saleId: sale.id,
          imageUrls: [
            for (final l in lines.where((l) => l.saleId == sale.id))
              images[l.variantId],
          ],
          receiptNumber: sale.receiptNumber,
          time: sale.createdAt,
          itemCount: lines
              .where((l) => l.saleId == sale.id)
              .fold<int>(0, (a, l) => a + l.quantity),
          paymentMethod: () {
            final methods = pays
                .where((p) => p.saleId == sale.id)
                .map((p) => p.paymentMethod)
                .toSet();
            return methods.length == 1
                ? methods.first
                : (methods.isEmpty ? '' : AppConstants.paymentMixed);
          }(),
          total: Money.fromMillimes(sale.totalMillimes),
          status: sale.status,
        ),
    ];

    final stock = await getInventoryValuation(actorId: actorId);
    return DashboardSummary(
      current: current,
      previous: previous,
      buckets: buckets,
      recent: recent,
      stock: stock,
    );
  }

  /// Clothing Intelligence: Size performance analysis
  Future<List<ClothingSizePerformance>> getSizePerformance({
    required String actorId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    await PermissionGuard.requirePermission(
      db,
      actorId,
      AppPermissions.viewReports,
    );
    final sales =
        await (db.select(db.sales)..where(
              (tbl) =>
                  tbl.createdAt.isBiggerOrEqualValue(startDate) &
                  tbl.createdAt.isSmallerOrEqualValue(endDate) &
                  tbl.status.equals(AppConstants.saleCompleted),
            ))
            .get();

    final saleIds = sales.map((s) => s.id).toList();
    if (saleIds.isEmpty) return [];

    final lines = await (db.select(
      db.saleLines,
    )..where((tbl) => tbl.saleId.isIn(saleIds))).get();

    final sizeMap = <String, ({int qty, int rev})>{};

    for (final l in lines) {
      // Extract size from variant description (e.g. "Noir / M" -> "M")
      final parts = l.variantDescription.split('/');
      final size = parts.length > 1
          ? parts.last.trim()
          : l.variantDescription.trim();

      final current = sizeMap[size] ?? (qty: 0, rev: 0);
      sizeMap[size] = (
        qty: current.qty + l.quantity,
        rev: current.rev + l.totalMillimes,
      );
    }

    final result = sizeMap.entries
        .map(
          (e) => ClothingSizePerformance(
            size: e.key,
            unitsSold: e.value.qty,
            revenue: Money.fromMillimes(e.value.rev),
          ),
        )
        .toList();

    result.sort((a, b) => b.unitsSold.compareTo(a.unitsSold));
    return result;
  }

  /// Inventory Valuation & Stock Health Report
  Future<InventoryValuationReport> getInventoryValuation({
    required String actorId,
  }) async {
    await PermissionGuard.requirePermission(
      db,
      actorId,
      AppPermissions.viewReports,
    );
    final variants = await (db.select(
      db.productVariants,
    )..where((tbl) => tbl.isActive.equals(true))).get();
    final stockLevels = await db.select(db.stockLevels).get();

    int totalUnits = 0;
    Money totalCost = Money.zero;
    Money totalRetail = Money.zero;
    int lowStock = 0;
    int outOfStock = 0;

    for (final v in variants) {
      final lvls = stockLevels.where((s) => s.variantId == v.id);
      final qty = lvls.fold(0, (sum, s) => sum + s.quantity);

      totalUnits += qty;
      final cost = Money.fromMillimes(v.costPriceOverrideMillimes ?? 0);
      final price = Money.fromMillimes(v.salePriceOverrideMillimes ?? 0);

      totalCost += cost * qty;
      totalRetail += price * qty;

      if (qty <= 0) {
        outOfStock++;
      } else if (qty <= v.minStockAlert) {
        lowStock++;
      }
    }

    return InventoryValuationReport(
      totalVariants: variants.length,
      totalUnitsInStock: totalUnits,
      valuationAtCost: totalCost,
      valuationAtRetail: totalRetail,
      potentialProfit: totalRetail - totalCost,
      lowStockCount: lowStock,
      outOfStockCount: outOfStock,
    );
  }
}
