import 'dart:io';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracepos/core/constants/permissions.dart';
import 'package:tracepos/core/constants/roles.dart';
import 'package:tracepos/core/errors/failure.dart';
import 'package:tracepos/core/localization/app_localizations_delegate.dart';
import 'package:tracepos/core/money/money.dart';
import 'package:tracepos/data/database/app_database.dart';
import 'package:tracepos/domain/services/catalog_service.dart';
import 'package:tracepos/providers/app_providers.dart';
import 'package:tracepos/providers/auth_provider.dart';
import 'package:tracepos/providers/catalog_provider.dart';
import 'package:tracepos/ui/theme/app_design_tokens.dart';
import 'package:tracepos/ui/theme/app_theme.dart';
import 'package:tracepos/ui/widgets/common/app_button.dart';
import 'package:tracepos/ui/widgets/common/app_status_badge.dart';
import 'package:tracepos/ui/widgets/common/product_thumbnail.dart';
import 'package:tracepos/ui/widgets/money_display.dart';
import 'stock_count_screen.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<StockLocation> _locations = [];
  List<StockMovement> _movements = [];
  List<VariantSearchResult> _variants = [];
  List<Category> _categories = [];
  String? _selectedLocationId;
  String? _selectedCategoryFilter;
  final Set<String> _expandedProductIds = {};
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final db = ref.read(databaseProvider);
    final catalogService = ref.read(catalogServiceProvider);

    final locations = await db.select(db.stockLocations).get();
    final categories = await db.select(db.categories).get();
    final movements =
        await (db.select(db.stockMovements)
              ..orderBy([(t) => OrderingTerm.desc(t.id)])
              ..limit(100))
            .get();
    final variants = await catalogService.searchVariants(_searchCtrl.text);

    if (mounted) {
      setState(() {
        _locations = locations;
        _categories = categories;
        _movements = movements;
        _variants = variants;
        if (_locations.isNotEmpty && _selectedLocationId == null) {
          _selectedLocationId = _locations.first.id;
        }
        _isLoading = false;
      });
    }
  }

  void _openStockCount() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) =>
            StockCountScreen(locationId: _selectedLocationId ?? 'LOC-SHOP'),
      ),
    );
    _loadData();
  }

  Future<void> _showTransferDialog(VariantSearchResult variant) async {
    final loc = context.loc;
    if (_locations.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.atLeastTwoLocationsRequired),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    String fromLoc = _locations.first.id;
    String toLoc = _locations[1].id;
    final qtyCtrl = TextEditingController(text: '1');
    final reasonCtrl = TextEditingController(text: loc.transferReason);

    final success = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppDesignTokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusDialog),
          ),
          title: Text(
            '${loc.stockTransfer} : ${variant.productName}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${loc.variantDescription}: ${variant.variantDescription} (${loc.sku}: ${variant.sku})',
                style: const TextStyle(color: AppDesignTokens.textSecondary),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: fromLoc,
                decoration: InputDecoration(labelText: loc.sourceLocation),
                items: _locations
                    .map(
                      (l) => DropdownMenuItem(value: l.id, child: Text(l.name)),
                    )
                    .toList(),
                onChanged: (v) => setDialogState(() => fromLoc = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: toLoc,
                decoration: InputDecoration(labelText: loc.destinationLocation),
                items: _locations
                    .map(
                      (l) => DropdownMenuItem(value: l.id, child: Text(l.name)),
                    )
                    .toList(),
                onChanged: (v) => setDialogState(() => toLoc = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: loc.transferQuantity),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: InputDecoration(labelText: loc.transferReason),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(loc.cancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppDesignTokens.primary,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              onPressed: () async {
                final qty = int.tryParse(qtyCtrl.text) ?? 0;
                if (qty <= 0 || fromLoc == toLoc) return;

                final invService = ref.read(inventoryServiceProvider);
                final auth = ref.read(authNotifierProvider);

                await invService.transferStock(
                  variantId: variant.variantId,
                  fromLocationId: fromLoc,
                  toLocationId: toLoc,
                  quantity: qty,
                  actorId: auth.user?.id ?? 'system',
                  reason: reasonCtrl.text.trim(),
                );
                if (ctx.mounted) {
                  Navigator.of(ctx).pop(true);
                }
              },
              child: Text(loc.stockTransfer),
            ),
          ],
        ),
      ),
    );

    if (success == true) {
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.transferSuccessful),
            backgroundColor: AppDesignTokens.success,
          ),
        );
      }
    }
  }

  /// Dialog 1: Modifier le produit
  Future<void> _showEditProductDialog(VariantSearchResult variant) async {
    final loc = context.loc;
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: variant.productName);
    final skuCtrl = TextEditingController(text: variant.sku);
    final barcodeCtrl = TextEditingController(text: variant.barcode);
    final variantCtrl = TextEditingController(text: variant.variantDescription);
    final salePriceCtrl = TextEditingController(
      text: variant.salePrice.format(
        includeCurrency: false,
        useGrouping: false,
      ),
    );
    final costPriceCtrl = TextEditingController(
      text: variant.costPrice.format(
        includeCurrency: false,
        useGrouping: false,
      ),
    );
    final stockCtrl = TextEditingController(text: variant.stock.toString());
    final minStockCtrl = TextEditingController(
      text: variant.minStockAlert.toString(),
    );

    String? selectedCategory = variant.categoryId;
    String? currentImage = variant.imageUrl;
    XFile? pickedNewImage;
    bool imageMarkedForRemoval = false;
    bool isSaving = false;
    String? dialogError;

    final imageService = ref.read(productImageServiceProvider);
    final catalogService = ref.read(catalogServiceProvider);
    final auth = ref.read(authNotifierProvider);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setModalState) {
          final int parsedStock = int.tryParse(stockCtrl.text) ?? variant.stock;
          final bool stockHasChanged = parsedStock != variant.stock;

          return AlertDialog(
            backgroundColor: AppDesignTokens.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDesignTokens.radiusDialog),
              side: const BorderSide(color: AppDesignTokens.border),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppDesignTokens.primaryLight.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.edit_outlined,
                    color: AppDesignTokens.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${loc.editProduct} : ${variant.productName}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (dialogError != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: AppDesignTokens.dangerBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppDesignTokens.danger.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: AppDesignTokens.danger,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  dialogError!,
                                  style: const TextStyle(
                                    color: AppDesignTokens.dangerText,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Image & Basic Info header
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Thumbnail Preview
                          Stack(
                            children: [
                              Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  color: AppTheme.background,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppTheme.border),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(9),
                                  child: pickedNewImage != null
                                      ? Image.file(
                                          File(pickedNewImage!.path),
                                          fit: BoxFit.cover,
                                        )
                                      : (!imageMarkedForRemoval &&
                                            currentImage != null &&
                                            currentImage.isNotEmpty)
                                      ? (currentImage.startsWith('http')
                                            ? Image.network(
                                                currentImage,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    _buildPlaceholder(size: 90),
                                              )
                                            : (File(currentImage).existsSync()
                                                  ? Image.file(
                                                      File(currentImage),
                                                      fit: BoxFit.cover,
                                                      errorBuilder:
                                                          (_, __, ___) =>
                                                              _buildPlaceholder(
                                                                size: 90,
                                                              ),
                                                    )
                                                  : _buildPlaceholder(
                                                      size: 90,
                                                    )))
                                      : _buildPlaceholder(size: 90),
                                ),
                              ),
                              if (pickedNewImage != null ||
                                  (!imageMarkedForRemoval &&
                                      currentImage != null &&
                                      currentImage.isNotEmpty))
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: InkWell(
                                    onTap: isSaving
                                        ? null
                                        : () {
                                            setModalState(() {
                                              pickedNewImage = null;
                                              imageMarkedForRemoval = true;
                                            });
                                          },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.black87,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: isSaving
                                      ? null
                                      : () async {
                                          try {
                                            final file = await imageService
                                                .pickImage();
                                            if (file != null) {
                                              setModalState(() {
                                                pickedNewImage = file;
                                                imageMarkedForRemoval = false;
                                                dialogError = null;
                                              });
                                            }
                                          } catch (e) {
                                            setModalState(() {
                                              dialogError = 'Erreur: $e';
                                            });
                                          }
                                        },
                                  icon: const Icon(
                                    Icons.add_photo_alternate_outlined,
                                    size: 16,
                                  ),
                                  label: Text(
                                    (pickedNewImage != null ||
                                            (!imageMarkedForRemoval &&
                                                currentImage != null &&
                                                currentImage.isNotEmpty))
                                        ? loc.addOrEditPhoto
                                        : loc.chooseImage,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'PNG, JPG, JPEG, WebP',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),
                      const Divider(color: AppTheme.border),
                      const SizedBox(height: 14),

                      // Row 1: Name & Category
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: nameCtrl,
                              enabled: !isSaving,
                              decoration: InputDecoration(
                                labelText: '${loc.productName} *',
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? loc.productName
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String?>(
                              initialValue: selectedCategory,
                              decoration: InputDecoration(
                                labelText: loc.category,
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: null,
                                  child: Text(loc.none),
                                ),
                                ..._categories.map(
                                  (c) => DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.name),
                                  ),
                                ),
                              ],
                              onChanged: isSaving
                                  ? null
                                  : (val) => setModalState(
                                      () => selectedCategory = val,
                                    ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Row 2: SKU, Barcode, Size/Variant
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: skuCtrl,
                              enabled: !isSaving,
                              decoration: InputDecoration(
                                labelText: '${loc.sku} *',
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? loc.sku
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: barcodeCtrl,
                              enabled: !isSaving,
                              decoration: InputDecoration(
                                labelText: '${loc.barcode} *',
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? loc.barcode
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: variantCtrl,
                              enabled: !isSaving,
                              decoration: InputDecoration(
                                labelText:
                                    '${loc.size} / ${loc.variantDescription}',
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Row 3: Prices
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: salePriceCtrl,
                              enabled: !isSaving,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText:
                                    '${loc.sellingPrice} (${loc.currencySymbol}) *',
                                suffixText: loc.currencySymbol,
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return loc.price;
                                }
                                final p = double.tryParse(v.trim());
                                if (p == null || p < 0) {
                                  return loc.price;
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: costPriceCtrl,
                              enabled: !isSaving,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText:
                                    '${loc.costPrice} (${loc.currencySymbol})',
                                suffixText: loc.currencySymbol,
                              ),
                              validator: (v) {
                                if (v != null && v.trim().isNotEmpty) {
                                  final p = double.tryParse(v.trim());
                                  if (p == null || p < 0) {
                                    return loc.costPrice;
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Row 4: Stock Quantity & Minimum Threshold
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: stockCtrl,
                              enabled: !isSaving,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: '${loc.currentStock} *',
                                suffixIcon: const Icon(
                                  Icons.inventory,
                                  size: 18,
                                ),
                              ),
                              onChanged: (_) => setModalState(() {}),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return loc.quantity;
                                }
                                if (int.tryParse(v.trim()) == null) {
                                  return loc.quantity;
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: minStockCtrl,
                              enabled: !isSaving,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: loc.minStockAlert,
                                suffixIcon: const Icon(
                                  Icons.warning_amber,
                                  size: 18,
                                ),
                              ),
                              validator: (v) {
                                if (v != null && v.trim().isNotEmpty) {
                                  final m = int.tryParse(v.trim());
                                  if (m == null || m < 0) {
                                    return loc.quantity;
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),

                      // Stock Adjustment Audit Warning
                      if (stockHasChanged) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppDesignTokens.warningBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppDesignTokens.warning.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.history_edu,
                                color: AppDesignTokens.warning,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  loc.manualStockAuditWarning,
                                  style: const TextStyle(
                                    color: AppDesignTokens.warningText,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving
                    ? null
                    : () => Navigator.of(dialogCtx).pop(),
                child: Text(loc.cancel),
              ),
              ElevatedButton.icon(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        final navigator = Navigator.of(dialogCtx);
                        final messenger = ScaffoldMessenger.of(context);

                        setModalState(() {
                          isSaving = true;
                          dialogError = null;
                        });

                        try {
                          String? finalImageUrl = currentImage;
                          if (pickedNewImage != null) {
                            finalImageUrl = await imageService.saveProductImage(
                              file: pickedNewImage!,
                              productId: variant.productId,
                            );
                          } else if (imageMarkedForRemoval) {
                            finalImageUrl = null;
                          }

                          final salePrice = Money.tryParse(
                            salePriceCtrl.text.trim(),
                          );
                          final costPrice = Money.tryParse(
                            costPriceCtrl.text.trim(),
                          );
                          if (salePrice == null ||
                              salePrice.isNegative ||
                              costPrice == null ||
                              costPrice.isNegative) {
                            throw const ValidationException(
                              'Prix invalide. Utilisez au maximum trois décimales.',
                            );
                          }
                          final int targetStock = int.parse(
                            stockCtrl.text.trim(),
                          );
                          final int targetMinStock =
                              int.tryParse(minStockCtrl.text.trim()) ?? 2;

                          await catalogService.updateProductFull(
                            productId: variant.productId,
                            variantId: variant.variantId,
                            name: nameCtrl.text.trim(),
                            sku: skuCtrl.text.trim().toUpperCase(),
                            barcode: barcodeCtrl.text.trim(),
                            sizeOrVariant: variantCtrl.text.trim(),
                            salePrice: salePrice,
                            costPrice: costPrice,
                            categoryId: selectedCategory,
                            newStock: targetStock,
                            minStockAlert: targetMinStock,
                            imageUrl: finalImageUrl,
                            actorId: auth.user?.id ?? 'system',
                            locationId: _selectedLocationId,
                          );

                          if ((pickedNewImage != null ||
                                  imageMarkedForRemoval) &&
                              currentImage != null &&
                              currentImage != finalImageUrl) {
                            await imageService.deleteImageFile(currentImage);
                          }

                          if (dialogCtx.mounted) {
                            navigator.pop();
                          }
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${nameCtrl.text.trim()} : ${loc.productSavedSuccess}',
                                ),
                                backgroundColor: AppDesignTokens.success,
                              ),
                            );
                            _loadData();
                            ref
                                .read(catalogNotifierProvider.notifier)
                                .refresh();
                          }
                        } catch (e) {
                          setModalState(() {
                            isSaving = false;
                            dialogError = e.toString();
                          });
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppDesignTokens.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check, size: 18),
                label: Text(isSaving ? loc.processing : loc.save),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Dialog 2: Ajouter / Modifier la photo
  Future<void> _showPhotoUploadDialog(VariantSearchResult variant) async {
    final loc = context.loc;
    XFile? tempPickedFile;
    bool willRemove = false;
    bool isSaving = false;
    String? uploadError;

    final imageService = ref.read(productImageServiceProvider);
    final catalogService = ref.read(catalogServiceProvider);
    final auth = ref.read(authNotifierProvider);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final bool hasExisting =
              variant.imageUrl != null && variant.imageUrl!.isNotEmpty;

          return AlertDialog(
            backgroundColor: AppDesignTokens.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDesignTokens.radiusDialog),
              side: const BorderSide(color: AppDesignTokens.border),
            ),
            title: Row(
              children: [
                const Icon(
                  Icons.add_photo_alternate_outlined,
                  color: AppDesignTokens.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${loc.addOrEditPhoto} : ${variant.productName}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (uploadError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: AppDesignTokens.dangerBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppDesignTokens.danger.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        uploadError!,
                        style: const TextStyle(
                          color: AppDesignTokens.dangerText,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],

                  // Large Preview Box
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: AppDesignTokens.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppDesignTokens.border,
                        width: 1.5,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: tempPickedFile != null
                          ? Image.file(
                              File(tempPickedFile!.path),
                              fit: BoxFit.cover,
                            )
                          : (!willRemove && hasExisting)
                          ? (variant.imageUrl!.startsWith('http')
                                ? Image.network(
                                    variant.imageUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _buildPlaceholder(size: 200),
                                  )
                                : (File(variant.imageUrl!).existsSync()
                                      ? Image.file(
                                          File(variant.imageUrl!),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              _buildPlaceholder(size: 200),
                                        )
                                      : _buildPlaceholder(size: 200)))
                          : _buildPlaceholder(size: 200),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Button select image
                  ElevatedButton.icon(
                    onPressed: isSaving
                        ? null
                        : () async {
                            try {
                              final file = await imageService.pickImage();
                              if (file != null) {
                                setModalState(() {
                                  tempPickedFile = file;
                                  willRemove = false;
                                  uploadError = null;
                                });
                              }
                            } catch (e) {
                              setModalState(() {
                                uploadError = 'Erreur: $e';
                              });
                            }
                          },
                    icon: const Icon(Icons.file_upload_outlined, size: 18),
                    label: Text(loc.chooseImage),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppDesignTokens.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                  ),

                  // Button remove existing
                  if ((hasExisting || tempPickedFile != null) &&
                      !willRemove) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: isSaving
                          ? null
                          : () {
                              setModalState(() {
                                tempPickedFile = null;
                                willRemove = true;
                              });
                            },
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: AppDesignTokens.danger,
                      ),
                      label: Text(
                        loc.removePhoto,
                        style: const TextStyle(
                          color: AppDesignTokens.dangerText,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),
                  const Text(
                    'PNG, JPG, JPEG, WebP',
                    style: TextStyle(
                      color: AppDesignTokens.textSecondary,
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                child: Text(loc.cancel),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppDesignTokens.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        setModalState(() {
                          isSaving = true;
                          uploadError = null;
                        });

                        try {
                          final navigator = Navigator.of(ctx);
                          final messenger = ScaffoldMessenger.of(context);

                          if (tempPickedFile != null) {
                            final savedPath = await imageService
                                .saveProductImage(
                                  file: tempPickedFile!,
                                  productId: variant.productId,
                                );

                            await catalogService.updateProductImage(
                              productId: variant.productId,
                              variantId: variant.variantId,
                              imageUrl: savedPath,
                              actorId: auth.user?.id ?? 'system',
                            );
                            await imageService.deleteImageFile(
                              variant.imageUrl,
                            );
                          } else if (willRemove && hasExisting) {
                            await catalogService.updateProductImage(
                              productId: variant.productId,
                              variantId: variant.variantId,
                              imageUrl: null,
                              actorId: auth.user?.id ?? 'system',
                            );
                            await imageService.deleteImageFile(
                              variant.imageUrl,
                            );
                          }

                          if (ctx.mounted) {
                            navigator.pop();
                          }
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(loc.photoUpdatedSuccess),
                                backgroundColor: AppDesignTokens.success,
                              ),
                            );
                            _loadData();
                            ref
                                .read(catalogNotifierProvider.notifier)
                                .refresh();
                          }
                        } catch (e) {
                          setModalState(() {
                            isSaving = false;
                            uploadError = 'Erreur: $e';
                          });
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(loc.save),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Dialog 3: Supprimer le produit (Soft-delete sécurisé)
  Future<void> _showDeleteProductDialog(VariantSearchResult variant) async {
    final loc = context.loc;
    bool isDeleting = false;
    String? deleteError;

    final catalogService = ref.read(catalogServiceProvider);
    final auth = ref.read(authNotifierProvider);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: AppDesignTokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusDialog),
            side: const BorderSide(color: AppDesignTokens.border),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppDesignTokens.danger,
                size: 24,
              ),
              const SizedBox(width: 10),
              Text(
                loc.deleteProductConfirmTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (deleteError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppDesignTokens.dangerBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppDesignTokens.danger.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      deleteError!,
                      style: const TextStyle(
                        color: AppDesignTokens.dangerText,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
                Text(
                  loc.deleteProductPrompt,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppDesignTokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppDesignTokens.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${loc.productName} : ',
                            style: const TextStyle(
                              color: AppDesignTokens.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              variant.productName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AppDesignTokens.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            '${loc.sku} : ',
                            style: const TextStyle(
                              color: AppDesignTokens.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            variant.sku,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppDesignTokens.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            '${loc.currentStock} : ',
                            style: const TextStyle(
                              color: AppDesignTokens.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '${variant.stock}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: variant.stock <= 0
                                  ? AppDesignTokens.dangerText
                                  : AppDesignTokens.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  loc.protectedHistoryNote,
                  style: const TextStyle(
                    color: AppDesignTokens.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isDeleting ? null : () => Navigator.of(ctx).pop(),
              child: Text(loc.cancel),
            ),
            ElevatedButton.icon(
              onPressed: isDeleting
                  ? null
                  : () async {
                      setModalState(() {
                        isDeleting = true;
                        deleteError = null;
                      });

                      try {
                        final navigator = Navigator.of(ctx);
                        final messenger = ScaffoldMessenger.of(context);

                        await catalogService.softDeleteProduct(
                          productId: variant.productId,
                          variantId: variant.variantId,
                          actorId: auth.user?.id ?? 'system',
                        );

                        if (ctx.mounted) {
                          navigator.pop();
                        }
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                '${variant.productName} : ${loc.productDeletedSuccess}',
                              ),
                              backgroundColor: AppDesignTokens.success,
                            ),
                          );
                          _loadData();
                          ref.read(catalogNotifierProvider.notifier).refresh();
                        }
                      } catch (e) {
                        setModalState(() {
                          isDeleting = false;
                          deleteError = 'Erreur: $e';
                        });
                      }
                    },
              icon: isDeleting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.delete, size: 16),
              label: Text(isDeleting ? loc.processing : loc.deleteProduct),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppDesignTokens.danger,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductThumbnail(String? imageUrl) {
    return ProductThumbnail(
      imageUrl: imageUrl,
      size: 46,
      borderRadius: AppDesignTokens.radiusSm,
    );
  }

  Widget _buildPlaceholder({double size = 46}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppDesignTokens.border),
      ),
      child: Icon(
        Icons.checkroom,
        color: AppDesignTokens.textMuted,
        size: size * 0.48,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    return Scaffold(
      backgroundColor: AppDesignTokens.canvas,
      appBar: AppBar(
        title: Text(
          loc.stockLevelsTitle,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        backgroundColor: AppDesignTokens.surface,
        foregroundColor: AppDesignTokens.textPrimary,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppDesignTokens.primary,
          labelColor: AppDesignTokens.primary,
          unselectedLabelColor: AppDesignTokens.textSecondary,
          tabs: [
            Tab(
              icon: const Icon(Icons.inventory_2),
              text: loc.stockLevelsTitle.toUpperCase(),
            ),
            Tab(
              icon: const Icon(Icons.history),
              text: loc.stockMovementsHistory.toUpperCase(),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: AppButton(
              onPressed: _openStockCount,
              variant: AppButtonVariant.primary,
              icon: Icons.fact_check,
              label: loc.startInventory.toUpperCase(),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppDesignTokens.primary),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Current Stock Levels
                _buildStockLevelsTab(),

                // Tab 2: Stock Movements Ledger
                _buildMovementsTab(),
              ],
            ),
    );
  }

  Widget _buildStockLevelsTab() {
    final loc = context.loc;
    final auth = ref.watch(authNotifierProvider);
    final user = auth.user;
    final isOwnerOrAdmin =
        user?.role == AppRoles.owner || user?.role == AppRoles.manager;
    final canManage =
        isOwnerOrAdmin ||
        auth.hasPermission(AppPermissions.editProducts) ||
        auth.hasPermission(AppPermissions.manageInventory);
    final canDelete =
        isOwnerOrAdmin || auth.hasPermission(AppPermissions.editProducts);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Filter Bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppDesignTokens.surface,
              borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
              border: Border.all(color: AppDesignTokens.border),
              boxShadow: AppDesignTokens.shadowSm,
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(
                      color: AppDesignTokens.textPrimary,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: loc.filterArticlesPrompt,
                      hintStyle: const TextStyle(
                        color: AppDesignTokens.textMuted,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppDesignTokens.textSecondary,
                      ),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchCtrl.clear();
                                _loadData();
                              },
                            )
                          : null,
                    ),
                    onSubmitted: (_) => _loadData(),
                  ),
                ),
                const SizedBox(width: 16),
                if (_categories.isNotEmpty) ...[
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String?>(
                      initialValue: _selectedCategoryFilter,
                      decoration: const InputDecoration(
                        labelText: 'Catégorie',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Toutes les catégories'),
                        ),
                        ..._categories.map(
                          (c) => DropdownMenuItem<String?>(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedCategoryFilter = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                IconButton(
                  icon: const Icon(
                    Icons.refresh,
                    color: AppDesignTokens.textSecondary,
                  ),
                  onPressed: _loadData,
                  tooltip: loc.refresh,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Group variants by productId
          Builder(
            builder: (context) {
              final filteredVariants = _variants.where((v) {
                if (_selectedCategoryFilter != null &&
                    v.categoryId != _selectedCategoryFilter) {
                  return false;
                }
                return true;
              }).toList();

              final Map<String, List<VariantSearchResult>> groupedByProduct = {};
              for (final v in filteredVariants) {
                groupedByProduct.putIfAbsent(v.productId, () => []).add(v);
              }
              final productGroups = groupedByProduct.entries.toList();

              if (productGroups.isEmpty) {
                return Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppDesignTokens.surface,
                      borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
                      border: Border.all(color: AppDesignTokens.border),
                      boxShadow: AppDesignTokens.shadowSm,
                    ),
                    child: Center(
                      child: Text(
                        loc.noArticlesFoundInInventory,
                        style: const TextStyle(
                          color: AppDesignTokens.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }

              return Expanded(
                child: ListView.builder(
                  itemCount: productGroups.length,
                  itemBuilder: (context, index) {
                    final entry = productGroups[index];
                    final productVariants = entry.value;
                    final mainVar = productVariants.first;
                    final totalStock = productVariants.fold<int>(
                      0,
                      (sum, v) => sum + v.stock,
                    );
                    final minAlert = productVariants
                        .map((v) => v.minStockAlert)
                        .fold<int>(0, (max, v) => v > max ? v : max);
                    final minPrice = productVariants
                        .map((v) => v.salePrice)
                        .reduce((a, b) => a < b ? a : b);
                    final maxPrice = productVariants
                        .map((v) => v.salePrice)
                        .reduce((a, b) => a > b ? a : b);
                    final isExpanded = _expandedProductIds.contains(entry.key);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
                        side: BorderSide(
                          color: isExpanded
                              ? AppDesignTokens.primary.withValues(alpha: 0.5)
                              : AppDesignTokens.border,
                          width: isExpanded ? 1.5 : 1.0,
                        ),
                      ),
                      child: Column(
                        children: [
                          InkWell(
                            onTap: () {
                              setState(() {
                                if (isExpanded) {
                                  _expandedProductIds.remove(entry.key);
                                } else {
                                  _expandedProductIds.add(entry.key);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  // Expand icon
                                  Icon(
                                    isExpanded
                                        ? Icons.keyboard_arrow_down
                                        : Icons.keyboard_arrow_right,
                                    color: isExpanded
                                        ? AppDesignTokens.primary
                                        : AppDesignTokens.textSecondary,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 8),
                                  // Thumbnail
                                  _buildProductThumbnail(mainVar.imageUrl),
                                  const SizedBox(width: 14),
                                  // Product info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          mainVar.productName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: AppDesignTokens.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            if (mainVar.categoryName != null &&
                                                mainVar.categoryName!.isNotEmpty) ...[
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppDesignTokens.primaryLight
                                                      .withValues(alpha: 0.4),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  mainVar.categoryName!,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: AppDesignTokens.primary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppDesignTokens.surfaceElevated,
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: AppDesignTokens.border,
                                                ),
                                              ),
                                              child: Text(
                                                productVariants.length == 1
                                                    ? 'Article simple'
                                                    : '${productVariants.length} déclinaisons',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppDesignTokens.textSecondary,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Stock and Price
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            'Stock total : ',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppDesignTokens.textSecondary,
                                            ),
                                          ),
                                          AppStatusBadge.forStock(
                                            stock: totalStock,
                                            minStockAlert: minAlert,
                                            loc: loc,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      minPrice == maxPrice
                                          ? MoneyDisplay(
                                              amount: minPrice,
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                            )
                                          : Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                MoneyDisplay(
                                                  amount: minPrice,
                                                  fontSize: 11,
                                                ),
                                                const Text(
                                                  ' - ',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: AppDesignTokens.textMuted,
                                                  ),
                                                ),
                                                MoneyDisplay(
                                                  amount: maxPrice,
                                                  fontSize: 11,
                                                ),
                                              ],
                                            ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  // Product Actions Menu
                                  if (canManage) ...[
                                    PopupMenuButton<String>(
                                      icon: const Icon(
                                        Icons.more_vert,
                                        size: 20,
                                        color: AppDesignTokens.textSecondary,
                                      ),
                                      tooltip: loc.productActions,
                                      onSelected: (action) {
                                        switch (action) {
                                          case 'edit':
                                            _showEditProductDialog(mainVar);
                                            break;
                                          case 'photo':
                                            _showPhotoUploadDialog(mainVar);
                                            break;
                                          case 'delete':
                                            _showDeleteProductDialog(mainVar);
                                            break;
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.edit_outlined,
                                                size: 18,
                                                color: AppDesignTokens.primary,
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                loc.editProduct,
                                                style: const TextStyle(fontSize: 13),
                                              ),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'photo',
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.add_photo_alternate_outlined,
                                                size: 18,
                                                color: AppDesignTokens.primary,
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                loc.addOrEditPhoto,
                                                style: const TextStyle(fontSize: 13),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (canDelete)
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.delete_outline,
                                                  size: 18,
                                                  color: AppDesignTokens.danger,
                                                ),
                                                const SizedBox(width: 10),
                                                Text(
                                                  loc.deleteProduct,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    color: AppDesignTokens.danger,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                          // Nested Variants Breakdown
                          if (isExpanded) ...[
                            const Divider(height: 1, color: AppDesignTokens.border),
                            Container(
                              color: AppDesignTokens.surfaceElevated
                                  .withValues(alpha: 0.5),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              child: Column(
                                children: productVariants.map((v) {
                                  return Container(
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppDesignTokens.surface,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: AppDesignTokens.border
                                            .withValues(alpha: 0.7),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const SizedBox(width: 8),
                                        const Icon(
                                          Icons.subdirectory_arrow_right,
                                          size: 16,
                                          color: AppDesignTokens.textMuted,
                                        ),
                                        const SizedBox(width: 10),
                                        // Variant Description
                                        Expanded(
                                          flex: 3,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                v.variantDescription.isNotEmpty
                                                    ? v.variantDescription
                                                    : 'Standard / Taille unique',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  color: AppDesignTokens.textPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'SKU: ${v.sku}  •  Code: ${v.barcode}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      AppDesignTokens.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Price
                                        MoneyDisplay(
                                          amount: v.salePrice,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        const SizedBox(width: 16),
                                        // Stock status badge
                                        AppStatusBadge.forStock(
                                          stock: v.stock,
                                          minStockAlert: v.minStockAlert,
                                          loc: loc,
                                        ),
                                        const SizedBox(width: 16),
                                        // Action: Stock Transfer
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            minimumSize: Size.zero,
                                            tapTargetSize:
                                                MaterialTapTargetSize.shrinkWrap,
                                            side: const BorderSide(
                                              color: AppDesignTokens.border,
                                            ),
                                          ),
                                          onPressed: () => _showTransferDialog(v),
                                          icon: const Icon(
                                            Icons.swap_horiz,
                                            size: 14,
                                          ),
                                          label: Text(
                                            loc.stockTransfer,
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Action: Adjust variant
                                        if (canManage) ...[
                                          OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 6,
                                              ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize.shrinkWrap,
                                              side: const BorderSide(
                                                color: AppDesignTokens.border,
                                              ),
                                            ),
                                            onPressed: () =>
                                                _showEditProductDialog(v),
                                            icon: const Icon(Icons.edit, size: 14),
                                            label: const Text(
                                              'Ajuster',
                                              style: TextStyle(fontSize: 11),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMovementsTab() {
    final loc = context.loc;
    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppDesignTokens.surface,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        border: Border.all(color: AppDesignTokens.border),
        boxShadow: AppDesignTokens.shadowSm,
      ),
      child: _movements.isEmpty
          ? Center(
              child: Text(
                loc.noMovementsRecorded,
                style: const TextStyle(color: AppDesignTokens.textSecondary),
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
              child: ListView.separated(
                itemCount: _movements.length,
                separatorBuilder: (_, __) => const Divider(
                  color: AppDesignTokens.border,
                  height: 1,
                  thickness: 1,
                ),
                itemBuilder: (context, index) {
                  final m = _movements[index];
                  final isPositive = m.quantityDelta > 0;

                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isPositive
                            ? AppDesignTokens.successBg
                            : AppDesignTokens.dangerBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        isPositive ? Icons.arrow_downward : Icons.arrow_upward,
                        color: isPositive
                            ? AppDesignTokens.successText
                            : AppDesignTokens.dangerText,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      '${loc.type}: ${m.movementType} (${m.referenceType ?? ""})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      '${loc.reference}: ${m.referenceId ?? loc.manual} • ${loc.date}: ${DateFormat("dd/MM/yyyy HH:mm").format(m.createdAt)}',
                      style: const TextStyle(
                        color: AppDesignTokens.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    trailing: Text(
                      isPositive ? '+${m.quantityDelta}' : '${m.quantityDelta}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isPositive
                            ? AppDesignTokens.successText
                            : AppDesignTokens.dangerText,
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
