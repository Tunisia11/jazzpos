import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/catalog_service.dart';
import 'package:jazzpos/domain/services/purchase_service.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/providers/catalog_provider.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'package:jazzpos/ui/widgets/barcode_scanner_listener.dart';
import 'package:jazzpos/ui/widgets/common/app_button.dart';
import 'package:jazzpos/ui/widgets/money_display.dart';

class GoodsReceivingScreen extends ConsumerStatefulWidget {
  final String? purchaseOrderId;

  const GoodsReceivingScreen({super.key, this.purchaseOrderId});

  @override
  ConsumerState<GoodsReceivingScreen> createState() =>
      _GoodsReceivingScreenState();
}

class _GoodsReceivingScreenState extends ConsumerState<GoodsReceivingScreen> {
  final _invoiceRefCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  List<Supplier> _suppliers = [];
  String? _selectedSupplierId;
  final List<ReceivedLineInput> _lines = [];
  final Map<String, VariantSearchResult> _variantMap = {};

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  @override
  void dispose() {
    _invoiceRefCtrl.dispose();
    _notesCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    setState(() => _isLoading = true);
    final db = ref.read(databaseProvider);
    final suppliers = await db.select(db.suppliers).get();

    if (mounted) {
      setState(() {
        _suppliers = suppliers;
        if (_suppliers.isNotEmpty) {
          _selectedSupplierId = _suppliers.first.id;
        }
        _isLoading = false;
      });
    }
  }

  void _addVariantToReceiving(VariantSearchResult variant) {
    _variantMap[variant.variantId] = variant;
    final existingIndex = _lines.indexWhere(
      (l) => l.variantId == variant.variantId,
    );

    setState(() {
      if (existingIndex >= 0) {
        final cur = _lines[existingIndex];
        _lines[existingIndex] = ReceivedLineInput(
          variantId: cur.variantId,
          quantityReceived: cur.quantityReceived + 1,
          quantityDamaged: cur.quantityDamaged,
          unitCost: cur.unitCost,
        );
      } else {
        _lines.add(
          ReceivedLineInput(
            variantId: variant.variantId,
            quantityReceived: 1,
            unitCost: variant.costPrice,
          ),
        );
      }
    });
  }

  Future<void> _submitReceiving() async {
    final loc = context.loc;
    if (_selectedSupplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.selectSupplierPrompt),
          backgroundColor: AppDesignTokens.danger,
        ),
      );
      return;
    }
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.addAtLeastOneArticlePrompt),
          backgroundColor: AppDesignTokens.danger,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final purchaseService = ref.read(purchaseServiceProvider);
      final auth = ref.read(authNotifierProvider);

      await purchaseService.receiveGoods(
        purchaseOrderId: widget.purchaseOrderId,
        supplierId: _selectedSupplierId!,
        invoiceReference: _invoiceRefCtrl.text.trim().isNotEmpty
            ? _invoiceRefCtrl.text.trim()
            : null,
        receivedById: auth.user?.id ?? 'system',
        storeId: 'STORE-01',
        lines: _lines,
        notes: _notesCtrl.text.trim().isNotEmpty
            ? _notesCtrl.text.trim()
            : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.receivingSavedSuccess),
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
    final catalogState = ref.watch(catalogNotifierProvider);

    Money totalCost = Money.zero;
    for (final l in _lines) {
      totalCost = totalCost + (l.unitCost * l.quantityReceived);
    }

    return BarcodeScannerListener(
      onBarcodeScanned: (code) async {
        final matches = await ref
            .read(catalogServiceProvider)
            .searchVariants(code);
        if (matches.isNotEmpty) {
          _addVariantToReceiving(matches.first);
        }
      },
      child: Scaffold(
        backgroundColor: AppDesignTokens.canvas,
        appBar: AppBar(
          title: Text(
            '${loc.goodsReceivingTitle} (${loc.invoiceOrDeliveryNote})',
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
                onPressed: _isSaving ? null : _submitReceiving,
                variant: AppButtonVariant.success,
                isLoading: _isSaving,
                icon: Icons.check_circle_outline,
                label: loc.validateReceiving.toUpperCase(),
              ),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppDesignTokens.primary,
                ),
              )
            : Padding(
                padding: const EdgeInsetsDirectional.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column: Supplier & Receiving Lines
                    Expanded(
                      flex: 7,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header Card
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppDesignTokens.surface,
                              borderRadius: BorderRadius.circular(
                                AppDesignTokens.radiusCard,
                              ),
                              border: Border.all(color: AppDesignTokens.border),
                              boxShadow: AppDesignTokens.shadowSm,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _selectedSupplierId,
                                    decoration: InputDecoration(
                                      labelText: '${loc.supplier} *',
                                    ),
                                    items: _suppliers.isEmpty
                                        ? [
                                            DropdownMenuItem(
                                              value: null,
                                              child: Text(loc.none),
                                            ),
                                          ]
                                        : _suppliers
                                              .map(
                                                (s) => DropdownMenuItem(
                                                  value: s.id,
                                                  child: Text(s.name),
                                                ),
                                              )
                                              .toList(),
                                    onChanged: (val) => setState(
                                      () => _selectedSupplierId = val,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: _invoiceRefCtrl,
                                    style: const TextStyle(
                                      color: AppDesignTokens.textPrimary,
                                    ),
                                    decoration: InputDecoration(
                                      labelText: loc.invoiceOrDeliveryNote,
                                      hintText: 'ex: BL-2026-9812',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Table of Received Lines
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppDesignTokens.surface,
                                borderRadius: BorderRadius.circular(
                                  AppDesignTokens.radiusCard,
                                ),
                                border: Border.all(
                                  color: AppDesignTokens.border,
                                ),
                                boxShadow: AppDesignTokens.shadowSm,
                              ),
                              child: _lines.isEmpty
                                  ? Center(
                                      child: Text(
                                        loc.noArticlesInReceiving,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: AppDesignTokens.textSecondary,
                                        ),
                                      ),
                                    )
                                  : ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                        AppDesignTokens.radiusCard,
                                      ),
                                      child: ListView.separated(
                                        itemCount: _lines.length,
                                        separatorBuilder: (_, __) =>
                                            const Divider(
                                              color: AppDesignTokens.border,
                                              height: 1,
                                              thickness: 1,
                                            ),
                                        itemBuilder: (context, index) {
                                          final line = _lines[index];
                                          final variant =
                                              _variantMap[line.variantId];

                                          return Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  flex: 4,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        variant?.productName ??
                                                            'Article',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 14,
                                                          color: AppDesignTokens
                                                              .textPrimary,
                                                        ),
                                                      ),
                                                      Text(
                                                        '${variant?.variantDescription ?? ""} • ${loc.sku}: ${variant?.sku ?? ""}',
                                                        style: const TextStyle(
                                                          color: AppDesignTokens
                                                              .textSecondary,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),

                                                // Qty Received
                                                Expanded(
                                                  flex: 2,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        loc.qtyReceived,
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color: AppDesignTokens
                                                              .textSecondary,
                                                        ),
                                                      ),
                                                      TextFormField(
                                                        initialValue:
                                                            '${line.quantityReceived}',
                                                        keyboardType:
                                                            TextInputType
                                                                .number,
                                                        style: const TextStyle(
                                                          color: AppDesignTokens
                                                              .textPrimary,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                        onChanged: (v) {
                                                          final val =
                                                              int.tryParse(v) ??
                                                              1;
                                                          setState(() {
                                                            _lines[index] = ReceivedLineInput(
                                                              variantId: line
                                                                  .variantId,
                                                              quantityReceived:
                                                                  val,
                                                              quantityDamaged: line
                                                                  .quantityDamaged,
                                                              unitCost:
                                                                  line.unitCost,
                                                            );
                                                          });
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),

                                                // Qty Damaged
                                                Expanded(
                                                  flex: 2,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        loc.qtyDamaged,
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color: AppDesignTokens
                                                              .dangerText,
                                                        ),
                                                      ),
                                                      TextFormField(
                                                        initialValue:
                                                            '${line.quantityDamaged}',
                                                        keyboardType:
                                                            TextInputType
                                                                .number,
                                                        style: const TextStyle(
                                                          color: AppDesignTokens
                                                              .dangerText,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                        onChanged: (v) {
                                                          final val =
                                                              int.tryParse(v) ??
                                                              0;
                                                          setState(() {
                                                            _lines[index] =
                                                                ReceivedLineInput(
                                                                  variantId: line
                                                                      .variantId,
                                                                  quantityReceived:
                                                                      line.quantityReceived,
                                                                  quantityDamaged:
                                                                      val,
                                                                  unitCost: line
                                                                      .unitCost,
                                                                );
                                                          });
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),

                                                // Unit Cost
                                                Expanded(
                                                  flex: 2,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        '${loc.costPrice} (${loc.currencySymbol})',
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color: AppDesignTokens
                                                              .textSecondary,
                                                        ),
                                                      ),
                                                      TextFormField(
                                                        initialValue: line
                                                            .unitCost
                                                            .format(
                                                              includeCurrency:
                                                                  false,
                                                              useGrouping:
                                                                  false,
                                                            ),
                                                        keyboardType:
                                                            TextInputType
                                                                .number,
                                                        style: const TextStyle(
                                                          color: AppDesignTokens
                                                              .textPrimary,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                        onChanged: (v) {
                                                          final val =
                                                              Money.fromTnd(
                                                                double.tryParse(
                                                                      v,
                                                                    ) ??
                                                                    0,
                                                              );
                                                          setState(() {
                                                            _lines[index] = ReceivedLineInput(
                                                              variantId: line
                                                                  .variantId,
                                                              quantityReceived:
                                                                  line.quantityReceived,
                                                              quantityDamaged: line
                                                                  .quantityDamaged,
                                                              unitCost: val,
                                                            );
                                                          });
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                ),

                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.close,
                                                    color:
                                                        AppDesignTokens.danger,
                                                    size: 18,
                                                  ),
                                                  onPressed: () => setState(
                                                    () =>
                                                        _lines.removeAt(index),
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

                    const SizedBox(width: 16),

                    // Right Column: Article Search / Quick Picker
                    Expanded(
                      flex: 4,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppDesignTokens.surface,
                          borderRadius: BorderRadius.circular(
                            AppDesignTokens.radiusCard,
                          ),
                          border: Border.all(color: AppDesignTokens.border),
                          boxShadow: AppDesignTokens.shadowSm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loc.addArticles,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: AppDesignTokens.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _searchCtrl,
                              style: const TextStyle(
                                color: AppDesignTokens.textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText: loc.searchProductOrBarcode,
                                prefixIcon: const Icon(
                                  Icons.search,
                                  color: AppDesignTokens.textSecondary,
                                ),
                              ),
                              onChanged: (val) => ref
                                  .read(catalogNotifierProvider.notifier)
                                  .search(val),
                            ),
                            const SizedBox(height: 12),

                            Expanded(
                              child: ListView.separated(
                                itemCount: catalogState.variants.length,
                                separatorBuilder: (_, __) => const Divider(
                                  color: AppDesignTokens.border,
                                  height: 1,
                                ),
                                itemBuilder: (context, index) {
                                  final v = catalogState.variants[index];
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                      v.productName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: AppDesignTokens.textPrimary,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${v.variantDescription} • ${loc.costPrice}: ${v.costPrice.format()}',
                                      style: const TextStyle(
                                        color: AppDesignTokens.textSecondary,
                                      ),
                                    ),
                                    trailing: const Icon(
                                      Icons.add_circle,
                                      color: AppDesignTokens.primary,
                                      size: 20,
                                    ),
                                    onTap: () => _addVariantToReceiving(v),
                                  );
                                },
                              ),
                            ),

                            const Divider(
                              color: AppDesignTokens.border,
                              height: 16,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${loc.total.toUpperCase()} :',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppDesignTokens.textPrimary,
                                  ),
                                ),
                                MoneyDisplay(
                                  amount: totalCost,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
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
      ),
    );
  }
}
