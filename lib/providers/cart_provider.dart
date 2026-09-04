import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  final String? lastError;

  const CartState({
    this.items = const [],
    this.cartDiscount = Money.zero,
    this.customer,
    this.isProcessing = false,
    this.lastError,
  });

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
    String? lastError,
  }) {
    return CartState(
      items: items ?? this.items,
      cartDiscount: cartDiscount ?? this.cartDiscount,
      customer: clearCustomer ? null : (customer ?? this.customer),
      isProcessing: isProcessing ?? this.isProcessing,
      lastError: lastError,
    );
  }
}

class CartNotifier extends StateNotifier<CartState> {
  final CatalogService catalogService;
  final SaleService saleService;

  CartNotifier(this.catalogService, this.saleService) : super(const CartState());

  /// Add item to cart from search result
  void addItem(VariantSearchResult variant, {int quantity = 1}) {
    final existingIndex = state.items.indexWhere((i) => i.variantId == variant.variantId);
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
      );
      state = state.copyWith(items: [...state.items, newItem]);
    }
  }

  /// Instant barcode scan handler: looks up variant and adds/increments in cart!
  Future<bool> addItemByBarcode(String barcode) async {
    final results = await catalogService.searchVariants(barcode.trim());
    if (results.isNotEmpty) {
      addItem(results.first);
      return true;
    }
    return false;
  }

  void updateQuantity(String variantId, int newQuantity) {
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
    final newItems = state.items.where((i) => i.variantId != variantId).toList();
    state = state.copyWith(items: newItems);
  }

  void applyLineDiscount(String variantId, Money discount) {
    final newItems = state.items.map((i) {
      if (i.variantId == variantId) {
        return i.copyWith(lineDiscount: discount);
      }
      return i;
    }).toList();
    state = state.copyWith(items: newItems);
  }

  void applyCartDiscount(Money discount) {
    state = state.copyWith(cartDiscount: discount);
  }

  void setCustomer(Customer? customer) {
    state = state.copyWith(customer: customer, clearCustomer: customer == null);
  }

  void clearCart() {
    state = const CartState();
  }

  /// Hold / Suspend the active cart
  Future<String> suspendCart({
    required String referenceName,
    required String cashierId,
    required String registerId,
  }) async {
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
    String? managerOverrideId,
    String? notes,
  }) async {
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
        idempotencyKey: IdGenerator.uuid(),
        notes: notes,
        managerOverrideId: managerOverrideId,
      );

      final result = await saleService.checkout(request);
      clearCart();
      return result;
    } catch (e) {
      state = state.copyWith(isProcessing: false, lastError: e.toString());
      rethrow;
    }
  }
}

final cartNotifierProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier(
    ref.watch(catalogServiceProvider),
    ref.watch(saleServiceProvider),
  );
});
