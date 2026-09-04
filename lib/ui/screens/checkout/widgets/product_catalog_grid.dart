import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/domain/services/catalog_service.dart';
import 'package:jazzpos/providers/cart_provider.dart';
import 'package:jazzpos/providers/catalog_provider.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';
import 'package:jazzpos/ui/widgets/money_display.dart';
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

  void _onProductTap(BuildContext context, String productName, List<VariantSearchResult> variants) {
    if (variants.isEmpty) return;

    if (variants.length == 1) {
      // Direct add to cart!
      ref.read(cartNotifierProvider.notifier).addItem(variants.first);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ajouté : ${variants.first.productName}'),
          duration: const Duration(milliseconds: 900),
          backgroundColor: AppTheme.success,
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
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: [
              // Search Input
              TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Rechercher article, code-barres, référence (F3)...',
                  prefixIcon: const Icon(Icons.search, color: AppTheme.primaryLight),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: AppTheme.textSecondary, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            catalogNotifier.search('');
                          },
                        )
                      : const Icon(Icons.qr_code_scanner, color: AppTheme.textSecondary),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: (val) => catalogNotifier.search(val),
              ),

              // Category Filter Chips
              if (catalogState.categories.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: const Text('Tous'),
                          selected: catalogState.selectedCategoryId == null,
                          onSelected: (_) => catalogNotifier.selectCategory(null),
                        ),
                      ),
                      ...catalogState.categories.map((cat) {
                        final isSelected = catalogState.selectedCategoryId == cat.id;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(cat.name),
                            selected: isSelected,
                            onSelected: (_) => catalogNotifier.selectCategory(cat.id),
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
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.4)),
                          const SizedBox(height: 12),
                          const Text(
                            'Aucun article trouvé',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                          ),
                          if (_searchController.text.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                _searchController.clear();
                                catalogNotifier.search('');
                              },
                              child: const Text('Effacer la recherche'),
                            ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        // Responsive cross axis count based on available width
                        final crossAxisCount = (constraints.maxWidth / 190).floor().clamp(2, 6);

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
                            final minPrice = variants.map((v) => v.salePrice).reduce((a, b) => a < b ? a : b);
                            final maxPrice = variants.map((v) => v.salePrice).reduce((a, b) => a > b ? a : b);
                            final totalStock = variants.fold(0, (sum, v) => sum + v.stock);

                            return InkWell(
                              onTap: () => _onProductTap(context, productName, variants),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppTheme.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppTheme.border),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Top row: Variant count badge & stock
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: variants.length > 1
                                                ? AppTheme.primary.withValues(alpha: 0.2)
                                                : Colors.white.withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(
                                              color: variants.length > 1 ? AppTheme.primary : AppTheme.border,
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Text(
                                            variants.length > 1 ? '${variants.length} var.' : 'Unique',
                                            style: TextStyle(
                                              color: variants.length > 1 ? AppTheme.primaryLight : AppTheme.textSecondary,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: totalStock > 0
                                                ? AppTheme.success.withValues(alpha: 0.15)
                                                : AppTheme.error.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Stock: $totalStock',
                                            style: TextStyle(
                                              color: totalStock > 0 ? AppTheme.success : AppTheme.error,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    const Spacer(),

                                    // Product Name
                                    Text(
                                      productName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Colors.white,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),

                                    const SizedBox(height: 4),

                                    // SKU / barcode subtitle
                                    Text(
                                      firstVar.barcode.isNotEmpty ? firstVar.barcode : firstVar.sku,
                                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),

                                    const SizedBox(height: 6),

                                    // Price Display
                                    if (minPrice == maxPrice)
                                      MoneyDisplay(amount: minPrice, fontSize: 16)
                                    else
                                      Text(
                                        '${minPrice.format()} - ${maxPrice.format()}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: AppTheme.primaryLight,
                                        ),
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
