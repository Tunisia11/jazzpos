import 'package:jazzpos/core/money/money.dart';
import 'cart_item.dart';

class PaymentSplit {
  final String method; // CASH, CARD, STORE_CREDIT
  final Money amount;
  final Money tendered;
  final Money change;
  final String? reference;

  const PaymentSplit({
    required this.method,
    required this.amount,
    this.tendered = Money.zero,
    this.change = Money.zero,
    this.reference,
  });
}

class CheckoutRequest {
  final String storeId;
  final String registerId;
  final String shiftId;
  final String cashierId;
  final String? customerId;
  final List<CartItem> items;
  final Money cartDiscount;
  final List<PaymentSplit> payments;
  final String idempotencyKey;
  final String? notes;
  final String? managerOverrideId;

  const CheckoutRequest({
    required this.storeId,
    required this.registerId,
    required this.shiftId,
    required this.cashierId,
    this.customerId,
    required this.items,
    this.cartDiscount = Money.zero,
    required this.payments,
    required this.idempotencyKey,
    this.notes,
    this.managerOverrideId,
  });

  Money get subtotal {
    return items.fold(Money.zero, (sum, item) => sum + item.total);
  }

  Money get total {
    final t = subtotal - cartDiscount;
    return t.isNegative ? Money.zero : t;
  }

  Money get totalPaid {
    return payments.fold(Money.zero, (sum, p) => sum + p.amount);
  }
}
