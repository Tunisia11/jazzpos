import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracepos/core/localization/app_localizations_delegate.dart';
import 'package:tracepos/core/money/money.dart';
import 'package:tracepos/domain/services/catalog_service.dart';
import 'package:tracepos/providers/cart_provider.dart';
import 'package:tracepos/providers/catalog_provider.dart';
import 'package:tracepos/ui/theme/app_design_tokens.dart';
import 'package:tracepos/ui/widgets/common/app_empty_state.dart';
import 'package:tracepos/ui/widgets/common/app_status_badge.dart';
import 'package:tracepos/ui/widgets/common/price_text.dart';
import 'package:tracepos/ui/widgets/common/product_thumbnail.dart';
import 'variant_selection_dialog.dart';

class ProductCatalogGrid extends ConsumerStatefulWidget {
  const ProductCatalogGrid({super.key});

  @override
  ConsumerState<ProductCatalogGrid> createState() => _ProductCatalogGridState();
}

class _ProductCatalogGridState extends ConsumerState<ProductCatalogGrid> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _listMode = false;
  _SortMode _sort = _SortMode.recent;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onProductTap(
    BuildContext context,
    String productName,
    List<VariantSearchResult> variants,
  ) {
    if (variants.isEmpty) return;

    if (variants.length == 1) {
      ref.read(cartNotifierProvider.notifier).addItem(variants.first);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.loc.barcodeScannedSuccess} : ${variants.first.productName}'),
          duration: const Duration(milliseconds: 900),
          backgroundColor: AppDesignTokens.success,
        ),
      );
    } else {
      VariantSelectionDialog.show(
        context,
        productName: productName,
        variants: variants,
      );
    }
  }

  /// Returns a short summary of available sizes/variants from variantDescription.
  /// variantDescription is a joined string like "M / Blue" or "XL".
  String _sizesSummary(List<VariantSearchResult> variants) {
    final descriptions = variants
        .map((v) => v.variantDescription)
        .where((d) => d.isNotEmpty && d != 'Standard')
        .toSet()
        .take(4)
        .join(', ');
    return descriptions;
  }

  int _minPrice(List<VariantSearchResult> v) =>
      v.map((e) => e.salePrice.millimes).reduce((a, b) => a < b ? a : b);

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
    switch (_sort) {
      case _SortMode.recent:
        break;
      case _SortMode.name:
        productGroups.sort(
          (a, b) => a.value.first.productName.toLowerCase().compareTo(
            b.value.first.productName.toLowerCase(),
          ),
        );
      case _SortMode.priceAsc:
        productGroups.sort(
          (a, b) => _minPrice(a.value).compareTo(_minPrice(b.value)),
        );
      case _SortMode.priceDesc:
        productGroups.sort(
          (a, b) => _minPrice(b.value).compareTo(_minPrice(a.value)),
        );
    }

    return Column(
      children: [
        // ── Welcome Hero Banner ────────────────────────────────────────────
        if (catalogState.searchQuery.isEmpty && catalogState.selectedCategoryId == null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            height: 96,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEAF7F0), Color(0xFFF7FBFF)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD1FAE5)),
            ),
            child: Row(
              children: [
                // Left text
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 0, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Bon retour !',
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: AppDesignTokens.success,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Prêt pour de nouvelles ventes ?',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppDesignTokens.textPrimary,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Recherchez un article, scannez un code-barres ou parcourez nos catégories.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppDesignTokens.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ),
                // Right illustration placeholder
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    width: 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1FAE5).withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.checkroom, size: 38, color: Color(0xFF22C55E)),
                        SizedBox(height: 4),
                        Text(
                          'Mode & Style\npour tous les jours',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 9, color: Color(0xFF16A34A), height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ── Search + Category Bar ──────────────────────────────────────────
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
              // Search input + scanner shortcut
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      style: const TextStyle(
                        color: AppDesignTokens.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: context.loc.searchProductOrBarcode,
                        hintStyle: const TextStyle(
                          color: AppDesignTokens.textMuted,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: AppDesignTokens.info,
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
                                  setState(() {});
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      onChanged: (val) {
                        setState(() {});
                        catalogNotifier.search(val);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Tooltip(
                    message: 'Scannez un code-barres',
                    child: InkWell(
                      onTap: () => _searchFocus.requestFocus(),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F0FE),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.qr_code_scanner,
                              color: AppDesignTokens.info,
                              size: 22,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Scanner',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppDesignTokens.info,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Category Filter Chips
              if (catalogState.categories.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      // "All" chip
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _CategoryChip(
                          label: context.loc.allCategories,
                          icon: Icons.grid_view_rounded,
                          isSelected: catalogState.selectedCategoryId == null,
                          onTap: () => catalogNotifier.selectCategory(null),
                        ),
                      ),
                      ...catalogState.categories.map((cat) {
                        final isSelected = catalogState.selectedCategoryId == cat.id;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _CategoryChip(
                            label: context.loc.categoryName(cat.name),
                            icon: Icons.checkroom_outlined,
                            isSelected: isSelected,
                            onTap: () => catalogNotifier.selectCategory(cat.id),
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

        const SizedBox(height: 10),

        // ── Count + Sort bar ───────────────────────────────────────────────
        Row(
          children: [
            Text(
              '${productGroups.length} ${productGroups.length == 1 ? 'article' : 'articles'}',
              style: const TextStyle(fontSize: 13, color: AppDesignTokens.textSecondary),
            ),
            const Spacer(),
            PopupMenuButton<_SortMode>(
              tooltip: 'Trier',
              initialValue: _sort,
              onSelected: (v) => setState(() => _sort = v),
              itemBuilder: (_) => [
                for (final m in _SortMode.values)
                  PopupMenuItem(value: m, child: Text(m.label)),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppDesignTokens.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppDesignTokens.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.sort,
                      size: 16,
                      color: AppDesignTokens.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Trier par : ${_sort.label}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down,
                      size: 16,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            _ViewToggle(
              icon: Icons.grid_view_rounded,
              selected: !_listMode,
              onTap: () => setState(() => _listMode = false),
            ),
            const SizedBox(width: 6),
            _ViewToggle(
              icon: Icons.view_list_rounded,
              selected: _listMode,
              onTap: () => setState(() => _listMode = true),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // ── Products Grid ──────────────────────────────────────────────────
        Expanded(
          child: catalogState.isLoading
              ? const Center(child: CircularProgressIndicator())
              : productGroups.isEmpty
              ? AppEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: context.loc.none,
                  subtitle: context.loc.searchProductOrBarcode,
                )
              : _listMode
              ? ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: productGroups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final variants = productGroups[index].value;
                    final first = variants.first;
                    final stock = variants.fold(0, (sum, v) => sum + v.stock);
                    final min = _minPrice(variants);
                    return InkWell(
                      onTap: () =>
                          _onProductTap(context, first.productName, variants),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppDesignTokens.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppDesignTokens.border),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: ProductThumbnail(
                                imageUrl: first.imageUrl,
                                size: 56,
                                borderRadius: 0,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    first.productName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    [
                                      _sizesSummary(variants),
                                      first.sku.isNotEmpty
                                          ? first.sku
                                          : first.barcode,
                                    ].where((e) => e.isNotEmpty).join('  ·  '),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppDesignTokens.textSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            AppStatusBadge.forStock(
                              stock: stock,
                              isCompact: true,
                              loc: context.loc,
                            ),
                            const SizedBox(width: 16),
                            PriceText(
                              money: Money.fromMillimes(min),
                              fontSize: 13,
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppDesignTokens.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.shopping_cart_outlined,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = (constraints.maxWidth / 190).floor().clamp(2, 6);
                    return GridView.builder(
                      padding: EdgeInsets.zero,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.72,
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
                        final totalStock = variants.fold(0, (sum, v) => sum + v.stock);
                        final sizeSummary = _sizesSummary(variants);

                        return InkWell(
                          onTap: () => _onProductTap(context, productName, variants),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppDesignTokens.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppDesignTokens.border),
                              boxShadow: AppDesignTokens.shadowSm,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── Image area with overlaid badges ──
                                Expanded(
                                  flex: 5,
                                  child: Stack(
                                    children: [
                                      // Product image / thumbnail — use SizedBox.expand
                                      // with a fixed size to avoid double.infinity crash
                                      // in ProductThumbnail's cacheWidth calculation.
                                      ClipRRect(
                                        borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(12),
                                        ),
                                        child: SizedBox.expand(
                                          child: FittedBox(
                                            fit: BoxFit.cover,
                                            clipBehavior: Clip.hardEdge,
                                            child: ProductThumbnail(
                                              imageUrl: firstVar.imageUrl,
                                              size: 140,
                                              borderRadius: 0,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Stock badge — top left
                                      Positioned(
                                        top: 8,
                                        left: 8,
                                        child: AppStatusBadge.forStock(
                                          stock: totalStock,
                                          isCompact: true,
                                          loc: context.loc,
                                        ),
                                      ),
                                      // Favorite icon — top right
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.85),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.favorite_border,
                                            size: 14,
                                            color: AppDesignTokens.textSecondary,
                                          ),
                                        ),
                                      ),
                                      // Variants badge — bottom left if multiple
                                      if (variants.length > 1)
                                        Positioned(
                                          bottom: 6,
                                          left: 6,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.9),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: AppDesignTokens.primarySoftBorder, width: 0.5),
                                            ),
                                            child: Text(
                                              '${variants.length} var.',
                                              style: const TextStyle(
                                                color: AppDesignTokens.primary,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),

                                // ── Text info + cart button ──
                                Expanded(
                                  flex: 4,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Product name
                                        Text(
                                          productName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: AppDesignTokens.textPrimary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),

                                        // Sizes / variants summary
                                        if (sizeSummary.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            sizeSummary,
                                            style: const TextStyle(
                                              color: AppDesignTokens.textSecondary,
                                              fontSize: 10,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],

                                        // SKU / barcode
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            const Icon(Icons.qr_code, size: 10, color: AppDesignTokens.textMuted),
                                            const SizedBox(width: 3),
                                            Expanded(
                                              child: Text(
                                                firstVar.sku.isNotEmpty ? firstVar.sku : firstVar.barcode,
                                                style: const TextStyle(
                                                  color: AppDesignTokens.textMuted,
                                                  fontSize: 10,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),

                                        const Spacer(),

                                        // Price + cart button
                                        Row(
                                          children: [
                                            Expanded(
                                              child: minPrice == maxPrice
                                                  ? PriceText(money: minPrice, fontSize: 13)
                                                  : PriceText(money: minPrice, fontSize: 11),
                                            ),
                                            GestureDetector(
                                              onTap: () => _onProductTap(context, productName, variants),
                                              child: Container(
                                                padding: const EdgeInsets.all(7),
                                                decoration: BoxDecoration(
                                                  color: AppDesignTokens.primary,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Icon(
                                                  Icons.shopping_cart_outlined,
                                                  size: 16,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
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

// ── Helper Widgets ─────────────────────────────────────────────────────────

class _CategoryChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppDesignTokens.primary : AppDesignTokens.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppDesignTokens.primary : AppDesignTokens.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : AppDesignTokens.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? Colors.white : AppDesignTokens.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


enum _SortMode {
  recent('Plus récents'),
  name('Nom A-Z'),
  priceAsc('Prix croissant'),
  priceDesc('Prix décroissant');

  final String label;
  const _SortMode(this.label);
}

class _ViewToggle extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ViewToggle({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 34,
        decoration: BoxDecoration(
          color: selected ? AppDesignTokens.primary : AppDesignTokens.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppDesignTokens.primary : AppDesignTokens.border,
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: selected ? Colors.white : AppDesignTokens.textSecondary,
        ),
      ),
    );
  }
}
