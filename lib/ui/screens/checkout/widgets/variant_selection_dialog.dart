import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/domain/services/catalog_service.dart';
import 'package:jazzpos/providers/cart_provider.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';
import 'package:jazzpos/ui/widgets/money_display.dart';

class VariantSelectionDialog extends ConsumerWidget {
  final String productName;
  final List<VariantSearchResult> variants;

  const VariantSelectionDialog({
    super.key,
    required this.productName,
    required this.variants,
  });

  static Future<void> show(
    BuildContext context, {
    required String productName,
    required List<VariantSearchResult> variants,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => VariantSelectionDialog(productName: productName, variants: variants),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 550,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    productName,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Sélectionnez la taille et la couleur',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            const Divider(color: AppTheme.border),
            const SizedBox(height: 12),

            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: variants.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, index) {
                  final v = variants[index];
                  final isOutOfStock = v.stock <= 0;

                  return InkWell(
                    onTap: () {
                      ref.read(cartNotifierProvider.notifier).addItem(v);
                      Navigator.of(context).pop();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161F2E),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppTheme.primary),
                            ),
                            child: Text(
                              v.variantDescription,
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('SKU: ${v.sku}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                                Text('Code: ${v.barcode}', style: const TextStyle(fontSize: 11, color: Colors.white38)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              MoneyDisplay(amount: v.salePrice, fontSize: 16),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isOutOfStock ? Colors.red.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isOutOfStock ? 'Rupture' : '${v.stock} en stock',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isOutOfStock ? Colors.redAccent : Colors.greenAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
