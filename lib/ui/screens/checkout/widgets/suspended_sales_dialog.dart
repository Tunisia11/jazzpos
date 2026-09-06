import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/providers/cart_provider.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';
import 'package:jazzpos/ui/widgets/common/app_empty_state.dart';
import 'package:jazzpos/ui/widgets/money_display.dart';

class SuspendedSalesDialog extends ConsumerStatefulWidget {
  final String registerId;

  const SuspendedSalesDialog({super.key, required this.registerId});

  static Future<void> show(BuildContext context, {required String registerId}) {
    return showDialog(
      context: context,
      builder: (ctx) => SuspendedSalesDialog(registerId: registerId),
    );
  }

  @override
  ConsumerState<SuspendedSalesDialog> createState() =>
      _SuspendedSalesDialogState();
}

class _SuspendedSalesDialogState extends ConsumerState<SuspendedSalesDialog> {
  List<SuspendedCart> _carts = [];
  bool _isLoading = true;
  String? _selectedCartId;

  @override
  void initState() {
    super.initState();
    _loadCarts();
  }

  Future<void> _loadCarts() async {
    setState(() => _isLoading = true);
    final saleService = ref.read(saleServiceProvider);
    final carts = await saleService.getSuspendedCarts(widget.registerId);
    setState(() {
      _carts = carts;
      _isLoading = false;
      if (_carts.isNotEmpty && _selectedCartId == null) {
        _selectedCartId = _carts.first.id;
      }
    });
  }

  Future<void> _resumeCart(SuspendedCart cart) async {
    final loc = context.loc;
    final cartState = ref.read(cartNotifierProvider);
    if (cartState.items.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppDesignTokens.surface,
          title: Text(
            loc.cartNotEmptyTitle,
            style: const TextStyle(
              color: AppDesignTokens.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            loc.cartNotEmptyBody,
            style: const TextStyle(color: AppDesignTokens.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(loc.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppDesignTokens.warning,
                foregroundColor: Colors.white,
              ),
              child: Text(loc.replaceCart),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    final cartNotifier = ref.read(cartNotifierProvider.notifier);
    final saleService = ref.read(saleServiceProvider);

    cartNotifier.resumeCart(cart);
    await saleService.deleteSuspendedCart(cart.id);

    if (mounted) {
      Navigator.of(context).pop();
      final name = cart.referenceName.isEmpty
          ? loc.unnamedSale
          : cart.referenceName;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name: ${loc.holdSaleSuccess}'),
          backgroundColor: AppDesignTokens.success,
        ),
      );
    }
  }

  Future<void> _deleteCart(SuspendedCart cart) async {
    final loc = context.loc;
    final name = cart.referenceName.isEmpty
        ? loc.unnamedSale
        : cart.referenceName;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppDesignTokens.surface,
        title: Text(
          loc.deleteSuspendedSaleTitle,
          style: const TextStyle(
            color: AppDesignTokens.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          loc.deleteSuspendedSaleBody(name),
          style: const TextStyle(color: AppDesignTokens.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(loc.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppDesignTokens.danger,
              foregroundColor: Colors.white,
            ),
            child: Text(loc.delete),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final saleService = ref.read(saleServiceProvider);
    await saleService.deleteSuspendedCart(cart.id);
    _loadCarts();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final selectedCart = _carts
        .where((c) => c.id == _selectedCartId)
        .firstOrNull;

    return Dialog(
      backgroundColor: AppDesignTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusXl),
      ),
      child: Container(
        width: 800,
        height: 520,
        padding: const EdgeInsets.all(AppDesignTokens.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.pause_circle_outline,
                      color: AppDesignTokens.warning,
                      size: 26,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      loc.suspendedSales,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
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
                        color: AppDesignTokens.warningBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppDesignTokens.warning.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        '${_carts.length}',
                        style: const TextStyle(
                          color: AppDesignTokens.warningText,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: AppDesignTokens.textSecondary,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(color: AppDesignTokens.border, height: 1),
            const SizedBox(height: 14),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _carts.isEmpty
                  ? Center(
                      child: AppEmptyState(
                        icon: Icons.inbox_outlined,
                        title: loc.noSuspendedSales,
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left list of suspended carts
                        Expanded(
                          flex: 5,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppDesignTokens.surfaceSecondary,
                              borderRadius: BorderRadius.circular(
                                AppDesignTokens.radiusMd,
                              ),
                              border: Border.all(color: AppDesignTokens.border),
                            ),
                            child: ListView.separated(
                              itemCount: _carts.length,
                              separatorBuilder: (_, __) => const Divider(
                                color: AppDesignTokens.border,
                                height: 1,
                              ),
                              itemBuilder: (context, index) {
                                final cart = _carts[index];
                                final isSelected = cart.id == _selectedCartId;
                                final cartData = _parseCartData(cart.cartJson);
                                final itemCount = cartData['itemCount'] as int;
                                final total = cartData['total'] as Money;
                                final timeStr = DateFormat(
                                  'HH:mm - dd/MM',
                                ).format(cart.createdAt);

                                return ListTile(
                                  selected: isSelected,
                                  selectedTileColor: const Color(0xFFEFF6FF),
                                  title: Text(
                                    cart.referenceName.isEmpty
                                        ? loc.unnamedSale
                                        : cart.referenceName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? AppDesignTokens.primary
                                          : AppDesignTokens.textPrimary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '$timeStr • ${loc.nArticles(itemCount)}',
                                    style: const TextStyle(
                                      color: AppDesignTokens.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: MoneyDisplay(
                                    amount: total,
                                    fontSize: 14,
                                    color: isSelected
                                        ? AppDesignTokens.primary
                                        : AppDesignTokens.textPrimary,
                                  ),
                                  onTap: () {
                                    setState(() => _selectedCartId = cart.id);
                                  },
                                );
                              },
                            ),
                          ),
                        ),

                        const SizedBox(width: 16),

                        // Right details pane
                        Expanded(
                          flex: 6,
                          child: selectedCart == null
                              ? const SizedBox.shrink()
                              : Container(
                                  padding: const EdgeInsets.all(
                                    AppDesignTokens.space16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppDesignTokens.surfaceSecondary,
                                    borderRadius: BorderRadius.circular(
                                      AppDesignTokens.radiusMd,
                                    ),
                                    border: Border.all(
                                      color: AppDesignTokens.border,
                                    ),
                                  ),
                                  child: _buildDetailsPane(selectedCart),
                                ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsPane(SuspendedCart cart) {
    final loc = context.loc;
    final cartData = _parseCartData(cart.cartJson);
    final items = cartData['items'] as List;
    final total = cartData['total'] as Money;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                cart.referenceName.isEmpty
                    ? loc.unnamedSale
                    : cart.referenceName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppDesignTokens.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            MoneyDisplay(
              amount: total,
              fontSize: 18,
              color: AppDesignTokens.textPrimary,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${loc.date}: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(cart.createdAt)}',
          style: const TextStyle(
            color: AppDesignTokens.textSecondary,
            fontSize: 12,
          ),
        ),
        const Divider(color: AppDesignTokens.border, height: 16),

        Text(
          '${loc.cart}:',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 8),

        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) =>
                const Divider(color: AppDesignTokens.border, height: 1),
            itemBuilder: (context, index) {
              final item = items[index] as Map<String, dynamic>;
              final qty = item['quantity'] as int;
              final unitPrice = Money.fromMillimes(item['unitPrice'] as int);
              final lineTotal = unitPrice * qty;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${qty}x',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppDesignTokens.primary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['productName'] as String,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppDesignTokens.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                          if ((item['variantDescription'] as String?)
                                  ?.isNotEmpty ==
                              true)
                            Text(
                              item['variantDescription'] as String,
                              style: const TextStyle(
                                color: AppDesignTokens.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    MoneyDisplay(
                      amount: lineTotal,
                      fontSize: 13,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => _deleteCart(cart),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppDesignTokens.danger,
                side: const BorderSide(color: AppDesignTokens.danger),
                minimumSize: const Size(0, 44),
              ),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(loc.delete),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _resumeCart(cart),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppDesignTokens.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 44),
                ),
                icon: const Icon(Icons.play_arrow, size: 20),
                label: Text(
                  loc.resumeThisSale,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Map<String, dynamic> _parseCartData(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final items = (map['items'] as List? ?? []);
      int totalMillimes = 0;
      int totalCount = 0;
      for (final item in items) {
        final q = (item['quantity'] as int? ?? 1);
        final p = (item['unitPrice'] as int? ?? 0);
        final disc = (item['lineDiscount'] as int? ?? 0);
        totalMillimes += (p * q) - disc;
        totalCount += q;
      }
      final cartDisc = (map['cartDiscount'] as int? ?? 0);
      totalMillimes -= cartDisc;
      if (totalMillimes < 0) totalMillimes = 0;

      return {
        'items': items,
        'itemCount': totalCount,
        'total': Money.fromMillimes(totalMillimes),
      };
    } catch (_) {
      return {'items': [], 'itemCount': 0, 'total': Money.zero};
    }
  }
}

/// Quick dialog to hold/suspend the current cart
class HoldCartDialog extends StatefulWidget {
  final String registerId;

  const HoldCartDialog({super.key, required this.registerId});

  static Future<String?> show(
    BuildContext context, {
    required String registerId,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => HoldCartDialog(registerId: registerId),
    );
  }

  @override
  State<HoldCartDialog> createState() => _HoldCartDialogState();
}

class _HoldCartDialogState extends State<HoldCartDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Row(
        children: [
          Icon(Icons.pause_circle_outline, color: AppTheme.warning),
          SizedBox(width: 8),
          Text('Mettre la vente en attente'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Donnez un nom ou une référence à cette vente (ex: Nom du client, table, cabine) :',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Ex: Client chemise bleue / Cabine 2',
              prefixIcon: Icon(Icons.label_outline),
            ),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                Navigator.of(context).pop(value.trim());
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: () {
            final text = _controller.text.trim();
            Navigator.of(context).pop(
              text.isEmpty
                  ? 'Vente ${DateFormat('HH:mm').format(DateTime.now())}'
                  : text,
            );
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
          child: const Text('Mettre en attente'),
        ),
      ],
    );
  }
}
