import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracepos/core/localization/app_localizations_delegate.dart';
import 'package:tracepos/core/money/money.dart';
import 'package:tracepos/domain/models/cart_item.dart';
import 'package:tracepos/providers/auth_provider.dart';
import 'package:tracepos/providers/cart_provider.dart';
import 'package:tracepos/providers/shift_provider.dart';
import 'package:tracepos/ui/theme/app_design_tokens.dart';
import 'package:tracepos/ui/theme/app_theme.dart';
import 'package:tracepos/ui/widgets/common/app_button.dart';
import 'package:tracepos/ui/widgets/common/app_empty_state.dart';
import 'package:tracepos/ui/widgets/common/product_thumbnail.dart';
import 'package:tracepos/ui/widgets/money_display.dart';
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
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusXl),
        border: Border.all(color: AppDesignTokens.border),
        boxShadow: AppDesignTokens.shadowSm,
      ),
      child: Column(
        children: [
          // Cart header: icon, title, count chip, clear button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.shopping_cart_outlined,
                  color: AppDesignTokens.info,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Text(
                  context.loc.cart,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FE),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    context.loc.itemsInCart(cartState.totalItemsCount),
                    style: const TextStyle(
                      color: AppDesignTokens.info,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                if (cartState.items.isNotEmpty)
                  Tooltip(
                    message: context.loc.clearCart,
                    child: InkWell(
                      onTap: () => _confirmClearCart(context, cartNotifier),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppDesignTokens.dangerBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: AppDesignTokens.danger,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Customer tag bar if selected
          if (cartState.customer != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: AppDesignTokens.primarySoft,
                border: Border(
                  bottom: BorderSide(color: AppDesignTokens.primarySoftBorder),
                ),
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

          // Items + note (scrolls together when the cart is long)
          Expanded(
            child: cartState.items.isEmpty
                ? AppEmptyState(
                    icon: Icons.shopping_bag_outlined,
                    title: context.loc.cartEmpty,
                    subtitle: context.loc.cartEmptySubtitle,
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final item in cartState.items) ...[
                        _CartItemTile(
                          item: item,
                          onQuantityChanged: (qty) =>
                              cartNotifier.updateQuantity(item.variantId, qty),
                          onRemove: () =>
                              cartNotifier.removeItem(item.variantId),
                          onDiscount: () =>
                              _showDiscountDialog(context, ref, item),
                        ),
                        const Divider(
                          color: AppDesignTokens.borderSubtle,
                          height: 1,
                        ),
                      ],
                      const SizedBox(height: 14),
                      _CartNoteField(
                        value: cartState.note,
                        onChanged: cartNotifier.setNote,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
          ),

          // Summary
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppDesignTokens.border)),
            ),
            child: Column(
              children: [
                _SummaryRow(
                  label: context.loc.subtotal,
                  value: cartState.subtotal.format(),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: cartState.items.isEmpty
                      ? null
                      : () => _showGlobalDiscountDialog(context, ref),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppDesignTokens.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.percent,
                          size: 18,
                          color: AppDesignTokens.textSecondary,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          context.loc.discount,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          cartState.cartDiscount > Money.zero
                              ? '-${cartState.cartDiscount.format()}'
                              : cartState.cartDiscount.format(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: cartState.cartDiscount > Money.zero
                                ? AppDesignTokens.danger
                                : AppDesignTokens.textPrimary,
                          ),
                        ),
                        if (cartState.cartDiscount > Money.zero) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () =>
                                cartNotifier.applyCartDiscount(Money.zero),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: AppDesignTokens.danger,
                            ),
                          ),
                        ] else
                          const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: AppDesignTokens.textSecondary,
                          ),
                      ],
                    ),
                  ),
                ),
                if (cartState.tax > Money.zero) ...[
                  const SizedBox(height: 10),
                  _SummaryRow(
                    label: 'TVA incluse',
                    value: cartState.tax.format(),
                  ),
                ],
                const SizedBox(height: 12),

                // Grand total panel
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppDesignTokens.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
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
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: MoneyDisplay(
                            amount: cartState.total,
                            fontSize: 26,
                            color: AppDesignTokens.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Hold (F6) and discount
                Row(
                  children: [
                    Expanded(
                      child: _SecondaryAction(
                        icon: Icons.pause,
                        label: context.loc.holdSale.replaceAll(
                          RegExp(r'\s*\(F6\)'),
                          '',
                        ),
                        hint: 'F6',
                        onPressed: cartState.items.isEmpty
                            ? null
                            : () => _holdCart(context, ref),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SecondaryAction(
                        icon: Icons.percent,
                        label: context.loc.discount,
                        onPressed: cartState.items.isEmpty
                            ? null
                            : () => _showGlobalDiscountDialog(context, ref),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Pay button (F12)
                AppButton(
                  label: shift == null
                      ? context.loc.clickToOpenRegister
                      : context.loc.payAction,
                  variant: AppButtonVariant.cta,
                  height: 54,
                  isExpanded: true,
                  icon: shift == null ? Icons.lock_open : Icons.credit_card,
                  shortcutHint: shift == null ? null : 'F12',
                  onPressed: shift == null
                      ? () => _openShiftPrompt(context, ref)
                      : (cartState.items.isEmpty
                            ? null
                            : () => _openPaymentDialog(context, cartState.total)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openShiftPrompt(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: '150.000');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppDesignTokens.surface,
        title: Text(
          context.loc.openRegisterTitle,
          style: const TextStyle(
            color: AppDesignTokens.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${context.loc.initialCashFloat} :',
              style: const TextStyle(color: AppDesignTokens.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
              style: const TextStyle(color: AppDesignTokens.textPrimary),
              decoration: InputDecoration(
                prefixIcon: const Icon(
                  Icons.account_balance_wallet,
                  color: AppDesignTokens.primary,
                ),
                suffixText: context.loc.currencySymbol,
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
            onPressed: () async {
              final val = double.tryParse(controller.text) ?? 0.0;
              final auth = ref.read(authNotifierProvider);
              try {
                await ref
                    .read(shiftNotifierProvider.notifier)
                    .openShift(
                      registerId: registerId,
                      cashierId: auth.user?.id ?? 'system',
                      openingCash: Money.fromTnd(val),
                    );
                if (ctx.mounted) Navigator.of(ctx).pop();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erreur: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppDesignTokens.success,
              foregroundColor: Colors.white,
            ),
            child: Text(context.loc.openRegisterAction),
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

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppDesignTokens.textSecondary,
            fontSize: 14,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppDesignTokens.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? hint;
  final VoidCallback? onPressed;
  const _SecondaryAction({
    required this.icon,
    required this.label,
    this.hint,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        backgroundColor: AppDesignTokens.surface,
        side: const BorderSide(color: AppDesignTokens.border),
        foregroundColor: AppDesignTokens.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: AppDesignTokens.accentOrange),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppDesignTokens.surfaceHighlight,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                hint!,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Optional sale note; edits flow into [CartState.note].
class _CartNoteField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _CartNoteField({required this.value, required this.onChanged});

  @override
  State<_CartNoteField> createState() => _CartNoteFieldState();
}

class _CartNoteFieldState extends State<_CartNoteField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(covariant _CartNoteField old) {
    super.didUpdateWidget(old);
    // Cart was reset (after checkout / clear): mirror it.
    if (widget.value != _controller.text) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(
              Icons.edit_note,
              size: 20,
              color: AppDesignTokens.textSecondary,
            ),
            SizedBox(width: 8),
            Text(
              'Ajouter une note (optionnel)',
              style: TextStyle(
                fontSize: 13,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          onChanged: widget.onChanged,
          minLines: 2,
          maxLines: 3,
          maxLength: 200,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Note de vente, client, ...',
            counterText: '',
            filled: true,
            fillColor: AppDesignTokens.surface,
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppDesignTokens.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppDesignTokens.border),
            ),
          ),
        ),
      ],
    );
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

  Widget _stepButton(IconData icon, VoidCallback onTap, String tooltip) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Tooltip(
        message: tooltip,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 16, color: AppDesignTokens.textPrimary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = [
      if (item.variantDescription.isNotEmpty &&
          item.variantDescription != 'Standard')
        item.variantDescription,
      if (item.sku.isNotEmpty) item.sku,
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 64,
              height: 72,
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: ProductThumbnail(
                  imageUrl: item.imageUrl,
                  size: 72,
                  borderRadius: 0,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.productName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppDesignTokens.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.total.format(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                  ],
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: AppDesignTokens.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (item.lineDiscount > Money.zero)
                  Text(
                    'Remise -${item.lineDiscount.format()}',
                    style: const TextStyle(
                      color: AppDesignTokens.danger,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AppDesignTokens.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppDesignTokens.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _stepButton(
                            Icons.remove,
                            () => onQuantityChanged(item.quantity - 1),
                            'Diminuer',
                          ),
                          GestureDetector(
                            onTap: () => _promptQuantity(context),
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 40),
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                border: Border.symmetric(
                                  vertical: BorderSide(
                                    color: AppDesignTokens.border,
                                  ),
                                ),
                              ),
                              height: 34,
                              child: Text(
                                '${item.quantity}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppDesignTokens.textPrimary,
                                ),
                              ),
                            ),
                          ),
                          _stepButton(
                            Icons.add,
                            () => onQuantityChanged(item.quantity + 1),
                            'Augmenter',
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: onDiscount,
                      borderRadius: BorderRadius.circular(8),
                      child: const Tooltip(
                        message: 'Remise',
                        child: SizedBox(
                          width: 34,
                          height: 34,
                          child: Icon(
                            Icons.percent,
                            size: 16,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: onRemove,
                      borderRadius: BorderRadius.circular(8),
                      child: Tooltip(
                        message: 'Supprimer',
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppDesignTokens.border),
                          ),
                          child: const Icon(
                            Icons.delete_outline,
                            size: 17,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
