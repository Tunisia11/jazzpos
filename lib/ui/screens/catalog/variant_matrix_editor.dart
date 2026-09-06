import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/domain/models/variant_matrix.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';

class VariantMatrixEditor extends ConsumerStatefulWidget {
  final String productCode;
  final Money defaultCost;
  final Money defaultPrice;
  final List<MatrixVariantItem> initialVariants;
  final ValueChanged<List<MatrixVariantItem>> onVariantsChanged;

  const VariantMatrixEditor({
    super.key,
    required this.productCode,
    required this.defaultCost,
    required this.defaultPrice,
    this.initialVariants = const [],
    required this.onVariantsChanged,
  });

  @override
  ConsumerState<VariantMatrixEditor> createState() =>
      _VariantMatrixEditorState();
}

class _VariantMatrixEditorState extends ConsumerState<VariantMatrixEditor> {
  // Available attributes from DB
  List<MatrixAttributeValue> _availableSizes = [];
  List<MatrixAttributeValue> _availableColors = [];
  String _sizeTypeId = '';
  String _colorTypeId = '';

  // Selected sets
  final Set<String> _selectedSizeIds = {};
  final Set<String> _selectedColorIds = {};

  List<MatrixVariantItem> _variants = [];
  bool _isLoadingAttrs = true;

  @override
  void initState() {
    super.initState();
    _variants = List.from(widget.initialVariants);
    _loadAttributes();
  }

  Future<void> _loadAttributes() async {
    setState(() => _isLoadingAttrs = true);
    final db = ref.read(databaseProvider);

    final attrTypes = await db.select(db.attributeTypes).get();
    final sizeType = attrTypes.where((a) => a.code == 'SIZE').firstOrNull;
    final colorType = attrTypes.where((a) => a.code == 'COLOR').firstOrNull;

    if (sizeType != null) {
      _sizeTypeId = sizeType.id;
      final sizeValues = await (db.select(
        db.attributeValues,
      )..where((tbl) => tbl.attributeTypeId.equals(sizeType.id))).get();
      _availableSizes = sizeValues
          .map(
            (v) => MatrixAttributeValue(
              id: v.id,
              value: v.value,
              code: v.code.isNotEmpty ? v.code : v.value.toUpperCase(),
            ),
          )
          .toList();
    }

    if (colorType != null) {
      _colorTypeId = colorType.id;
      final colorValues = await (db.select(
        db.attributeValues,
      )..where((tbl) => tbl.attributeTypeId.equals(colorType.id))).get();
      _availableColors = colorValues
          .map(
            (v) => MatrixAttributeValue(
              id: v.id,
              value: v.value,
              code: v.value
                  .substring(0, v.value.length >= 3 ? 3 : v.value.length)
                  .toUpperCase(),
            ),
          )
          .toList();
    }

    setState(() => _isLoadingAttrs = false);
  }

  void _regenerateMatrix() {
    final selectedSizes = _availableSizes
        .where((s) => _selectedSizeIds.contains(s.id))
        .toList();
    final selectedColors = _availableColors
        .where((c) => _selectedColorIds.contains(c.id))
        .toList();

    final attributes = <MatrixAttribute>[];
    if (selectedColors.isNotEmpty) {
      attributes.add(
        MatrixAttribute(
          attributeTypeId: _colorTypeId,
          attributeTypeName: 'Couleur',
          selectedValues: selectedColors,
        ),
      );
    }
    if (selectedSizes.isNotEmpty) {
      attributes.add(
        MatrixAttribute(
          attributeTypeId: _sizeTypeId,
          attributeTypeName: 'Taille',
          selectedValues: selectedSizes,
        ),
      );
    }

    final code = widget.productCode.trim().isEmpty
        ? 'PROD'
        : widget.productCode.trim();

    final generated = VariantMatrixGenerator.generateMatrix(
      productCode: code,
      attributes: attributes,
      defaultCost: widget.defaultCost,
      defaultPrice: widget.defaultPrice,
    );

    setState(() {
      _variants = generated;
    });
    widget.onVariantsChanged(_variants);
  }

  void _bulkApplyPrice() {
    final loc = context.loc;
    final ctrl = TextEditingController(
      text: widget.defaultPrice.format(
        includeCurrency: false,
        useGrouping: false,
      ),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppDesignTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusDialog),
        ),
        title: Text(
          loc.bulkPrice,
          style: const TextStyle(
            color: AppDesignTokens.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: loc.sellingPrice,
            suffixText: loc.currencySymbol,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(loc.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppDesignTokens.primary,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            onPressed: () {
              final p = Money.tryParse(ctrl.text);
              if (p == null || p.isNegative) return;
              setState(() {
                for (final v in _variants) {
                  v.salePrice = p;
                }
              });
              widget.onVariantsChanged(_variants);
              Navigator.of(ctx).pop();
            },
            child: Text(loc.confirm),
          ),
        ],
      ),
    );
  }

  void _bulkApplyStock() {
    final loc = context.loc;
    final ctrl = TextEditingController(text: '10');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppDesignTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusDialog),
        ),
        title: Text(
          loc.bulkStock,
          style: const TextStyle(
            color: AppDesignTokens.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: loc.initialStock),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(loc.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppDesignTokens.primary,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            onPressed: () {
              final qty = int.tryParse(ctrl.text) ?? 0;
              setState(() {
                for (final v in _variants) {
                  v.initialStock = qty;
                }
              });
              widget.onVariantsChanged(_variants);
              Navigator.of(ctx).pop();
            },
            child: Text(loc.confirm),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;

    if (_isLoadingAttrs) {
      return const Center(
        child: CircularProgressIndicator(color: AppDesignTokens.primary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Attribute Selection Panel (Sizes & Colors)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppDesignTokens.surfaceElevated,
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
            border: Border.all(color: AppDesignTokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.grid_on,
                    color: AppDesignTokens.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    loc.matrixGenerator,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Sizes Selection
              Text(
                loc.selectSizes,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableSizes.map((s) {
                  final isSelected = _selectedSizeIds.contains(s.id);
                  return FilterChip(
                    label: Text(
                      s.value,
                      style: TextStyle(
                        color: isSelected
                            ? AppDesignTokens.primary
                            : AppDesignTokens.textPrimary,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    selected: isSelected,
                    backgroundColor: AppDesignTokens.surface,
                    selectedColor: AppDesignTokens.primaryLight,
                    checkmarkColor: AppDesignTokens.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppDesignTokens.radiusSm,
                      ),
                      side: BorderSide(
                        color: isSelected
                            ? AppDesignTokens.primary
                            : AppDesignTokens.border,
                      ),
                    ),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedSizeIds.add(s.id);
                        } else {
                          _selectedSizeIds.remove(s.id);
                        }
                      });
                      _regenerateMatrix();
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Colors Selection
              Text(
                loc.selectColors,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableColors.map((c) {
                  final isSelected = _selectedColorIds.contains(c.id);
                  return FilterChip(
                    label: Text(
                      c.value,
                      style: TextStyle(
                        color: isSelected
                            ? AppDesignTokens.primary
                            : AppDesignTokens.textPrimary,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    selected: isSelected,
                    backgroundColor: AppDesignTokens.surface,
                    selectedColor: AppDesignTokens.primaryLight,
                    checkmarkColor: AppDesignTokens.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppDesignTokens.radiusSm,
                      ),
                      side: BorderSide(
                        color: isSelected
                            ? AppDesignTokens.primary
                            : AppDesignTokens.border,
                      ),
                    ),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedColorIds.add(c.id);
                        } else {
                          _selectedColorIds.remove(c.id);
                        }
                      });
                      _regenerateMatrix();
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Generated Variants Matrix Table
        if (_variants.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${loc.variantDescription} (${_variants.where((v) => v.isEnabled).length} ${loc.active.toLowerCase()} / ${_variants.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppDesignTokens.primary,
                      side: const BorderSide(color: AppDesignTokens.border),
                      backgroundColor: AppDesignTokens.surface,
                    ),
                    onPressed: _bulkApplyPrice,
                    icon: const Icon(Icons.price_change, size: 16),
                    label: Text(
                      loc.bulkPrice,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppDesignTokens.primary,
                      side: const BorderSide(color: AppDesignTokens.border),
                      backgroundColor: AppDesignTokens.surface,
                    ),
                    onPressed: _bulkApplyStock,
                    icon: const Icon(Icons.inventory, size: 16),
                    label: Text(
                      loc.bulkStock,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          Container(
            decoration: BoxDecoration(
              color: AppDesignTokens.surface,
              borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
              border: Border.all(color: AppDesignTokens.border),
              boxShadow: AppDesignTokens.shadowSm,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
              child: Table(
                columnWidths: const {
                  0: FixedColumnWidth(48),
                  1: FlexColumnWidth(2),
                  2: FlexColumnWidth(2),
                  3: FlexColumnWidth(2),
                  4: FlexColumnWidth(1.5),
                  5: FlexColumnWidth(1.5),
                  6: FlexColumnWidth(1.2),
                },
                children: [
                  // Header
                  TableRow(
                    decoration: const BoxDecoration(
                      color: AppDesignTokens.surfaceElevated,
                      border: Border(
                        bottom: BorderSide(color: AppDesignTokens.border),
                      ),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Center(
                          child: Text(
                            loc.active,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppDesignTokens.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          loc.variantDescription,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          '${loc.sku} / Réf',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          loc.barcode,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          loc.sellingPrice,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          loc.costPrice,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          loc.initialStock,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Rows
                  ..._variants.map((v) {
                    return TableRow(
                      decoration: BoxDecoration(
                        color: v.isEnabled
                            ? Colors.transparent
                            : AppDesignTokens.surfaceElevated.withValues(
                                alpha: 0.6,
                              ),
                        border: const Border(
                          bottom: BorderSide(
                            color: AppDesignTokens.border,
                            width: 0.5,
                          ),
                        ),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Checkbox(
                            value: v.isEnabled,
                            activeColor: AppDesignTokens.primary,
                            onChanged: (val) {
                              setState(() => v.isEnabled = val ?? true);
                              widget.onVariantsChanged(_variants);
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 8,
                          ),
                          child: Text(
                            v.attributeDescription,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: v.isEnabled
                                  ? AppDesignTokens.textPrimary
                                  : AppDesignTokens.textMuted,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: TextFormField(
                            initialValue: v.sku,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppDesignTokens.textPrimary,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                            onChanged: (val) {
                              v.sku = val;
                              widget.onVariantsChanged(_variants);
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: TextFormField(
                            initialValue: v.barcode,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppDesignTokens.textPrimary,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                            onChanged: (val) {
                              v.barcode = val;
                              widget.onVariantsChanged(_variants);
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: TextFormField(
                            initialValue: v.salePrice.format(
                              includeCurrency: false,
                              useGrouping: false,
                            ),
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppDesignTokens.textPrimary,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                            onChanged: (val) {
                              v.salePrice = Money.fromTnd(
                                double.tryParse(val) ?? 0,
                              );
                              widget.onVariantsChanged(_variants);
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: TextFormField(
                            initialValue: v.costPrice.format(
                              includeCurrency: false,
                              useGrouping: false,
                            ),
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppDesignTokens.textPrimary,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                            onChanged: (val) {
                              v.costPrice = Money.fromTnd(
                                double.tryParse(val) ?? 0,
                              );
                              widget.onVariantsChanged(_variants);
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: TextFormField(
                            initialValue: '${v.initialStock}',
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppDesignTokens.textPrimary,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                            onChanged: (val) {
                              v.initialStock = int.tryParse(val) ?? 0;
                              widget.onVariantsChanged(_variants);
                            },
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        ] else
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppDesignTokens.surface,
              borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
              border: Border.all(color: AppDesignTokens.border),
            ),
            child: Text(
              '${loc.selectSizes} & ${loc.selectColors}',
              style: const TextStyle(color: AppDesignTokens.textSecondary),
            ),
          ),
      ],
    );
  }
}
