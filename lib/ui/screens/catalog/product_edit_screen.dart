import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tracepos/core/localization/app_localizations.dart';
import 'package:tracepos/core/localization/app_localizations_delegate.dart';
import 'package:tracepos/core/errors/failure.dart';
import 'package:tracepos/core/logging/pos_logger.dart';
import 'package:tracepos/core/money/money.dart';
import 'package:tracepos/core/platform/app_paths.dart';
import 'package:tracepos/core/utils/id_generator.dart';
import 'package:tracepos/data/database/app_database.dart';
import 'package:tracepos/domain/models/variant_matrix.dart';
import 'package:tracepos/domain/services/product_image_service.dart';
import 'package:tracepos/hardware/hardware_manager.dart';
import 'package:tracepos/providers/app_providers.dart';
import 'package:tracepos/providers/auth_provider.dart';
import 'package:tracepos/providers/catalog_provider.dart';
import 'package:tracepos/ui/theme/app_design_tokens.dart';
import 'package:tracepos/ui/widgets/common/app_button.dart';
import 'package:tracepos/ui/widgets/common/app_card.dart';
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
  final _skuCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _defaultCostCtrl = TextEditingController(text: '30.000');
  final _defaultPriceCtrl = TextEditingController(text: '69.000');
  final _initialStockCtrl = TextEditingController(text: '10');
  final _minStockCtrl = TextEditingController(text: '2');
  double _taxRatePercent = 19.0;

  bool _hasVariants = false;
  String? _barcodeConflictError;
  bool _isCheckingBarcode = false;
  Timer? _barcodeDebounceTimer;

  String? _selectedCategoryId;
  List<Category> _categories = [];
  List<MatrixVariantItem> _variants = [];
  bool _isLoading = true;
  bool _isSaving = false;

  // Product Image State
  String? _currentImageUrl;
  StagedProductImage? _stagedImage;
  bool _isImageMarkedForRemoval = false;
  bool _isProcessingImage = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _barcodeDebounceTimer?.cancel();
    _nameCtrl.dispose();
    _secondaryNameCtrl.dispose();
    _skuCtrl.dispose();
    _barcodeCtrl.dispose();
    _descriptionCtrl.dispose();
    _defaultCostCtrl.dispose();
    _defaultPriceCtrl.dispose();
    _initialStockCtrl.dispose();
    _minStockCtrl.dispose();
    if (_stagedImage != null) {
      ref.read(productImageServiceProvider).cleanStagedImage(_stagedImage);
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final db = ref.read(databaseProvider);
    final catalogService = ref.read(catalogServiceProvider);

    _categories = await db.select(db.categories).get();
    if (_categories.isNotEmpty && _selectedCategoryId == null) {
      _selectedCategoryId = _categories.first.id;
    }

    if (widget.productId != null) {
      final product = await (db.select(
        db.products,
      )..where((tbl) => tbl.id.equals(widget.productId!))).getSingleOrNull();
      if (product != null) {
        _currentImageUrl = product.imageUrl;
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

        if (_variants.length == 1) {
          _hasVariants = false;
          _skuCtrl.text = _variants.first.sku;
          _barcodeCtrl.text = _variants.first.barcode;
          _initialStockCtrl.text = '${_variants.first.initialStock}';
          _minStockCtrl.text = '${_variants.first.minStockAlert}';
        } else {
          _hasVariants = true;
          _skuCtrl.text = _variants.isNotEmpty
              ? _variants.first.sku.split('-').take(2).join('-')
              : product.name;
          _barcodeCtrl.text = _variants.isNotEmpty ? _variants.first.barcode : '';
        }
      }
    } else {
      // New product: Auto-generate SKU & EAN-13 Barcode
      _skuCtrl.text = await catalogService.generateNextProductSku(
        categoryId: _selectedCategoryId,
      );
      _barcodeCtrl.text = await catalogService.generateUniqueEan13();
      _hasVariants = false;
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _regenerateSku() async {
    final catalogService = ref.read(catalogServiceProvider);
    final sku = await catalogService.generateNextProductSku(
      categoryId: _selectedCategoryId,
    );
    if (mounted) {
      setState(() {
        _skuCtrl.text = sku;
      });
    }
  }

  Future<void> _regenerateBarcode() async {
    final catalogService = ref.read(catalogServiceProvider);
    final barcode = await catalogService.generateUniqueEan13();
    if (mounted) {
      setState(() {
        _barcodeCtrl.text = barcode;
        _barcodeConflictError = null;
      });
    }
  }

  void _onBarcodeChanged(String val) {
    _barcodeDebounceTimer?.cancel();
    _barcodeDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final clean = val.trim();
      if (clean.isEmpty) {
        if (mounted) setState(() => _barcodeConflictError = null);
        return;
      }
      setState(() => _isCheckingBarcode = true);
      final catalogService = ref.read(catalogServiceProvider);
      final conflict = await catalogService.findConflictForBarcode(
        clean,
        excludeVariantId: (widget.productId != null && _variants.isNotEmpty)
            ? _variants.first.id
            : null,
      );
      if (mounted) {
        setState(() {
          _isCheckingBarcode = false;
          _barcodeConflictError = conflict;
        });
      }
    });
  }

  Future<void> _openScanBarcodeDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => const _BarcodeScanDialog(),
    );
    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        _barcodeCtrl.text = result;
      });
      _onBarcodeChanged(result);
    }
  }

  Future<void> _showQuickCreateCategoryDialog() async {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppDesignTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusDialog),
        ),
        title: const Text(
          'Nouvelle catégorie',
          style: TextStyle(
            color: AppDesignTokens.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nom de la catégorie *',
                  hintText: 'ex: Robes, Chemises, Chaussures',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: codeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Code / Préfixe SKU (ex: ROB, CHM)',
                  hintText: '3-4 lettres majuscules',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppDesignTokens.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );

    if (created == true && nameCtrl.text.trim().isNotEmpty && mounted) {
      final user = ref.read(authNotifierProvider).user;
      if (user != null) {
        final cat = await ref.read(catalogServiceProvider).createCategory(
          name: nameCtrl.text.trim(),
          code: codeCtrl.text.trim().isNotEmpty
              ? codeCtrl.text.trim().toUpperCase()
              : null,
          actorId: user.id,
        );
        final db = ref.read(databaseProvider);
        final cats = await db.select(db.categories).get();
        setState(() {
          _categories = cats;
          _selectedCategoryId = cat.id;
        });
        await _regenerateSku();
      }
    }
  }

  Future<void> _pickAndStageImage() async {
    final loc = context.loc;
    final imageService = ref.read(productImageServiceProvider);

    try {
      PosLogger.instance.info('Catalog', 'Launching image picker for product...');
      final picked = await imageService.pickImage();
      if (picked == null) {
        PosLogger.instance.info('Catalog', 'Image picker cancelled or returned no file.');
        return;
      }

      setState(() => _isProcessingImage = true);

      final staged = await imageService.stageImage(picked);
      if (_stagedImage != null) {
        await imageService.cleanStagedImage(_stagedImage);
      }

      setState(() {
        _stagedImage = staged;
        _isImageMarkedForRemoval = false;
      });
    } on PosException catch (e) {
      PosLogger.instance.warning('Catalog', 'Validation error during image staging: ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
      }
    } catch (e, st) {
      PosLogger.instance.error('Catalog', 'Unexpected error picking/staging image: $e', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${loc.error}: $e'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingImage = false);
      }
    }
  }

  Future<void> _confirmRemoveImage() async {
    final loc = context.loc;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.confirmRemoveImageTitle),
        content: Text(loc.confirmRemoveImage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(loc.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppDesignTokens.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(loc.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (_stagedImage != null) {
        await ref.read(productImageServiceProvider).cleanStagedImage(_stagedImage);
      }
      setState(() {
        _stagedImage = null;
        _isImageMarkedForRemoval = true;
      });
    }
  }

  void _openImageFile() {
    String? path;
    if (_stagedImage != null) {
      path = _stagedImage!.mainFile.path;
    } else if (_currentImageUrl != null && !_isImageMarkedForRemoval) {
      path = AppPaths.instance.resolveImagePath(_currentImageUrl!);
    }

    if (path != null && File(path).existsSync()) {
      if (Platform.isWindows) {
        Process.run('explorer.exe', ['/select,', p.normalize(path)]);
      }
    }
  }

  Future<void> _saveProduct() async {
    final loc = context.loc;
    if (!_formKey.currentState!.validate()) return;

    if (_barcodeConflictError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Conflit code-barres : déjà utilisé par $_barcodeConflictError'),
          backgroundColor: AppDesignTokens.danger,
        ),
      );
      return;
    }

    // Determine variants to save
    final cost = Money.tryParse(_defaultCostCtrl.text);
    final price = Money.tryParse(_defaultPriceCtrl.text);
    if (cost == null || cost.isNegative || price == null || price.isNegative) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Les prix doivent être des montants positifs valides.'),
          backgroundColor: AppDesignTokens.danger,
        ),
      );
      return;
    }

    List<MatrixVariantItem> effectiveVariants;
    if (!_hasVariants) {
      if (_skuCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Veuillez renseigner un SKU / Référence.'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
        return;
      }
      if (_barcodeCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Veuillez renseigner ou générer un code-barres.'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
        return;
      }

      effectiveVariants = [
        MatrixVariantItem(
          id: (widget.productId != null && _variants.isNotEmpty)
              ? _variants.first.id
              : IdGenerator.uuid(),
          selectedAttributes: const {},
          sku: _skuCtrl.text.trim(),
          barcode: _barcodeCtrl.text.trim(),
          costPrice: cost,
          salePrice: price,
          initialStock: int.tryParse(_initialStockCtrl.text.trim()) ?? 0,
          minStockAlert: int.tryParse(_minStockCtrl.text.trim()) ?? 2,
          isEnabled: true,
        ),
      ];
    } else {
      effectiveVariants = _variants.where((v) => v.isEnabled).toList();
      if (effectiveVariants.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.atLeastOneVariant),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final catalogService = ref.read(catalogServiceProvider);
      final imageService = ref.read(productImageServiceProvider);
      final auth = ref.read(authNotifierProvider);

      final user = auth.user;
      if (user == null) throw const AuthException('User is not authenticated.');

      final db = ref.read(databaseProvider);
      final store = await (db.select(db.stores)..limit(1)).getSingleOrNull();
      if (store == null) {
        throw const ValidationException('Aucun magasin configuré.');
      }

      final targetProductId = widget.productId ?? IdGenerator.uuid();
      String? finalImageUrl = _currentImageUrl;

      if (_stagedImage != null) {
        finalImageUrl = await imageService.commitProductImage(
          productId: targetProductId,
          staged: _stagedImage!,
          previousImagePath: _currentImageUrl,
        );
        _stagedImage = null;
      } else if (_isImageMarkedForRemoval) {
        if (widget.productId != null) {
          await imageService.removeProductImage(widget.productId!);
        }
        finalImageUrl = null;
      }

      if (widget.productId == null) {
        await catalogService.createProductWithMatrix(
          productId: targetProductId,
          name: _nameCtrl.text.trim(),
          secondaryName: _secondaryNameCtrl.text.trim().isNotEmpty
              ? _secondaryNameCtrl.text.trim()
              : null,
          description: _descriptionCtrl.text.trim().isNotEmpty
              ? _descriptionCtrl.text.trim()
              : null,
          categoryId: _selectedCategoryId,
          imageUrl: finalImageUrl,
          defaultCost: cost,
          defaultPrice: price,
          taxRatePercent: _taxRatePercent,
          variants: effectiveVariants,
          actorId: user.id,
          storeId: store.id,
        );
      } else {
        final location = await ref
            .read(inventoryServiceProvider)
            .getDefaultLocation(store.id);

        await db.transaction(() async {
          for (final variant in effectiveVariants) {
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
              imageUrl: finalImageUrl,
              actorId: user.id,
              locationId: location.id,
            );
          }
          if (finalImageUrl != _currentImageUrl || _isImageMarkedForRemoval) {
            await catalogService.updateProductImage(
              productId: widget.productId!,
              imageUrl: finalImageUrl,
              actorId: user.id,
            );
          }
        });
      }

      // Refresh catalog state
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
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 900) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 280,
                          child: _buildImageCard(loc),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildGeneralInfoCard(loc),
                              const SizedBox(height: 16),
                              _buildIdentificationCard(loc),
                              const SizedBox(height: 16),
                              _buildPricingAndInventoryCard(loc),
                            ],
                          ),
                        ),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        _buildImageCard(loc),
                        const SizedBox(height: 20),
                        _buildGeneralInfoCard(loc),
                        const SizedBox(height: 16),
                        _buildIdentificationCard(loc),
                        const SizedBox(height: 16),
                        _buildPricingAndInventoryCard(loc),
                      ],
                    );
                  }
                },
              ),

              const SizedBox(height: 24),

              // Mode selector for Single vs Matrix variants
              _buildVariantToggleCard(),

              if (_hasVariants) ...[
                const SizedBox(height: 20),
                VariantMatrixEditor(
                  productCode: _skuCtrl.text.trim().isNotEmpty
                      ? _skuCtrl.text.trim()
                      : (_nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : 'PROD'),
                  defaultCost: cost,
                  defaultPrice: price,
                  initialVariants: _variants,
                  onVariantsChanged: (vars) {
                    _variants = vars;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageCard(AppLocalizations loc) {
    final hasImage = (_stagedImage != null) ||
        (_currentImageUrl != null && !_isImageMarkedForRemoval);

    File? previewFile;
    if (_stagedImage != null) {
      previewFile = _stagedImage!.mainFile;
    } else if (_currentImageUrl != null && !_isImageMarkedForRemoval) {
      final resolved = AppPaths.instance.resolveImagePath(_currentImageUrl!);
      if (resolved != null) {
        previewFile = File(resolved);
      }
    }

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.image_outlined,
                size: 20,
                color: AppDesignTokens.primary,
              ),
              const SizedBox(width: 8),
              Text(
                loc.productImage,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Material(
              color: AppDesignTokens.canvas,
              borderRadius: BorderRadius.circular(AppDesignTokens.radiusMd),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _isProcessingImage ? null : _pickAndStageImage,
                borderRadius: BorderRadius.circular(AppDesignTokens.radiusMd),
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppDesignTokens.radiusMd),
                    border: Border.all(
                      color: AppDesignTokens.border,
                      width: 1.5,
                    ),
                  ),
                  child: _isProcessingImage
                      ? const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppDesignTokens.primary,
                          ),
                        )
                      : previewFile != null && previewFile.existsSync()
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(
                                  previewFile,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) =>
                                      _buildImagePlaceholder(loc),
                                ),
                                Positioned(
                                  bottom: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.edit,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : _buildImagePlaceholder(loc),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!hasImage) ...[
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: loc.addImage,
                icon: Icons.add_photo_alternate_outlined,
                variant: AppButtonVariant.outline,
                isLoading: _isProcessingImage,
                onPressed: _isProcessingImage ? null : _pickAndStageImage,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'JPG, PNG, WebP (max 20 Mo)',
                style: TextStyle(
                  fontSize: 11,
                  color: AppDesignTokens.textSecondary.withValues(alpha: 0.8),
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: loc.replaceImage,
                    icon: Icons.sync,
                    variant: AppButtonVariant.outline,
                    isLoading: _isProcessingImage,
                    onPressed: _isProcessingImage ? null : _pickAndStageImage,
                  ),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: loc.removeImage,
                  icon: Icons.delete_outline,
                  variant: AppButtonVariant.danger,
                  onPressed: _isProcessingImage ? null : _confirmRemoveImage,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _openImageFile,
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: Text(
                  loc.openImageFile,
                  style: const TextStyle(fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppDesignTokens.textSecondary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder(AppLocalizations loc) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 48,
            color: AppDesignTokens.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 8),
          Text(
            loc.noImage,
            style: TextStyle(
              fontSize: 13,
              color: AppDesignTokens.textSecondary.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralInfoCard(AppLocalizations loc) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, size: 20, color: AppDesignTokens.primary),
              const SizedBox(width: 8),
              Text(
                loc.generalInfo,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: TextFormField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: '${loc.productName} *',
                    hintText: 'ex: T-Shirt Oversize Coton',
                  ),
                  validator: (val) =>
                      val == null || val.trim().isEmpty ? loc.requiredField : null,
                  onChanged: (val) {
                    if (!_hasVariants && _skuCtrl.text.isEmpty) {
                      _regenerateSku();
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedCategoryId,
                        decoration: InputDecoration(
                          labelText: '${loc.category} *',
                        ),
                        items: _categories
                            .map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.name),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          setState(() => _selectedCategoryId = val);
                          if (widget.productId == null) {
                            _regenerateSku();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Créer une catégorie',
                      child: IconButton.outlined(
                        icon: const Icon(Icons.add, size: 20),
                        color: AppDesignTokens.primary,
                        onPressed: _showQuickCreateCategoryDialog,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _secondaryNameCtrl,
                  decoration: InputDecoration(
                    labelText: loc.secondaryName,
                    hintText: 'ex: Collection Été / Marque',
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _descriptionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Description courte',
                    hintText: 'ex: 100% Coton peigné biologique',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIdentificationCard(AppLocalizations loc) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_2, size: 20, color: AppDesignTokens.primary),
              const SizedBox(width: 8),
              const Text(
                'Identification & Codes-Barres',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // SKU Field
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _skuCtrl,
                      decoration: InputDecoration(
                        labelText: 'Référence / SKU (Auto-généré) *',
                        hintText: 'ex: TSH-000001',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.autorenew, size: 20),
                          tooltip: 'Régénérer SKU automatique',
                          onPressed: _regenerateSku,
                        ),
                      ),
                      validator: (val) =>
                          (val == null || val.trim().isEmpty) ? loc.requiredField : null,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Format séquentiel persistant avec zéros initiaux.',
                      style: TextStyle(fontSize: 11, color: AppDesignTokens.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // Barcode Field
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _barcodeCtrl,
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                        labelText: 'Code-Barres (EAN-13 / Code 128) *',
                        hintText: 'ex: 200123456789',
                        errorText: _barcodeConflictError != null
                            ? '⚠️ Déjà utilisé par : $_barcodeConflictError'
                            : null,
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isCheckingBarcode)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            IconButton(
                              icon: const Icon(Icons.flash_on, color: AppDesignTokens.warning, size: 20),
                              tooltip: 'Générer EAN-13 valide',
                              onPressed: _regenerateBarcode,
                            ),
                            IconButton(
                              icon: const Icon(Icons.qr_code_scanner, color: AppDesignTokens.primary, size: 20),
                              tooltip: 'Scanner le code-barres',
                              onPressed: _openScanBarcodeDialog,
                            ),
                          ],
                        ),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return loc.requiredField;
                        if (_barcodeConflictError != null) return 'Code-barres en conflit';
                        return null;
                      },
                      onChanged: _onBarcodeChanged,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Compatible douchette USB HID. Chiffres et zéros préservés.',
                      style: TextStyle(fontSize: 11, color: AppDesignTokens.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPricingAndInventoryCard(AppLocalizations loc) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.attach_money, size: 20, color: AppDesignTokens.primary),
              const SizedBox(width: 8),
              const Text(
                'Tarification & Stock Initial',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _defaultCostCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: '${loc.defaultPrice} *',
                    suffixText: loc.currencySymbol,
                  ),
                  validator: (val) =>
                      val == null || val.trim().isEmpty ? loc.requiredField : null,
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
              if (!_hasVariants) ...[
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _initialStockCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Stock Initial *',
                      suffixIcon: Icon(Icons.inventory_2_outlined, size: 18),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _minStockCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Alerte Stock Bas',
                      suffixIcon: Icon(Icons.notifications_none, size: 18),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVariantToggleCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        border: Border.all(color: AppDesignTokens.border),
      ),
      child: Row(
        children: [
          Icon(
            _hasVariants ? Icons.style : Icons.checkroom_outlined,
            color: AppDesignTokens.primary,
            size: 24,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _hasVariants
                      ? 'Article avec déclinaisons (Tailles & Couleurs)'
                      : 'Article simple (Taille unique / Sans déclinaison)',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _hasVariants
                      ? 'Génère une matrice de variantes avec SKU et codes-barres dédiés par taille/couleur.'
                      : 'Un seul code-barres et SKU sont nécessaires pour la vente directe.',
                  style: const TextStyle(fontSize: 12, color: AppDesignTokens.textSecondary),
                ),
              ],
            ),
          ),
          Switch(
            value: _hasVariants,
            activeThumbColor: AppDesignTokens.primary,
            activeTrackColor: AppDesignTokens.primaryLight,
            onChanged: (val) {
              setState(() => _hasVariants = val);
            },
          ),
        ],
      ),
    );
  }
}

/// Dedicated dialog for capturing barcode scans from physical USB scanner or manual entry
class _BarcodeScanDialog extends StatefulWidget {
  const _BarcodeScanDialog();

  @override
  State<_BarcodeScanDialog> createState() => _BarcodeScanDialogState();
}

class _BarcodeScanDialogState extends State<_BarcodeScanDialog> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  StreamSubscription<String>? _scanSub;

  @override
  void initState() {
    super.initState();
    // Listen to physical scanner stream if available
    try {
      _scanSub = HardwareManager.instance.barcodeScanner.onScan.listen((scanned) {
        if (mounted && scanned.trim().isNotEmpty) {
          Navigator.of(context).pop(scanned.trim());
        }
      });
    } catch (e) { PosLogger.instance.warning('product_edit_screen', 'Ignored error: $e'); }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isNotEmpty) {
      Navigator.of(context).pop(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppDesignTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusDialog),
      ),
      title: const Row(
        children: [
          Icon(Icons.qr_code_scanner, color: AppDesignTokens.primary, size: 24),
          SizedBox(width: 10),
          Text(
            'Scanner le Code-Barres',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.barcode_reader, color: Color(0xFF16A34A), size: 32),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Prêt pour le scan !\nUtilisez votre douchette USB pour scanner l\'article directement, ou saisissez le code ci-dessous.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF166534), height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _ctrl,
              focusNode: _focusNode,
              autofocus: true,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: 'Code-barres scanné',
                hintText: 'Entrez ou scannez...',
                prefixIcon: Icon(Icons.keyboard, color: AppDesignTokens.primary),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppDesignTokens.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: _submit,
          child: const Text('Valider'),
        ),
      ],
    );
  }
}
