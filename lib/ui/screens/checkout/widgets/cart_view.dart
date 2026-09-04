import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/domain/models/cart_item.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/providers/cart_provider.dart';
import 'package:jazzpos/providers/shift_provider.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';
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
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          // Cart Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.shopping_cart_outlined,
                      color: AppTheme.primaryLight,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Panier en cours',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${cartState.totalItemsCount} pièce(s)',
                        style: const TextStyle(
                          color: AppTheme.primaryLight,
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
                      color: AppTheme.error,
                    ),
                    label: const Text(
                      'Vider (F7)',
                      style: TextStyle(color: AppTheme.error, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),

          // Customer Tag Bar if selected
          if (cartState.customer != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppTheme.primary.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const Icon(
                    Icons.person,
                    size: 16,
                    color: AppTheme.primaryLight,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Client: ${cartState.customer!.name} (${cartState.customer!.phone ?? "Sans tél"})',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 16,
                      color: AppTheme.textSecondary,
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
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_bag_outlined,
                          size: 56,
                          color: AppTheme.textSecondary.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Panier vide',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Scannez un code-barres ou sélectionnez un article',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: cartState.items.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: AppTheme.border, height: 1),
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
              color: Color(0xFF161F2E),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: Column(
              children: [
                // Totals breakdown
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Sous-total:',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    MoneyDisplay(amount: cartState.subtotal, fontSize: 16),
                  ],
                ),
                if (cartState.cartDiscount > Money.zero) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Remise globale:',
                            style: TextStyle(
                              color: AppTheme.error,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              size: 14,
                              color: AppTheme.error,
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
                          color: AppTheme.error,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
                const Divider(color: AppTheme.border, height: 16),

                // Grand Total
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOTAL A PAYER',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'TTC inclus',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    MoneyDisplay(
                      amount: cartState.total,
                      fontSize: 28,
                      color: AppTheme.success,
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
                          minimumSize: const Size(0, 42),
                          side: const BorderSide(color: AppTheme.border),
                        ),
                        icon: const Icon(
                          Icons.pause,
                          size: 16,
                          color: AppTheme.warning,
                        ),
                        label: const Text(
                          'Attente (F6)',
                          style: TextStyle(fontSize: 12),
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
                          minimumSize: const Size(0, 42),
                          side: const BorderSide(color: AppTheme.border),
                        ),
                        icon: const Icon(
                          Icons.percent,
                          size: 16,
                          color: Colors.amber,
                        ),
                        label: const Text(
                          'Remise',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Pay Button (F12)
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: (cartState.items.isEmpty || shift == null)
                        ? null
                        : () => _openPaymentDialog(context, cartState.total),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.border,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 4,
                    ),
                    icon: const Icon(Icons.payment, size: 24),
                    label: Text(
                      shift == null
                          ? 'OUVRIR CAISSE REQUISE'
                          : 'ENCAISSER (F12)',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
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
            content: Text('Vente "$name" mise en attente'),
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
        backgroundColor: AppTheme.surface,
        title: const Text('Vider le panier'),
        content: const Text(
          'Êtes-vous sûr de vouloir supprimer tous les articles du panier ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              cartNotifier.clearCart();
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Vider le panier'),
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
          backgroundColor: AppTheme.surface,
          title: Text('Remise sur ${item.productName}'),
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
                      label: const Text('Montant TND'),
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
                decoration: InputDecoration(
                  labelText: mode == 0 ? 'Pourcentage (%)' : 'Montant en TND',
                  suffixText: mode == 0 ? '%' : 'TND',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
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
              child: const Text('Appliquer'),
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
          backgroundColor: AppTheme.surface,
          title: const Text('Remise globale sur le panier'),
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
                      label: const Text('Montant TND'),
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
                decoration: InputDecoration(
                  labelText: mode == 0 ? 'Pourcentage (%)' : 'Montant en TND',
                  suffixText: mode == 0 ? '%' : 'TND',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
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
              child: const Text('Appliquer'),
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
              color: const Color(0xFF161F2E),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove, size: 14),
                  onPressed: () => onQuantityChanged(item.quantity - 1),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  tooltip: 'Diminuer',
                ),
                GestureDetector(
                  onTap: () => _promptQuantity(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '${item.quantity}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 14),
                  onPressed: () => onQuantityChanged(item.quantity + 1),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  tooltip: 'Augmenter',
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

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
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.variantDescription.isNotEmpty)
                  Text(
                    item.variantDescription,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                Row(
                  children: [
                    Text(
                      '${item.unitPrice.format()} /u',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    if (item.lineDiscount > Money.zero) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(-${item.lineDiscount.format()})',
                        style: const TextStyle(
                          color: AppTheme.error,
                          fontSize: 11,
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
              MoneyDisplay(amount: item.total, fontSize: 15),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.percent,
                      size: 14,
                      color: AppTheme.textSecondary,
                    ),
                    onPressed: onDiscount,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    tooltip: 'Remise sur la ligne',
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 14,
                      color: AppTheme.error,
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
        backgroundColor: AppTheme.surface,
        title: Text('Modifier quantité: ${item.productName}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nouvelle quantité'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(controller.text) ?? item.quantity;
              onQuantityChanged(val);
              Navigator.of(ctx).pop();
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }
}
