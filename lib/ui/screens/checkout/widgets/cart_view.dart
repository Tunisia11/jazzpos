import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/domain/models/cart_item.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/providers/cart_provider.dart';
import 'package:jazzpos/providers/shift_provider.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';
import 'package:jazzpos/ui/widgets/common/app_button.dart';
import 'package:jazzpos/ui/widgets/common/app_empty_state.dart';
import 'package:jazzpos/ui/widgets/money_display.dart';
import 'payment_dialog.dart';
import 'suspended_sales_dialog.dart';

class CartView extends ConsumerWidget {
  final String storeId;
  final String registerId;

  const CartView({super.key, required this.storeId, required this.registerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartState = ref.watch(cartNotifierProvider);
    final cartNotifier = ref.read(cartNotifierProvider.notifier);
    final shift = ref.watch(shiftNotifierProvider).activeShift;

    return Container(
      decoration: BoxDecoration(
        color: AppDesignTokens.surface,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusLg),
        border: Border.all(color: AppDesignTokens.border),
        boxShadow: AppDesignTokens.shadowSm,
      ),
      child: Column(
        children: [
          // Cart Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppDesignTokens.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.shopping_cart_outlined,
                      color: AppDesignTokens.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.loc.cart,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        context.loc.itemsInCart(cartState.totalItemsCount),
                        style: const TextStyle(
                          color: AppDesignTokens.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if (cartState.items.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _confirmClearCart(context, cartNotifier),
                    icon: const Icon(
                      Icons.delete_sweep,
                      size: 18,
                      color: AppDesignTokens.danger,
                    ),
                    label: Text(
                      context.loc.clearCart,
                      style: const TextStyle(
                        color: AppDesignTokens.danger,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Customer Tag Bar if selected
          if (cartState.customer != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFEFF6FF),
                border: Border(bottom: BorderSide(color: Color(0xFFDBEAFE))),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.person,
                    size: 16,
                    color: AppDesignTokens.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Client: ${cartState.customer!.name} (${cartState.customer!.phone ?? "Sans tél"})',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppDesignTokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 16,
                      color: AppDesignTokens.textSecondary,
                    ),
                    onPressed: () => cartNotifier.setCustomer(null),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

          // Cart Items List
          Expanded(
            child: cartState.items.isEmpty
                ? AppEmptyState(
                    icon: Icons.shopping_bag_outlined,
                    title: context.loc.cartEmpty,
                    subtitle: context.loc.cartEmptySubtitle,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: cartState.items.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: AppDesignTokens.border, height: 1),
                    itemBuilder: (context, index) {
                      final item = cartState.items[index];
                      return _CartItemTile(
                        item: item,
                        onQuantityChanged: (qty) =>
                            cartNotifier.updateQuantity(item.variantId, qty),
                        onRemove: () => cartNotifier.removeItem(item.variantId),
                        onDiscount: () =>
                            _showDiscountDialog(context, ref, item),
                      );
                    },
                  ),
          ),

          // Cart Footer & Summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppDesignTokens.surfaceSecondary,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(AppDesignTokens.radiusLg),
                bottomRight: Radius.circular(AppDesignTokens.radiusLg),
              ),
              border: Border(top: BorderSide(color: AppDesignTokens.border)),
            ),
            child: Column(
              children: [
                // Totals breakdown
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${context.loc.subtotal}:',
                      style: const TextStyle(
                        color: AppDesignTokens.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    MoneyDisplay(
                      amount: cartState.subtotal,
                      fontSize: 15,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ],
                ),
                if (cartState.cartDiscount > Money.zero) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${context.loc.discount}:',
                            style: const TextStyle(
                              color: AppDesignTokens.danger,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              size: 14,
                              color: AppDesignTokens.danger,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () =>
                                cartNotifier.applyCartDiscount(Money.zero),
                          ),
                        ],
                      ),
                      Text(
                        '-${cartState.cartDiscount.format()}',
                        style: const TextStyle(
                          color: AppDesignTokens.danger,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
                const Divider(color: AppDesignTokens.border, height: 16),

                // Grand Total
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.loc.total,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                        const Text(
                          'TTC inclus',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    MoneyDisplay(
                      amount: cartState.total,
                      fontSize: 26,
                      color: AppDesignTokens.accentOrange,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Quick buttons: Hold (F6) and Customer (F8)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: cartState.items.isEmpty
                            ? null
                            : () => _holdCart(context, ref),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          backgroundColor: AppDesignTokens.surface,
                          side: const BorderSide(color: AppDesignTokens.border),
                          foregroundColor: AppDesignTokens.textPrimary,
                        ),
                        icon: const Icon(
                          Icons.pause,
                          size: 16,
                          color: AppDesignTokens.warning,
                        ),
                        label: Text(
                          context.loc.holdSale,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: cartState.items.isEmpty
                            ? null
                            : () => _showGlobalDiscountDialog(context, ref),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          backgroundColor: AppDesignTokens.surface,
                          side: const BorderSide(color: AppDesignTokens.border),
                          foregroundColor: AppDesignTokens.textPrimary,
                        ),
                        icon: const Icon(
                          Icons.percent,
                          size: 15,
                          color: AppDesignTokens.warning,
                        ),
                        label: Text(
                          context.loc.discount,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Pay Button (F12)
                AppButton(
                  label: shift == null
                      ? context.loc.clickToOpenRegister
                      : context.loc.payAction,
                  variant: AppButtonVariant.cta,
                  height: 50,
                  isExpanded: true,
                  icon: Icons.payments_outlined,
                  shortcutHint: shift == null ? null : 'F12',
                  onPressed: (cartState.items.isEmpty || shift == null)
                      ? null
                      : () => _openPaymentDialog(context, cartState.total),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openPaymentDialog(BuildContext context, Money total) {
    PaymentDialog.show(
      context,
      totalAmount: total,
      storeId: storeId,
      registerId: registerId,
    );
  }

  Future<void> _holdCart(BuildContext context, WidgetRef ref) async {
    final name = await HoldCartDialog.show(context, registerId: registerId);
    if (name != null) {
      final auth = ref.read(authNotifierProvider);
      final cartNotifier = ref.read(cartNotifierProvider.notifier);
      await cartNotifier.suspendCart(
        referenceName: name,
        cashierId: auth.user?.id ?? 'system',
        registerId: registerId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.loc.holdSaleSuccess),
            backgroundColor: AppTheme.warning,
          ),
        );
      }
    }
  }

  void _confirmClearCart(BuildContext context, CartNotifier cartNotifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppDesignTokens.surface,
        title: Text(
          context.loc.clearCart,
          style: const TextStyle(
            color: AppDesignTokens.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          context.loc.clearCartConfirm,
          style: const TextStyle(color: AppDesignTokens.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.loc.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              cartNotifier.clearCart();
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppDesignTokens.danger,
              foregroundColor: Colors.white,
            ),
            child: Text(context.loc.clearCart),
          ),
        ],
      ),
    );
  }

  Future<void> _showDiscountDialog(
    BuildContext context,
    WidgetRef ref,
    CartItem item,
  ) async {
    final controller = TextEditingController();
    int mode = 0; // 0: percentage, 1: fixed amount in millimes

    final discount = await showDialog<Money>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppDesignTokens.surface,
          title: Text(
            '${context.loc.discount} : ${item.productName}',
            style: const TextStyle(
              color: AppDesignTokens.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('% Pourcentage'),
                      selected: mode == 0,
                      onSelected: (_) => setState(() => mode = 0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: Text(context.loc.currencySymbol),
                      selected: mode == 1,
                      onSelected: (_) => setState(() => mode = 1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: const TextStyle(color: AppDesignTokens.textPrimary),
                decoration: InputDecoration(
                  labelText: mode == 0
                      ? 'Pourcentage (%)'
                      : '${context.loc.price} (${context.loc.currencySymbol})',
                  suffixText: mode == 0 ? '%' : context.loc.currencySymbol,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(context.loc.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                final val = double.tryParse(controller.text) ?? 0.0;
                if (val <= 0) {
                  Navigator.of(ctx).pop(Money.zero);
                  return;
                }
                if (mode == 0) {
                  final discMillimes =
                      ((item.unitPrice.millimes * item.quantity) * (val / 100))
                          .round();
                  Navigator.of(ctx).pop(Money.fromMillimes(discMillimes));
                } else {
                  final disc = Money.fromTnd(val);
                  Navigator.of(ctx).pop(disc);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppDesignTokens.primary,
                foregroundColor: Colors.white,
              ),
              child: Text(context.loc.confirm),
            ),
          ],
        ),
      ),
    );

    if (discount != null) {
      ref
          .read(cartNotifierProvider.notifier)
          .applyLineDiscount(item.variantId, discount);
    }
  }

  Future<void> _showGlobalDiscountDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = TextEditingController();
    int mode = 0; // 0: percentage, 1: fixed amount

    final cartState = ref.read(cartNotifierProvider);

    final discount = await showDialog<Money>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppDesignTokens.surface,
          title: Text(
            context.loc.discount,
            style: const TextStyle(
              color: AppDesignTokens.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('% Pourcentage'),
                      selected: mode == 0,
                      onSelected: (_) => setState(() => mode = 0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: Text(context.loc.currencySymbol),
                      selected: mode == 1,
                      onSelected: (_) => setState(() => mode = 1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: const TextStyle(color: AppDesignTokens.textPrimary),
                decoration: InputDecoration(
                  labelText: mode == 0
                      ? 'Pourcentage (%)'
                      : '${context.loc.price} (${context.loc.currencySymbol})',
                  suffixText: mode == 0 ? '%' : context.loc.currencySymbol,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(context.loc.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                final val = double.tryParse(controller.text) ?? 0.0;
                if (val <= 0) {
                  Navigator.of(ctx).pop(Money.zero);
                  return;
                }
                if (mode == 0) {
                  final discMillimes =
                      (cartState.subtotal.millimes * (val / 100)).round();
                  Navigator.of(ctx).pop(Money.fromMillimes(discMillimes));
                } else {
                  final disc = Money.fromTnd(val);
                  Navigator.of(ctx).pop(disc);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppDesignTokens.primary,
                foregroundColor: Colors.white,
              ),
              child: Text(context.loc.confirm),
            ),
          ],
        ),
      ),
    );

    if (discount != null) {
      ref.read(cartNotifierProvider.notifier).applyCartDiscount(discount);
    }
  }
}

class _CartItemTile extends StatelessWidget {
  final CartItem item;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onRemove;
  final VoidCallback onDiscount;

  const _CartItemTile({
    required this.item,
    required this.onQuantityChanged,
    required this.onRemove,
    required this.onDiscount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Quantity Adjuster (+ / - / num)
          Container(
            decoration: BoxDecoration(
              color: AppDesignTokens.surfaceSecondary,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppDesignTokens.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove, size: 14),
                  onPressed: () => onQuantityChanged(item.quantity - 1),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  tooltip: 'Diminuer',
                  color: AppDesignTokens.textSecondary,
                ),
                GestureDetector(
                  onTap: () => _promptQuantity(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '${item.quantity}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 14),
                  onPressed: () => onQuantityChanged(item.quantity + 1),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  tooltip: 'Augmenter',
                  color: AppDesignTokens.textSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Product Description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppDesignTokens.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.variantDescription.isNotEmpty)
                  Text(
                    item.variantDescription,
                    style: const TextStyle(
                      color: AppDesignTokens.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                Row(
                  children: [
                    Text(
                      '${item.unitPrice.format()} /u',
                      style: const TextStyle(
                        color: AppDesignTokens.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    if (item.lineDiscount > Money.zero) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(-${item.lineDiscount.format()})',
                        style: const TextStyle(
                          color: AppDesignTokens.danger,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Total Price for this line
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MoneyDisplay(
                amount: item.total,
                fontSize: 14,
                color: AppDesignTokens.textPrimary,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.percent,
                      size: 14,
                      color: AppDesignTokens.textSecondary,
                    ),
                    onPressed: onDiscount,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    tooltip: 'Remise',
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 14,
                      color: AppDesignTokens.danger,
                    ),
                    onPressed: onRemove,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    tooltip: 'Supprimer',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _promptQuantity(BuildContext context) {
    final controller = TextEditingController(text: '${item.quantity}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppDesignTokens.surface,
        title: Text(
          '${context.loc.quantity} : ${item.productName}',
          style: const TextStyle(
            color: AppDesignTokens.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(color: AppDesignTokens.textPrimary),
          decoration: InputDecoration(labelText: context.loc.quantity),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.loc.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(controller.text) ?? item.quantity;
              onQuantityChanged(val);
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppDesignTokens.primary,
              foregroundColor: Colors.white,
            ),
            child: Text(context.loc.confirm),
          ),
        ],
      ),
    );
  }
}
