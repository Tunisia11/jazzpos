import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/data/database/app_database.dart';
import '../models/cart_item.dart';

class PricingService {
  final AppDatabase db;

  PricingService(this.db);

  /// Get configured max cashier discount percentage (e.g. 10%)
  Future<double> getMaxCashierDiscountPercent() async {
    final setting =
        await (db.select(db.appSettings)..where(
              (tbl) =>
                  tbl.key.equals(AppConstants.keyMaxCashierDiscountPercent),
            ))
            .getSingleOrNull();
    if (setting == null) return 10.0;
    return double.tryParse(setting.value) ?? 10.0;
  }

  /// Validate manual discount application
  Future<void> validateDiscount({
    required Money originalAmount,
    required Money discountAmount,
    required String userRole,
    String? managerOverrideId,
  }) async {
    if (discountAmount.isNegative) {
      throw const ValidationException('Discount cannot be negative');
    }
    if (discountAmount > originalAmount) {
      throw const ValidationException('Discount cannot exceed original amount');
    }

    // Owner or Manager can apply any discount up to 100%
    if (userRole == 'OWNER' || userRole == 'MANAGER') return;

    // Cashier check
    final maxPercent = await getMaxCashierDiscountPercent();
    final maxAllowedDiscount = originalAmount.percentageDiscount(maxPercent);

    if (discountAmount > maxAllowedDiscount) {
      if (managerOverrideId == null || managerOverrideId.isEmpty) {
        throw ValidationException(
          'Discount exceeds cashier limit of ${maxPercent.toStringAsFixed(0)}%. Manager override required.',
          code: 'REQUIRES_MANAGER_OVERRIDE',
        );
      }
    }
  }

  /// Calculate item pricing with line discount
  CartItem applyLineDiscount(CartItem item, Money discount) {
    if (discount > item.subtotal) {
      discount = item.subtotal;
    }
    return item.copyWith(lineDiscount: discount);
  }

  /// Apply percentage discount to cart item
  CartItem applyPercentageLineDiscount(CartItem item, num percent) {
    final discount = item.subtotal.percentageDiscount(percent);
    return applyLineDiscount(item, discount);
  }
}
