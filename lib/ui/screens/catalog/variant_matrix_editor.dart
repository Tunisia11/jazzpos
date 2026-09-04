import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/domain/models/variant_matrix.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';

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
    final ctrl = TextEditingController(
      text: widget.defaultPrice.format(
        includeCurrency: false,
        useGrouping: false,
      ),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Appliquer un prix à toutes les variantes'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Nouveau prix de vente (TND)',
            suffixText: 'TND',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              final p = Money.fromTnd(double.tryParse(ctrl.text) ?? 0);
              setState(() {
                for (final v in _variants) {
                  v.salePrice = p;
                }
              });
              widget.onVariantsChanged(_variants);
              Navigator.of(ctx).pop();
            },
            child: const Text('Appliquer'),
          ),
        ],
      ),
    );
  }

  void _bulkApplyStock() {
    final ctrl = TextEditingController(text: '10');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Appliquer un stock initial à toutes les variantes'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Quantité initiale par variante',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
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
            child: const Text('Appliquer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingAttrs) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Attribute Selection Panel (Sizes & Colors)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161F2E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.grid_on, color: AppTheme.primaryLight, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Générateur de Matrice Tailles & Couleurs (Prêt-à-Porter)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Sizes Selection
              const Text(
                '1. Sélectionnez les Tailles :',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableSizes.map((s) {
                  final isSelected = _selectedSizeIds.contains(s.id);
                  return FilterChip(
                    label: Text(s.value),
                    selected: isSelected,
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
              const Text(
                '2. Sélectionnez les Couleurs :',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableColors.map((c) {
                  final isSelected = _selectedColorIds.contains(c.id);
                  return FilterChip(
                    label: Text(c.value),
                    selected: isSelected,
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
                'Variantes générées (${_variants.where((v) => v.isEnabled).length} actives / ${_variants.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _bulkApplyPrice,
                    icon: const Icon(Icons.price_change, size: 16),
                    label: const Text(
                      'Prix en masse',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _bulkApplyStock,
                    icon: const Icon(Icons.inventory, size: 16),
                    label: const Text(
                      'Stock initial en masse',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
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
                    color: Color(0xFF161F2E),
                    border: Border(bottom: BorderSide(color: AppTheme.border)),
                  ),
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: Center(
                        child: Text(
                          'Actif',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: Text(
                        'Variante',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: Text(
                        'SKU / Réf',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: Text(
                        'Code-barres',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: Text(
                        'Prix Vente',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: Text(
                        'Coût Achat',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: Text(
                        'Stock Init.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
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
                          : Colors.black.withValues(alpha: 0.3),
                      border: const Border(
                        bottom: BorderSide(color: AppTheme.border, width: 0.5),
                      ),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Checkbox(
                          value: v.isEnabled,
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
                                ? Colors.white
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: TextFormField(
                          initialValue: v.sku,
                          style: const TextStyle(fontSize: 12),
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
                          style: const TextStyle(fontSize: 12),
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
                          style: const TextStyle(fontSize: 12),
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
                          style: const TextStyle(fontSize: 12),
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
        ] else
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Text(
              'Sélectionnez au moins une taille ou une couleur pour générer automatiquement la matrice de variantes.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
      ],
    );
  }
}
