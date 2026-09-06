import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/domain/services/catalog_service.dart';
import 'package:jazzpos/providers/cart_provider.dart';
import 'package:jazzpos/providers/catalog_provider.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'package:jazzpos/ui/widgets/common/app_empty_state.dart';
import 'package:jazzpos/ui/widgets/common/app_status_badge.dart';
import 'package:jazzpos/ui/widgets/common/price_text.dart';
import 'package:jazzpos/ui/widgets/common/product_thumbnail.dart';
import 'variant_selection_dialog.dart';

class ProductCatalogGrid extends ConsumerStatefulWidget {
  const ProductCatalogGrid({super.key});

  @override
  ConsumerState<ProductCatalogGrid> createState() => _ProductCatalogGridState();
}

class _ProductCatalogGridState extends ConsumerState<ProductCatalogGrid> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onProductTap(
    BuildContext context,
    String productName,
    List<VariantSearchResult> variants,
  ) {
    if (variants.isEmpty) return;

    if (variants.length == 1) {
      // Direct add to cart!
      ref.read(cartNotifierProvider.notifier).addItem(variants.first);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.loc.barcodeScannedSuccess} : ${variants.first.productName}',
          ),
          duration: const Duration(milliseconds: 900),
          backgroundColor: AppDesignTokens.success,
        ),
      );
    } else {
      // Multiple variants: open size/color picker
      VariantSelectionDialog.show(
        context,
        productName: productName,
        variants: variants,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogState = ref.watch(catalogNotifierProvider);
    final catalogNotifier = ref.read(catalogNotifierProvider.notifier);

    // Group variants by productId
    final Map<String, List<VariantSearchResult>> groupedByProduct = {};
    for (final v in catalogState.variants) {
      groupedByProduct.putIfAbsent(v.productId, () => []).add(v);
    }

    final productGroups = groupedByProduct.entries.toList();

    return Column(
      children: [
        // Search and Category Bar
        Container(
          padding: const EdgeInsets.all(AppDesignTokens.space12),
          decoration: BoxDecoration(
            color: AppDesignTokens.surface,
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusLg),
            border: Border.all(color: AppDesignTokens.border),
            boxShadow: AppDesignTokens.shadowSm,
          ),
          child: Column(
            children: [
              // Search Input
              TextField(
                controller: _searchController,
                style: const TextStyle(
                  color: AppDesignTokens.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: context.loc.searchProductOrBarcode,
                  hintStyle: const TextStyle(color: AppDesignTokens.textMuted),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppDesignTokens.primary,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear,
                            color: AppDesignTokens.textSecondary,
                            size: 18,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            catalogNotifier.search('');
                          },
                        )
                      : const Icon(
                          Icons.qr_code_scanner,
                          color: AppDesignTokens.textSecondary,
                        ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: (val) => catalogNotifier.search(val),
              ),

              // Category Filter Chips
              if (catalogState.categories.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(context.loc.allCategories),
                          selected: catalogState.selectedCategoryId == null,
                          onSelected: (_) =>
                              catalogNotifier.selectCategory(null),
                          selectedColor: AppDesignTokens.primary,
                          labelStyle: TextStyle(
                            color: catalogState.selectedCategoryId == null
                                ? Colors.white
                                : AppDesignTokens.textPrimary,
                            fontWeight: catalogState.selectedCategoryId == null
                                ? FontWeight.w600
                                : FontWeight.normal,
                            fontSize: 12,
                          ),
                          backgroundColor: AppDesignTokens.surfaceSecondary,
                          side: BorderSide(
                            color: catalogState.selectedCategoryId == null
                                ? AppDesignTokens.primary
                                : AppDesignTokens.border,
                          ),
                        ),
                      ),
                      ...catalogState.categories.map((cat) {
                        final isSelected =
                            catalogState.selectedCategoryId == cat.id;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(context.loc.categoryName(cat.name)),
                            selected: isSelected,
                            onSelected: (_) =>
                                catalogNotifier.selectCategory(cat.id),
                            selectedColor: AppDesignTokens.primary,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : AppDesignTokens.textPrimary,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              fontSize: 12,
                            ),
                            backgroundColor: AppDesignTokens.surfaceSecondary,
                            side: BorderSide(
                              color: isSelected
                                  ? AppDesignTokens.primary
                                  : AppDesignTokens.border,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Products Grid
        Expanded(
          child: catalogState.isLoading
              ? const Center(child: CircularProgressIndicator())
              : productGroups.isEmpty
              ? AppEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: context.loc.none,
                  subtitle: context.loc.searchProductOrBarcode,
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    // Responsive cross axis count based on available width
                    final crossAxisCount = (constraints.maxWidth / 190)
                        .floor()
                        .clamp(2, 6);

                    return GridView.builder(
                      padding: EdgeInsets.zero,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.88,
                      ),
                      itemCount: productGroups.length,
                      itemBuilder: (context, index) {
                        final entry = productGroups[index];
                        final variants = entry.value;
                        final firstVar = variants.first;
                        final productName = firstVar.productName;
                        final minPrice = variants
                            .map((v) => v.salePrice)
                            .reduce((a, b) => a < b ? a : b);
                        final maxPrice = variants
                            .map((v) => v.salePrice)
                            .reduce((a, b) => a > b ? a : b);
                        final totalStock = variants.fold(
                          0,
                          (sum, v) => sum + v.stock,
                        );

                        return InkWell(
                          onTap: () =>
                              _onProductTap(context, productName, variants),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppDesignTokens.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppDesignTokens.border),
                              boxShadow: AppDesignTokens.shadowSm,
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Top row: Thumbnail & badges
                                Row(
                                  children: [
                                    ProductThumbnail(
                                      imageUrl: firstVar.imageUrl,
                                      size: 38,
                                    ),
                                    const Spacer(),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        if (variants.length > 1)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 4,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEFF6FF),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: const Color(0xFFBFDBFE),
                                                width: 0.5,
                                              ),
                                            ),
                                            child: Text(
                                              '${variants.length} var.',
                                              style: const TextStyle(
                                                color: AppDesignTokens.primary,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        AppStatusBadge.forStock(
                                          stock: totalStock,
                                          isCompact: true,
                                          loc: context.loc,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),

                                const Spacer(),

                                // Product Name
                                Text(
                                  productName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: AppDesignTokens.textPrimary,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),

                                const SizedBox(height: 3),

                                // SKU / barcode subtitle
                                Text(
                                  firstVar.barcode.isNotEmpty
                                      ? firstVar.barcode
                                      : firstVar.sku,
                                  style: const TextStyle(
                                    color: AppDesignTokens.textSecondary,
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),

                                const SizedBox(height: 6),

                                // Price Display
                                if (minPrice == maxPrice)
                                  PriceText(money: minPrice, fontSize: 14)
                                else
                                  Row(
                                    children: [
                                      PriceText(money: minPrice, fontSize: 12),
                                      const Text(
                                        ' - ',
                                        style: TextStyle(
                                          color: AppDesignTokens.textSecondary,
                                          fontSize: 11,
                                        ),
                                      ),
                                      PriceText(money: maxPrice, fontSize: 12),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
