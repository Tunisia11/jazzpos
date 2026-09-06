import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/localization/app_localizations.dart';
import 'package:jazzpos/domain/services/catalog_service.dart';
import 'package:jazzpos/providers/cart_provider.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
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
      builder: (ctx) =>
          VariantSelectionDialog(productName: productName, variants: variants),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = context.loc;

    return Dialog(
      backgroundColor: AppDesignTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusXl),
      ),
      child: Container(
        width: 550,
        padding: const EdgeInsets.all(AppDesignTokens.space24),
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
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppDesignTokens.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              loc.selectVariantSubtitle,
              style: const TextStyle(
                fontSize: 13,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            const Divider(color: AppDesignTokens.border, height: 1),
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
                    borderRadius: BorderRadius.circular(
                      AppDesignTokens.radiusMd,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppDesignTokens.surfaceSecondary,
                        borderRadius: BorderRadius.circular(
                          AppDesignTokens.radiusMd,
                        ),
                        border: Border.all(color: AppDesignTokens.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFFBFDBFE),
                              ),
                            ),
                            child: Text(
                              v.variantDescription,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppDesignTokens.primary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SKU: ${v.sku}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppDesignTokens.textSecondary,
                                  ),
                                ),
                                if (v.barcode.isNotEmpty)
                                  Text(
                                    '${loc.barcode}: ${v.barcode}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppDesignTokens.textMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              MoneyDisplay(
                                amount: v.salePrice,
                                fontSize: 15,
                                color: AppDesignTokens.textPrimary,
                              ),
                              const SizedBox(height: 3),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isOutOfStock
                                      ? AppDesignTokens.dangerBg
                                      : AppDesignTokens.successBg,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isOutOfStock
                                      ? loc.outOfStock
                                      : loc.unitsInStock(v.stock),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isOutOfStock
                                        ? AppDesignTokens.dangerText
                                        : AppDesignTokens.successText,
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
