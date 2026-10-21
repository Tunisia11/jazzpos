import 'dart:convert';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';

class OwnerCatalogView extends ConsumerStatefulWidget {
  const OwnerCatalogView({super.key});

  @override
  ConsumerState<OwnerCatalogView> createState() => _OwnerCatalogViewState();
}

class _OwnerCatalogViewState extends ConsumerState<OwnerCatalogView> {
  final TextEditingController _searchController = TextEditingController();
  List<Product> _products = [];
  Map<String, List<ProductVariant>> _variantsByProductId = {};
  bool _isLoading = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseProvider);
      final prods = await (db.select(db.products)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

      final variants = await (db.select(db.productVariants)
            ..where((t) => t.deletedAt.isNull()))
          .get();

      final grouped = <String, List<ProductVariant>>{};
      for (final v in variants) {
        grouped.putIfAbsent(v.productId, () => []).add(v);
      }

      if (mounted) {
        setState(() {
          _products = prods;
          _variantsByProductId = grouped;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editPrice(Product product) async {
    final variants = _variantsByProductId[product.id] ?? [];
    final initialPrice = product.defaultPriceMillimes > 0
        ? Money.fromMillimes(product.defaultPriceMillimes).formatted
        : '0.000';
    final priceController = TextEditingController(text: initialPrice);

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Modifier le prix : ${product.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ce nouveau prix sera synchronisé dans le Cloud et répercuté automatiquement sur toutes les caisses du magasin.',
              style: TextStyle(fontSize: 12, color: AppDesignTokens.textSecondary),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Prix de Vente (TND)',
                suffixText: 'DT',
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppDesignTokens.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Mettre à jour le prix'),
          ),
        ],
      ),
    );

    if (updated != true || !mounted) return;

    final rawPrice = priceController.text.trim().replaceAll(',', '.');
    final priceNum = double.tryParse(rawPrice);
    if (priceNum == null || priceNum < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Veuillez entrer un montant valide.'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
      }
      return;
    }

    final newMillimes = (priceNum * 1000).round();
    final db = ref.read(databaseProvider);
    final now = DateTime.now();

    await db.transaction(() async {
      // 1. Update product default price
      await (db.update(db.products)..where((t) => t.id.equals(product.id))).write(
        ProductsCompanion(
          defaultPriceMillimes: Value(newMillimes),
          updatedAt: Value(now),
        ),
      );

      // 2. Update variant prices
      for (final v in variants) {
        await (db.update(db.productVariants)..where((t) => t.id.equals(v.id))).write(
          ProductVariantsCompanion(
            salePriceOverrideMillimes: Value(newMillimes),
            updatedAt: Value(now),
          ),
        );
      }

      // 3. Enqueue Outbox event to push to Supabase Cloud
      await db.into(db.syncOutbox).insert(
        SyncOutboxCompanion.insert(
          id: IdGenerator.uuid(),
          entityType: 'PRODUCT',
          operation: 'UPDATE',
          payloadJson: jsonEncode({
            'id': product.id,
            'name': product.name,
            'default_price_millimes': newMillimes,
            'updated_at': now.toIso8601String(),
          }),
          createdAt: now,
          updatedAt: now,
        ),
      );
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Prix de "${product.name}" mis à jour à $rawPrice DT.'),
          backgroundColor: AppDesignTokens.success,
        ),
      );
      _loadCatalog();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _products.where((p) {
      if (_filter.isEmpty) return true;
      final q = _filter.toLowerCase();
      final inName = p.name.toLowerCase().contains(q);
      final variants = _variantsByProductId[p.id] ?? [];
      final inSku = variants.any((v) => v.sku.toLowerCase().contains(q));
      final inBarcode = variants.any((v) => v.barcode.toLowerCase().contains(q));
      return inName || inSku || inBarcode;
    }).toList();

    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.all(AppDesignTokens.space16),
          child: TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _filter = val.trim()),
            decoration: InputDecoration(
              hintText: 'Rechercher un article (Nom, SKU, Code-barres)...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _filter.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _filter = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
              fillColor: AppDesignTokens.surface,
              filled: true,
            ),
          ),
        ),

        // Products List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                        _filter.isEmpty ? 'Aucun article trouvé' : 'Aucun résultat pour "$_filter"',
                        style: const TextStyle(color: AppDesignTokens.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: AppDesignTokens.space16),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final product = filtered[i];
                        final variants = _variantsByProductId[product.id] ?? [];
                        final price = Money.fromMillimes(product.defaultPriceMillimes);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: AppDesignTokens.surface,
                            borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
                            border: Border.all(color: AppDesignTokens.border),
                            boxShadow: AppDesignTokens.shadowSm,
                          ),
                          child: ListTile(
                            onTap: () => _editPrice(product),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppDesignTokens.surfaceSecondary,
                                borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput),
                              ),
                              child: const Icon(Icons.inventory_2_outlined, color: AppDesignTokens.primary, size: 22),
                            ),
                            title: Text(
                              product.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${variants.length} variante(s) • ${variants.isNotEmpty ? variants.first.sku : "Sans SKU"}',
                              style: const TextStyle(fontSize: 11, color: AppDesignTokens.textSecondary),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  price.formatted,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: AppDesignTokens.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 18, color: AppDesignTokens.textSecondary),
                                  onPressed: () => _editPrice(product),
                                  tooltip: 'Modifier le prix',
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
