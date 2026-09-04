import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/models/variant_matrix.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/providers/catalog_provider.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';
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
      }
    }

    setState(() => _isLoading = false);
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    if (_variants.isEmpty || _variants.where((v) => v.isEnabled).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Veuillez générer au moins une variante active pour ce vêtement',
          ),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final catalogService = ref.read(catalogServiceProvider);
      final auth = ref.read(authNotifierProvider);

      final cost = Money.fromTnd(double.tryParse(_defaultCostCtrl.text) ?? 0);
      final price = Money.fromTnd(double.tryParse(_defaultPriceCtrl.text) ?? 0);

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
        actorId: auth.user?.id ?? 'system',
        storeId: 'STORE-01',
      );

      // Refresh catalog provider state
      ref.read(catalogNotifierProvider.notifier).refresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Article et variantes enregistrés avec succès !'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final cost = Money.fromTnd(double.tryParse(_defaultCostCtrl.text) ?? 0);
    final price = Money.fromTnd(double.tryParse(_defaultPriceCtrl.text) ?? 0);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          widget.productId == null
              ? 'Nouvel Article Vêtement'
              : 'Modifier Article',
        ),
        backgroundColor: AppTheme.surface,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveProduct,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                foregroundColor: Colors.white,
              ),
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.check, size: 20),
              label: Text(
                _isSaving ? 'ENREGISTREMENT...' : 'ENREGISTRER L\'ARTICLE',
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product General Info Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Informations Générales de l\'Article',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Désignation de l\'article *',
                              hintText: 'ex: Chemise Slim Fit',
                            ),
                            validator: (val) =>
                                val == null || val.trim().isEmpty
                                ? 'Champ requis'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _secondaryNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nom secondaire / Arabe (optionnel)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _codeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Code / Préfixe SKU',
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
                            decoration: const InputDecoration(
                              labelText: 'Catégorie',
                            ),
                            items: _categories
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.name),
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
                            decoration: const InputDecoration(
                              labelText: 'Coût d\'Achat Défaut (TND)',
                              suffixText: 'TND',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _defaultPriceCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Prix de Vente Défaut (TND) *',
                              suffixText: 'TND',
                            ),
                            validator: (val) =>
                                val == null || val.trim().isEmpty
                                ? 'Champ requis'
                                : null,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<double>(
                            initialValue: _taxRatePercent,
                            decoration: const InputDecoration(
                              labelText: 'Taux TVA',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 0.0,
                                child: Text('0% (Exonéré)'),
                              ),
                              DropdownMenuItem(value: 7.0, child: Text('7%')),
                              DropdownMenuItem(
                                value: 19.0,
                                child: Text('19% (Standard)'),
                              ),
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
