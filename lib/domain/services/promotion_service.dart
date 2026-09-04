import 'package:drift/drift.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/data/database/app_database.dart';
import '../models/cart_item.dart';

class PromotionService {
  final AppDatabase db;

  PromotionService(this.db);

  /// Evaluate and apply eligible active promotions to the cart items
  Future<List<CartItem>> evaluateCartPromotions(List<CartItem> items) async {
    final now = DateTime.now();

    // Fetch active promotions sorted by priority descending
    final activePromos = await (db.select(db.promotions)
          ..where((tbl) => tbl.isActive.equals(true) & tbl.startDate.isSmallerOrEqualValue(now) & tbl.endDate.isBiggerOrEqualValue(now))
          ..orderBy([(t) => OrderingTerm.desc(t.priority)]))
        .get();

    if (activePromos.isEmpty) return items;

    final updatedItems = List<CartItem>.from(items);

    for (final promo in activePromos) {
      final rules = await (db.select(db.promotionRules)..where((tbl) => tbl.promotionId.equals(promo.id))).get();

      for (int i = 0; i < updatedItems.length; i++) {
        final item = updatedItems[i];
        if (item.lineDiscount > Money.zero) continue; // Already discounted, avoid unwanted stacking

        bool matches = false;
        if (rules.isEmpty || rules.any((r) => r.targetType == 'ALL')) {
          matches = true;
        } else {
          for (final rule in rules) {
            if (rule.targetType == 'PRODUCT' && rule.targetId == item.productId) {
              matches = true;
              break;
            } else if (rule.targetType == 'VARIANT' && rule.targetId == item.variantId) {
              matches = true;
              break;
            }
          }
        }

        if (matches && item.quantity >= promo.minQuantity) {
          Money discount = Money.zero;
          if (promo.promotionType == 'PERCENTAGE') {
            discount = item.subtotal.percentageDiscount(promo.value);
          } else if (promo.promotionType == 'FIXED') {
            discount = Money.fromMillimes(promo.value.toInt()) * item.quantity;
          }

          if (discount > item.subtotal) discount = item.subtotal;
          updatedItems[i] = item.copyWith(lineDiscount: discount);
        }
      }
    }

    return updatedItems;
  }
}
