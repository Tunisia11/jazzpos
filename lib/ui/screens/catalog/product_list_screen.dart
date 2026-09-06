import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/domain/services/catalog_service.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/providers/catalog_provider.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'package:jazzpos/ui/widgets/common/app_button.dart';
import 'package:jazzpos/ui/widgets/common/app_card.dart';
import 'package:jazzpos/ui/widgets/common/app_empty_state.dart';
import 'package:jazzpos/ui/widgets/common/app_page_header.dart';
import 'package:jazzpos/ui/widgets/common/app_search_field.dart';
import 'package:jazzpos/ui/widgets/common/app_status_badge.dart';
import 'package:jazzpos/ui/widgets/common/product_thumbnail.dart';
import 'package:jazzpos/ui/widgets/money_display.dart';
import '../labels/label_studio_screen.dart';
import 'product_edit_screen.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String? _selectedCategoryId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openNewProduct() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (ctx) => const ProductEditScreen()));
    ref.read(catalogNotifierProvider.notifier).refresh();
  }

  void _openEditProduct(String productId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => ProductEditScreen(productId: productId),
      ),
    );
    ref.read(catalogNotifierProvider.notifier).refresh();
  }

  void _openLabelStudio(VariantSearchResult variant) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => LabelStudioScreen(initialVariant: variant),
      ),
    );
  }

  Future<void> _archiveProduct(String productId, String productName) async {
    final loc = context.loc;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppDesignTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusDialog),
        ),
        title: Text(
          loc.archive,
          style: const TextStyle(
            color: AppDesignTokens.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          loc.archiveProductConfirm,
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
              elevation: 0,
            ),
            child: Text(loc.archive),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final user = ref.read(authNotifierProvider).user;
        if (user == null) throw StateError('Utilisateur non connecté.');
        await ref
            .read(catalogServiceProvider)
            .archiveProduct(productId, user.id);
        ref.read(catalogNotifierProvider.notifier).refresh();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${context.loc.error}: $error'),
              backgroundColor: AppDesignTokens.danger,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final catalogState = ref.watch(catalogNotifierProvider);

    // Filter variants based on category
    final filteredVariants = catalogState.variants.where((v) {
      if (_selectedCategoryId != null && v.categoryId != _selectedCategoryId) {
        return false;
      }
      return true;
    }).toList();

    // Group variants by productId
    final Map<String, List<VariantSearchResult>> grouped = {};
    for (final v in filteredVariants) {
      grouped.putIfAbsent(v.productId, () => []).add(v);
    }

    final productList = grouped.entries.toList();

    return Scaffold(
      backgroundColor: AppDesignTokens.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              AppPageHeader(
                title: loc.productsTitle,
                subtitle:
                    '${productList.length} ${loc.activeProducts.toLowerCase()}',
                actions: [
                  IconButton(
                    icon: const Icon(
                      Icons.refresh,
                      color: AppDesignTokens.textSecondary,
                    ),
                    onPressed: () =>
                        ref.read(catalogNotifierProvider.notifier).refresh(),
                    tooltip: loc.refresh,
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    label: loc.newProduct,
                    icon: Icons.add,
                    variant: AppButtonVariant.primary,
                    onPressed: _openNewProduct,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Filter Bar
              AppCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: AppSearchField(
                        controller: _searchCtrl,
                        hintText: loc.searchProductOrBarcode,
                        onChanged: (val) => ref
                            .read(catalogNotifierProvider.notifier)
                            .search(val),
                        onClear: () {
                          _searchCtrl.clear();
                          ref.read(catalogNotifierProvider.notifier).search('');
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String?>(
                        initialValue: _selectedCategoryId,
                        decoration: InputDecoration(
                          labelText: loc.category,
                          filled: true,
                          fillColor: AppDesignTokens.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppDesignTokens.radiusInput,
                            ),
                            borderSide: const BorderSide(
                              color: AppDesignTokens.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppDesignTokens.radiusInput,
                            ),
                            borderSide: const BorderSide(
                              color: AppDesignTokens.border,
                            ),
                          ),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(loc.allCategories),
                          ),
                          ...catalogState.categories.map(
                            (c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(loc.categoryName(c.name)),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          setState(() => _selectedCategoryId = val);
                          ref
                              .read(catalogNotifierProvider.notifier)
                              .selectCategory(val);
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Products List
              Expanded(
                child: catalogState.isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppDesignTokens.primary,
                        ),
                      )
                    : productList.isEmpty
                    ? Center(
                        child: AppEmptyState(
                          icon: Icons.checkroom,
                          title: loc.noProductsFound,
                          action: AppButton(
                            label: loc.createFirstProduct,
                            icon: Icons.add,
                            variant: AppButtonVariant.primary,
                            onPressed: _openNewProduct,
                          ),
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(
                          AppDesignTokens.radiusCard,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppDesignTokens.surface,
                            borderRadius: BorderRadius.circular(
                              AppDesignTokens.radiusCard,
                            ),
                            border: Border.all(color: AppDesignTokens.border),
                            boxShadow: AppDesignTokens.shadowSm,
                          ),
                          child: ListView.separated(
                            itemCount: productList.length,
                            separatorBuilder: (_, __) => const Divider(
                              color: AppDesignTokens.border,
                              height: 1,
                              thickness: 1,
                            ),
                            itemBuilder: (context, index) {
                              final item = productList[index];
                              final variants = item.value;
                              final firstVar = variants.first;
                              final totalStock = variants.fold(
                                0,
                                (sum, v) => sum + v.stock,
                              );
                              final minPrice = variants
                                  .map((v) => v.salePrice)
                                  .reduce((a, b) => a < b ? a : b);
                              final maxPrice = variants
                                  .map((v) => v.salePrice)
                                  .reduce((a, b) => a > b ? a : b);

                              return Theme(
                                data: Theme.of(
                                  context,
                                ).copyWith(dividerColor: Colors.transparent),
                                child: ExpansionTile(
                                  tilePadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  leading: ProductThumbnail(
                                    imageUrl: firstVar.imageUrl,
                                    size: 48,
                                    borderRadius: AppDesignTokens.radiusSm,
                                  ),
                                  title: Text(
                                    firstVar.productName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      color: AppDesignTokens.textPrimary,
                                    ),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Wrap(
                                      spacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                AppDesignTokens.surfaceElevated,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: AppDesignTokens.border,
                                            ),
                                          ),
                                          child: Text(
                                            '${variants.length} ${loc.variantDescription}',
                                            style: const TextStyle(
                                              color:
                                                  AppDesignTokens.textSecondary,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '${loc.sku}: ${firstVar.sku}',
                                          style: const TextStyle(
                                            color: AppDesignTokens.textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                        if (firstVar.categoryName != null)
                                          Text(
                                            '• ${loc.categoryName(firstVar.categoryName!)}',
                                            style: const TextStyle(
                                              color: AppDesignTokens.textMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AppStatusBadge.forStock(
                                        stock: totalStock,
                                        minStockAlert: 5,
                                        loc: loc,
                                      ),
                                      const SizedBox(width: 16),
                                      if (minPrice == maxPrice)
                                        MoneyDisplay(
                                          amount: minPrice,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        )
                                      else
                                        Text(
                                          '${minPrice.format()} - ${maxPrice.format()}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: AppDesignTokens.primary,
                                            fontSize: 14,
                                          ),
                                        ),
                                      const SizedBox(width: 8),
                                      PopupMenuButton<String>(
                                        icon: const Icon(
                                          Icons.more_vert,
                                          color: AppDesignTokens.textSecondary,
                                          size: 20,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          side: const BorderSide(
                                            color: AppDesignTokens.border,
                                          ),
                                        ),
                                        color: AppDesignTokens.surface,
                                        onSelected: (val) {
                                          if (val == 'edit') {
                                            _openEditProduct(item.key);
                                          } else if (val == 'archive') {
                                            _archiveProduct(
                                              item.key,
                                              firstVar.productName,
                                            );
                                          }
                                        },
                                        itemBuilder: (ctx) => [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.edit_outlined,
                                                  size: 18,
                                                  color:
                                                      AppDesignTokens.primary,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  loc.editProduct,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    color: AppDesignTokens
                                                        .textPrimary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'archive',
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.archive_outlined,
                                                  size: 18,
                                                  color:
                                                      AppDesignTokens.warning,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  loc.archive,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    color: AppDesignTokens
                                                        .textPrimary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  children: [
                                    // Expanded list of variants
                                    Container(
                                      decoration: const BoxDecoration(
                                        color: AppDesignTokens.surfaceElevated,
                                        border: Border(
                                          top: BorderSide(
                                            color: AppDesignTokens.border,
                                          ),
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 10,
                                      ),
                                      child: Column(
                                        children: variants.map((v) {
                                          return Container(
                                            margin: const EdgeInsets.symmetric(
                                              vertical: 4,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppDesignTokens.surface,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: AppDesignTokens.border,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: AppDesignTokens
                                                        .primaryLight,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    v.variantDescription,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 12,
                                                      color: AppDesignTokens
                                                          .primary,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Text(
                                                  '${loc.sku}: ${v.sku}',
                                                  style: const TextStyle(
                                                    color: AppDesignTokens
                                                        .textSecondary,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Text(
                                                  '${loc.barcode}: ${v.barcode}',
                                                  style: const TextStyle(
                                                    color: AppDesignTokens
                                                        .textSecondary,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                const Spacer(),
                                                AppStatusBadge.forStock(
                                                  stock: v.stock,
                                                  minStockAlert:
                                                      v.minStockAlert,
                                                  loc: loc,
                                                ),
                                                const SizedBox(width: 16),
                                                MoneyDisplay(
                                                  amount: v.salePrice,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                const SizedBox(width: 12),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.qr_code,
                                                    size: 18,
                                                    color:
                                                        AppDesignTokens.primary,
                                                  ),
                                                  onPressed: () =>
                                                      _openLabelStudio(v),
                                                  tooltip: loc.navLabels,
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
