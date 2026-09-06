import 'package:drift/drift.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
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

class ReportService {
  final AppDatabase db;

  ReportService(this.db);

  /// Generate Sales & Profit summary for a date range from local data
  Future<SalesReportSummary> getSalesReport({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
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

  /// Clothing Intelligence: Size performance analysis
  Future<List<ClothingSizePerformance>> getSizePerformance({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
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
  Future<InventoryValuationReport> getInventoryValuation() async {
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
