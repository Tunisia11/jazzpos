import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/models/cart_item.dart';
import 'package:jazzpos/domain/models/checkout_request.dart';
import 'package:jazzpos/domain/services/catalog_service.dart';
import 'package:jazzpos/domain/services/sale_service.dart';
import 'app_providers.dart';

class CartState {
  final List<CartItem> items;
  final Money cartDiscount;
  final Customer? customer;
  final bool isProcessing;
  final bool isLocked;
  final String? lastError;
  final String note;

  const CartState({
    this.items = const [],
    this.cartDiscount = Money.zero,
    this.customer,
    this.isProcessing = false,
    this.isLocked = false,
    this.lastError,
    this.note = '',
  });

  Money get tax => items.fold(Money.zero, (sum, i) => sum + i.taxAmount);

  Money get subtotal => items.fold(Money.zero, (sum, i) => sum + i.total);
  Money get total {
    final t = subtotal - cartDiscount;
    return t.isNegative ? Money.zero : t;
  }

  int get totalItemsCount => items.fold(0, (sum, i) => sum + i.quantity);

  CartState copyWith({
    List<CartItem>? items,
    Money? cartDiscount,
    Customer? customer,
    bool clearCustomer = false,
    bool? isProcessing,
    bool? isLocked,
    String? lastError,
    String? note,
  }) {
    return CartState(
      items: items ?? this.items,
      cartDiscount: cartDiscount ?? this.cartDiscount,
      customer: clearCustomer ? null : (customer ?? this.customer),
      isProcessing: isProcessing ?? this.isProcessing,
      isLocked: isLocked ?? this.isLocked,
      lastError: lastError,
      note: note ?? this.note,
    );
  }
}

class CartPaymentSession {
  CartPaymentSession(this._release);
  void Function()? _release;
  void release() {
    final callback = _release;
    _release = null;
    callback?.call();
  }
}

class CartNotifier extends StateNotifier<CartState> {
  final CatalogService catalogService;
  final SaleService saleService;

  CartNotifier(this.catalogService, this.saleService)
    : super(const CartState());

  final Set<Object> _paymentSessions = {};
  CartPaymentSession? _legacyLock;

  CartPaymentSession beginPaymentSession() {
    final token = Object();
    _paymentSessions.add(token);
    state = state.copyWith(isLocked: true);
    return CartPaymentSession(() {
      _paymentSessions.remove(token);
      if (mounted) state = state.copyWith(isLocked: _paymentSessions.isNotEmpty);
    });
  }

  void lockCart() => _legacyLock ??= beginPaymentSession();
  void unlockCart() {
    _legacyLock?.release();
    _legacyLock = null;
  }

  /// Add item to cart from search result
  void addItem(VariantSearchResult variant, {int quantity = 1}) {
    if (state.isLocked || state.isProcessing) {
      PosLogger.instance.warning('Cart', 'Cannot add item: cart is locked during payment/modal');
      return;
    }
    final existingIndex = state.items.indexWhere(
      (i) => i.variantId == variant.variantId,
    );
    if (existingIndex >= 0) {
      final existing = state.items[existingIndex];
      final updated = existing.copyWith(quantity: existing.quantity + quantity);
      final newItems = List<CartItem>.from(state.items);
      newItems[existingIndex] = updated;
      state = state.copyWith(items: newItems);
    } else {
      final newItem = CartItem(
        variantId: variant.variantId,
        productId: variant.productId,
        productName: variant.productName,
        variantDescription: variant.variantDescription,
        sku: variant.sku,
        barcode: variant.barcode,
        unitPrice: variant.salePrice,
        originalPrice: variant.salePrice,
        quantity: quantity,
        taxRatePercent: variant.taxRatePercent,
        unitCost: variant.costPrice,
        imageUrl: variant.imageUrl,
      );
      state = state.copyWith(items: [...state.items, newItem]);
    }
  }

  /// Instant barcode scan handler: looks up variant using strict exact barcode matching.
  /// Never falls back to partial search. Refuses mutation if cart is locked.
  Future<bool> addItemByBarcode(String barcode) async {
    if (state.isLocked || state.isProcessing) {
      PosLogger.instance.warning(
        'Cart',
        'Barcode scan "$barcode" rejected: cart is locked during payment/modal',
      );
      return false;
    }
    final variant = await catalogService.findVariantByExactBarcode(barcode);
    if (variant != null) {
      if (state.isLocked || state.isProcessing) return false;
      addItem(variant);
      return true;
    }
    return false;
  }

  void updateQuantity(String variantId, int newQuantity) {
    if (state.isLocked || state.isProcessing) {
      PosLogger.instance.warning('Cart', 'Cannot update quantity: cart is locked');
      return;
    }
    if (newQuantity <= 0) {
      removeItem(variantId);
      return;
    }
    final newItems = state.items.map((i) {
      if (i.variantId == variantId) {
        return i.copyWith(quantity: newQuantity);
      }
      return i;
    }).toList();
    state = state.copyWith(items: newItems);
  }

  void removeItem(String variantId) {
    if (state.isLocked || state.isProcessing) {
      PosLogger.instance.warning('Cart', 'Cannot remove item: cart is locked');
      return;
    }
    final newItems = state.items
        .where((i) => i.variantId != variantId)
        .toList();
    state = state.copyWith(items: newItems);
  }

  void applyLineDiscount(String variantId, Money discount) {
    if (state.isLocked || state.isProcessing) return;
    final newItems = state.items.map((i) {
      if (i.variantId == variantId) {
        return i.copyWith(lineDiscount: discount);
      }
      return i;
    }).toList();
    state = state.copyWith(items: newItems);
  }

  void applyCartDiscount(Money discount) {
    if (state.isLocked || state.isProcessing) return;
    state = state.copyWith(cartDiscount: discount);
  }

  void setCustomer(Customer? customer) {
    if (state.isLocked || state.isProcessing) return;
    state = state.copyWith(customer: customer, clearCustomer: customer == null);
  }

  void setNote(String value) {
    if (state.isProcessing) return;
    state = state.copyWith(note: value);
  }

  void clearCart() {
    if (state.isLocked || state.isProcessing) {
      PosLogger.instance.warning('Cart', 'Cannot clear cart: cart is locked');
      return;
    }
    state = const CartState();
  }

  /// Internal reset after checkout success
  void _resetAfterCheckout() {
    state = CartState(isLocked: _paymentSessions.isNotEmpty);
  }

  /// Hold / Suspend the active cart
  Future<String> suspendCart({
    required String referenceName,
    required String cashierId,
    required String registerId,
  }) async {
    if (state.isLocked || state.isProcessing) throw StateError('Cart is locked');
    if (state.items.isEmpty) throw Exception('Cannot suspend an empty cart');
    final id = await saleService.suspendCart(
      referenceName: referenceName,
      cashierId: cashierId,
      registerId: registerId,
      items: state.items,
      cartDiscount: state.cartDiscount,
    );
    clearCart();
    return id;
  }

  /// Resume a suspended cart
  void resumeCart(SuspendedCart suspended) {
    if (state.isLocked || state.isProcessing) return;
    final data = jsonDecode(suspended.cartJson) as Map<String, dynamic>;
    final itemsList = (data['items'] as List).map((i) {
      return CartItem(
        variantId: i['variantId'] as String,
        productId: i['productId'] as String,
        productName: i['productName'] as String,
        variantDescription: i['variantDescription'] as String,
        sku: i['sku'] as String,
        barcode: i['barcode'] as String,
        unitPrice: Money.fromMillimes(i['unitPrice'] as int),
        originalPrice: Money.fromMillimes(i['originalPrice'] as int),
        quantity: i['quantity'] as int,
        lineDiscount: Money.fromMillimes(i['lineDiscount'] as int? ?? 0),
        taxRatePercent: (i['taxRatePercent'] as num? ?? 0.0).toDouble(),
        unitCost: Money.fromMillimes(i['unitCost'] as int? ?? 0),
      );
    }).toList();

    final cartDisc = Money.fromMillimes(data['cartDiscount'] as int? ?? 0);
    state = state.copyWith(items: itemsList, cartDiscount: cartDisc);
  }

  /// Execute checkout
  Future<SaleCompletedResult> checkout({
    required String storeId,
    required String registerId,
    required String shiftId,
    required String cashierId,
    required List<PaymentSplit> payments,
    String? idempotencyKey,
    String? managerOverrideId,
    String? notes,
  }) async {
    if (state.isProcessing) throw StateError('Checkout is already in progress');
    state = state.copyWith(isProcessing: true, lastError: null);
    try {
      final request = CheckoutRequest(
        storeId: storeId,
        registerId: registerId,
        shiftId: shiftId,
        cashierId: cashierId,
        customerId: state.customer?.id,
        items: state.items,
        cartDiscount: state.cartDiscount,
        payments: payments,
        idempotencyKey: idempotencyKey ?? IdGenerator.uuid(),
        notes: notes ?? (state.note.trim().isEmpty ? null : state.note.trim()),
        managerOverrideId: managerOverrideId,
      );

      final result = await saleService.checkout(request);
      _resetAfterCheckout();
      return result;
    } catch (e) {
      state = state.copyWith(isProcessing: false, lastError: e.toString());
      rethrow;
    }
  }
}

final cartNotifierProvider = StateNotifierProvider<CartNotifier, CartState>((
  ref,
) {
  return CartNotifier(
    ref.watch(catalogServiceProvider),
    ref.watch(saleServiceProvider),
  );
});
