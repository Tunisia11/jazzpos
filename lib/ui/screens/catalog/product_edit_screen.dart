import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/models/variant_matrix.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/providers/catalog_provider.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'package:jazzpos/ui/widgets/common/app_button.dart';
import 'package:jazzpos/ui/widgets/common/app_card.dart';
import 'variant_matrix_editor.dart';

class ProductEditScreen extends ConsumerStatefulWidget {
  final String? productId; // null for new product

  const ProductEditScreen({super.key, this.productId});

  @override
  ConsumerState<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends ConsumerState<ProductEditScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _secondaryNameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _defaultCostCtrl = TextEditingController(text: '30.000');
  final _defaultPriceCtrl = TextEditingController(text: '69.000');
  double _taxRatePercent = 19.0;

  String? _selectedCategoryId;
  List<Category> _categories = [];
  List<MatrixVariantItem> _variants = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _secondaryNameCtrl.dispose();
    _codeCtrl.dispose();
    _descriptionCtrl.dispose();
    _defaultCostCtrl.dispose();
    _defaultPriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final db = ref.read(databaseProvider);
    _categories = await db.select(db.categories).get();
    if (_categories.isNotEmpty && _selectedCategoryId == null) {
      _selectedCategoryId = _categories.first.id;
    }

    if (widget.productId != null) {
      final product = await (db.select(
        db.products,
      )..where((tbl) => tbl.id.equals(widget.productId!))).getSingleOrNull();
      if (product != null) {
        _nameCtrl.text = product.name;
        _secondaryNameCtrl.text = product.secondaryName ?? '';
        _descriptionCtrl.text = product.description ?? '';
        _selectedCategoryId = product.categoryId;
        _defaultCostCtrl.text = Money.fromMillimes(
          product.defaultCostMillimes,
        ).format(includeCurrency: false, useGrouping: false);
        _defaultPriceCtrl.text = Money.fromMillimes(
          product.defaultPriceMillimes,
        ).format(includeCurrency: false, useGrouping: false);
        _taxRatePercent = product.taxRatePercent;

        final dbVariants = await (db.select(
          db.productVariants,
        )..where((table) => table.productId.equals(product.id))).get();
        final inventory = ref.read(inventoryServiceProvider);
        _variants = [];
        for (final variant in dbVariants) {
          _variants.add(
            MatrixVariantItem(
              id: variant.id,
              selectedAttributes: const {},
              sku: variant.sku,
              barcode: variant.barcode,
              costPrice: Money.fromMillimes(
                variant.costPriceOverrideMillimes ??
                    product.defaultCostMillimes,
              ),
              salePrice: Money.fromMillimes(
                variant.salePriceOverrideMillimes ??
                    product.defaultPriceMillimes,
              ),
              initialStock: await inventory.getStock(variant.id),
              minStockAlert: variant.minStockAlert,
              isEnabled: variant.isActive,
            ),
          );
        }
      }
    }

    setState(() => _isLoading = false);
  }

  Future<void> _saveProduct() async {
    final loc = context.loc;
    if (!_formKey.currentState!.validate()) return;
    if (_variants.isEmpty || _variants.where((v) => v.isEnabled).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.atLeastOneVariant),
          backgroundColor: AppDesignTokens.danger,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final catalogService = ref.read(catalogServiceProvider);
      final auth = ref.read(authNotifierProvider);

      final user = auth.user;
      if (user == null) throw const AuthException('User is not authenticated.');
      final cost = Money.tryParse(_defaultCostCtrl.text);
      final price = Money.tryParse(_defaultPriceCtrl.text);
      if (cost == null ||
          cost.isNegative ||
          price == null ||
          price.isNegative) {
        throw const ValidationException(
          'Les prix doivent être des montants positifs avec au maximum trois décimales.',
        );
      }
      final db = ref.read(databaseProvider);
      final store = await (db.select(db.stores)..limit(1)).getSingleOrNull();
      if (store == null) {
        throw const ValidationException('Aucun magasin configuré.');
      }

      if (widget.productId == null) {
        await catalogService.createProductWithMatrix(
          name: _nameCtrl.text.trim(),
          secondaryName: _secondaryNameCtrl.text.trim().isNotEmpty
              ? _secondaryNameCtrl.text.trim()
              : null,
          description: _descriptionCtrl.text.trim().isNotEmpty
              ? _descriptionCtrl.text.trim()
              : null,
          categoryId: _selectedCategoryId,
          defaultCost: cost,
          defaultPrice: price,
          taxRatePercent: _taxRatePercent,
          variants: _variants,
          actorId: user.id,
          storeId: store.id,
        );
      } else {
        final existingIds =
            (await (db.select(db.productVariants)..where(
                      (table) => table.productId.equals(widget.productId!),
                    ))
                    .get())
                .map((variant) => variant.id)
                .toSet();
        if (_variants.any(
          (variant) => !existingIds.contains(variant.id) || !variant.isEnabled,
        )) {
          throw const ValidationException(
            'Ajoutez ou archivez les variantes depuis la gestion du stock.',
          );
        }
        final location = await ref
            .read(inventoryServiceProvider)
            .getDefaultLocation(store.id);
        await db.transaction(() async {
          for (final variant in _variants) {
            await catalogService.updateProductFull(
              productId: widget.productId!,
              variantId: variant.id,
              name: _nameCtrl.text.trim(),
              sku: variant.sku,
              barcode: variant.barcode,
              salePrice: variant.salePrice,
              costPrice: variant.costPrice,
              categoryId: _selectedCategoryId,
              newStock: variant.initialStock,
              minStockAlert: variant.minStockAlert,
              actorId: user.id,
              locationId: location.id,
            );
          }
        });
      }

      // Refresh catalog provider state
      ref.read(catalogNotifierProvider.notifier).refresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.productSavedSuccess),
            backgroundColor: AppDesignTokens.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${loc.error}: $e'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppDesignTokens.canvas,
        body: const Center(
          child: CircularProgressIndicator(color: AppDesignTokens.primary),
        ),
      );
    }

    final cost = Money.tryParse(_defaultCostCtrl.text) ?? Money.zero;
    final price = Money.tryParse(_defaultPriceCtrl.text) ?? Money.zero;

    return Scaffold(
      backgroundColor: AppDesignTokens.canvas,
      appBar: AppBar(
        title: Text(
          widget.productId == null ? loc.newProduct : loc.editProduct,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        backgroundColor: AppDesignTokens.surface,
        foregroundColor: AppDesignTokens.textPrimary,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppDesignTokens.border),
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: AppButton(
              label: loc.save,
              icon: Icons.check,
              variant: AppButtonVariant.success,
              isLoading: _isSaving,
              onPressed: _saveProduct,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product General Info Card
              AppCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.generalInfo,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _nameCtrl,
                            decoration: InputDecoration(
                              labelText: '${loc.productName} *',
                              hintText: 'ex: Chemise Slim Fit',
                            ),
                            validator: (val) =>
                                val == null || val.trim().isEmpty
                                ? loc.requiredField
                                : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _secondaryNameCtrl,
                            decoration: InputDecoration(
                              labelText: loc.secondaryName,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _codeCtrl,
                            decoration: InputDecoration(
                              labelText: loc.skuPrefix,
                              hintText: 'ex: CHM-SLIM',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedCategoryId,
                            decoration: InputDecoration(
                              labelText: loc.category,
                            ),
                            items: _categories
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c.id,
                                    child: Text(loc.categoryName(c.name)),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) =>
                                setState(() => _selectedCategoryId = val),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _defaultCostCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: loc.defaultCost,
                              suffixText: loc.currencySymbol,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _defaultPriceCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: '${loc.defaultPrice} *',
                              suffixText: loc.currencySymbol,
                            ),
                            validator: (val) =>
                                val == null || val.trim().isEmpty
                                ? loc.requiredField
                                : null,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<double>(
                            initialValue: _taxRatePercent,
                            decoration: InputDecoration(labelText: loc.taxRate),
                            items: const [
                              DropdownMenuItem(value: 0.0, child: Text('0%')),
                              DropdownMenuItem(value: 7.0, child: Text('7%')),
                              DropdownMenuItem(value: 19.0, child: Text('19%')),
                            ],
                            onChanged: (val) =>
                                setState(() => _taxRatePercent = val ?? 19.0),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Embedded Clothing Variant Matrix Editor
              VariantMatrixEditor(
                productCode: _codeCtrl.text.isNotEmpty
                    ? _codeCtrl.text
                    : _nameCtrl.text,
                defaultCost: cost,
                defaultPrice: price,
                initialVariants: _variants,
                onVariantsChanged: (vars) {
                  _variants = vars;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
