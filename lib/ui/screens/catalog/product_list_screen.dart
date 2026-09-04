import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/catalog_service.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/providers/catalog_provider.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';
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
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (ctx) => const ProductEditScreen()),
    );
    ref.read(catalogNotifierProvider.notifier).refresh();
  }

  void _openEditProduct(String productId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (ctx) => ProductEditScreen(productId: productId)),
    );
    ref.read(catalogNotifierProvider.notifier).refresh();
  }

  void _openLabelStudio(VariantSearchResult variant) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => LabelStudioScreen(
          initialVariant: variant,
        ),
      ),
    );
  }

  Future<void> _archiveProduct(String productId, String productName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Archiver l\'article'),
        content: Text('Voulez-vous vraiment archiver "$productName" ? Il ne sera plus visible sur la caisse.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
            child: const Text('Archiver'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = ref.read(databaseProvider);
      await (db.update(db.products)..where((tbl) => tbl.id.equals(productId))).write(
        const ProductsCompanion(status: Value('ARCHIVED')),
      );
      ref.read(catalogNotifierProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogState = ref.watch(catalogNotifierProvider);

    // Filter variants based on category and status
    final filteredVariants = catalogState.variants.where((v) {
      if (_selectedCategoryId != null) {
        // category filter
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
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Catalogue & Articles Prêt-à-Porter'),
        backgroundColor: AppTheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(catalogNotifierProvider.notifier).refresh(),
            tooltip: 'Actualiser',
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: _openNewProduct,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('NOUVEL ARTICLE'),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Filter Bar
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Rechercher par désignation, référence SKU, code-barres...',
                        prefixIcon: const Icon(Icons.search, color: AppTheme.primaryLight),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  ref.read(catalogNotifierProvider.notifier).search('');
                                },
                              )
                            : null,
                      ),
                      onChanged: (val) => ref.read(catalogNotifierProvider.notifier).search(val),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String?>(
                      initialValue: _selectedCategoryId,
                      decoration: const InputDecoration(labelText: 'Catégorie'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Toutes les catégories')),
                        ...catalogState.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedCategoryId = val);
                        ref.read(catalogNotifierProvider.notifier).selectCategory(val);
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Products Table
            Expanded(
              child: catalogState.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : productList.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.checkroom, size: 64, color: AppTheme.textSecondary),
                              const SizedBox(height: 12),
                              const Text('Aucun article trouvé dans le catalogue', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _openNewProduct,
                                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                                icon: const Icon(Icons.add, color: Colors.white),
                                label: const Text('Créer le premier article', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: ListView.separated(
                            itemCount: productList.length,
                            separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1),
                            itemBuilder: (context, index) {
                              final item = productList[index];
                              final variants = item.value;
                              final firstVar = variants.first;
                              final totalStock = variants.fold(0, (sum, v) => sum + v.stock);
                              final minPrice = variants.map((v) => v.salePrice).reduce((a, b) => a < b ? a : b);
                              final maxPrice = variants.map((v) => v.salePrice).reduce((a, b) => a > b ? a : b);

                              return ExpansionTile(
                                leading: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.checkroom, color: AppTheme.primaryLight),
                                ),
                                title: Text(
                                  firstVar.productName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                                ),
                                subtitle: Text(
                                  '${variants.length} variante(s) • Réf: ${firstVar.sku} • Stock total: $totalStock pièces',
                                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (minPrice == maxPrice)
                                      MoneyDisplay(amount: minPrice, fontSize: 16)
                                    else
                                      Text(
                                        '${minPrice.format()} - ${maxPrice.format()}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryLight),
                                      ),
                                    const SizedBox(width: 16),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 20, color: AppTheme.primaryLight),
                                      onPressed: () => _openEditProduct(item.key),
                                      tooltip: 'Modifier l\'article',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.archive_outlined, size: 20, color: AppTheme.textSecondary),
                                      onPressed: () => _archiveProduct(item.key, firstVar.productName),
                                      tooltip: 'Archiver l\'article',
                                    ),
                                  ],
                                ),
                                children: [
                                  // Expanded list of variants for this clothing item
                                  Container(
                                    color: const Color(0xFF161F2E),
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                    child: Column(
                                      children: variants.map((v) {
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
                                                child: Text(
                                                  v.variantDescription,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Text(
                                                'SKU: ${v.sku}',
                                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                              ),
                                              const SizedBox(width: 16),
                                              Text(
                                                'Code: ${v.barcode}',
                                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                              ),
                                              const Spacer(),
                                              Text(
                                                'Stock: ${v.stock}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: v.stock > 0 ? AppTheme.success : AppTheme.error,
                                                ),
                                              ),
                                              const SizedBox(width: 20),
                                              MoneyDisplay(amount: v.salePrice, fontSize: 14),
                                              const SizedBox(width: 16),
                                              IconButton(
                                                icon: const Icon(Icons.qr_code, size: 18, color: AppTheme.primaryLight),
                                                onPressed: () => _openLabelStudio(v),
                                                tooltip: 'Imprimer Étiquette Code-barres',
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
