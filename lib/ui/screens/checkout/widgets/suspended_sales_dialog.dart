import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/providers/cart_provider.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';
import 'package:jazzpos/ui/widgets/money_display.dart';

class SuspendedSalesDialog extends ConsumerStatefulWidget {
  final String registerId;

  const SuspendedSalesDialog({
    super.key,
    required this.registerId,
  });

  static Future<void> show(BuildContext context, {required String registerId}) {
    return showDialog(
      context: context,
      builder: (ctx) => SuspendedSalesDialog(registerId: registerId),
    );
  }

  @override
  ConsumerState<SuspendedSalesDialog> createState() => _SuspendedSalesDialogState();
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
    final cartState = ref.read(cartNotifierProvider);
    if (cartState.items.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('Panier actuel non vide'),
          content: const Text(
            'Le panier actuel contient des articles. Si vous reprenez cette vente en attente, le panier en cours sera remplacé. Voulez-vous continuer ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
              child: const Text('Remplacer le panier'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Vente "${cart.referenceName}" reprise avec succès'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  Future<void> _deleteCart(SuspendedCart cart) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Supprimer la vente en attente'),
        content: Text('Êtes-vous sûr de vouloir supprimer définitivement "${cart.referenceName}" ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Supprimer'),
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
    final selectedCart = _carts.where((c) => c.id == _selectedCartId).firstOrNull;

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 800,
        height: 520,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.pause_circle_outline, color: AppTheme.warning, size: 28),
                    const SizedBox(width: 12),
                    const Text(
                      'Ventes en Attente (Mise en attente)',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.warning),
                      ),
                      child: Text(
                        '${_carts.length}',
                        style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: AppTheme.border, height: 1),
            const SizedBox(height: 16),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _carts.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inbox_outlined, size: 64, color: AppTheme.textSecondary),
                              SizedBox(height: 12),
                              Text('Aucune vente en attente', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                            ],
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
                                  color: const Color(0xFF161F2E),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.border),
                                ),
                                child: ListView.separated(
                                  itemCount: _carts.length,
                                  separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1),
                                  itemBuilder: (context, index) {
                                    final cart = _carts[index];
                                    final isSelected = cart.id == _selectedCartId;
                                    final cartData = _parseCartData(cart.cartJson);
                                    final itemCount = cartData['itemCount'] as int;
                                    final total = cartData['total'] as Money;
                                    final timeStr = DateFormat('HH:mm - dd/MM').format(cart.createdAt);

                                    return ListTile(
                                      selected: isSelected,
                                      selectedTileColor: AppTheme.primary.withValues(alpha: 0.15),
                                      title: Text(
                                        cart.referenceName.isEmpty ? 'Sans nom' : cart.referenceName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isSelected ? AppTheme.primaryLight : Colors.white,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '$timeStr • $itemCount article(s)',
                                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                      ),
                                      trailing: MoneyDisplay(amount: total, fontSize: 15),
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
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF161F2E),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: AppTheme.border),
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
                cart.referenceName.isEmpty ? 'Vente sans nom' : cart.referenceName,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            MoneyDisplay(amount: total, fontSize: 20),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Créée le ${DateFormat('dd/MM/yyyy à HH:mm:ss').format(cart.createdAt)}',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        const Divider(color: AppTheme.border, height: 16),

        const Text('Articles dans le panier :', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
        const SizedBox(height: 8),

        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('${qty}x', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['productName'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(item['variantDescription'] as String, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                        ],
                      ),
                    ),
                    MoneyDisplay(amount: lineTotal, fontSize: 14),
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
                foregroundColor: AppTheme.error,
                side: const BorderSide(color: AppTheme.error),
                minimumSize: const Size(0, 48),
              ),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Supprimer'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _resumeCart(cart),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                ),
                icon: const Icon(Icons.play_arrow, size: 20),
                label: const Text('Reprendre cette vente', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
      return {
        'items': [],
        'itemCount': 0,
        'total': Money.zero,
      };
    }
  }
}

/// Quick dialog to hold/suspend the current cart
class HoldCartDialog extends StatefulWidget {
  final String registerId;

  const HoldCartDialog({super.key, required this.registerId});

  static Future<String?> show(BuildContext context, {required String registerId}) {
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
          const Text('Donnez un nom ou une référence à cette vente (ex: Nom du client, table, cabine) :'),
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
            Navigator.of(context).pop(text.isEmpty ? 'Vente ${DateFormat('HH:mm').format(DateTime.now())}' : text);
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
          child: const Text('Mettre en attente'),
        ),
      ],
    );
  }
}
