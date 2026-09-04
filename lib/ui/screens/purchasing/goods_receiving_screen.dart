import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/catalog_service.dart';
import 'package:jazzpos/domain/services/purchase_service.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/providers/catalog_provider.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';
import 'package:jazzpos/ui/widgets/barcode_scanner_listener.dart';
import 'package:jazzpos/ui/widgets/money_display.dart';

class GoodsReceivingScreen extends ConsumerStatefulWidget {
  final String? purchaseOrderId;

  const GoodsReceivingScreen({super.key, this.purchaseOrderId});

  @override
  ConsumerState<GoodsReceivingScreen> createState() => _GoodsReceivingScreenState();
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
    final existingIndex = _lines.indexWhere((l) => l.variantId == variant.variantId);

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
    if (_selectedSupplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner un fournisseur'), backgroundColor: AppTheme.error),
      );
      return;
    }
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez ajouter au moins un article reçu'), backgroundColor: AppTheme.error),
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
        invoiceReference: _invoiceRefCtrl.text.trim().isNotEmpty ? _invoiceRefCtrl.text.trim() : null,
        receivedById: auth.user?.id ?? 'system',
        storeId: 'STORE-01',
        lines: _lines,
        notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Réception de marchandises enregistrée avec succès !'), backgroundColor: AppTheme.success),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogState = ref.watch(catalogNotifierProvider);

    Money totalCost = Money.zero;
    for (final l in _lines) {
      totalCost = totalCost + (l.unitCost * l.quantityReceived);
    }

    return BarcodeScannerListener(
      onBarcodeScanned: (code) async {
        final matches = await ref.read(catalogServiceProvider).searchVariants(code);
        if (matches.isNotEmpty) {
          _addVariantToReceiving(matches.first);
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Réception Marchandises Fournisseur (Bon de Livraison)'),
          backgroundColor: AppTheme.surface,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _submitReceiving,
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, foregroundColor: Colors.white),
                icon: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle_outline, size: 20),
                label: Text(_isSaving ? 'ENREGISTREMENT...' : 'VALIDER LA RÉCEPTION'),
              ),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(20),
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
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: DropdownButtonFormField<String>(
                                    value: _selectedSupplierId,
                                    decoration: const InputDecoration(labelText: 'Fournisseur *'),
                                    items: _suppliers.isEmpty
                                        ? [const DropdownMenuItem(value: null, child: Text('Aucun fournisseur (par défaut)'))]
                                        : _suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                                    onChanged: (val) => setState(() => _selectedSupplierId = val),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: _invoiceRefCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'N° Bon Livraison / Facture',
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
                                color: AppTheme.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: _lines.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'Aucun article dans cette réception.\nSélectionnez ou scannez des articles à droite.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: AppTheme.textSecondary),
                                      ),
                                    )
                                  : ListView.separated(
                                      itemCount: _lines.length,
                                      separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1),
                                      itemBuilder: (context, index) {
                                        final line = _lines[index];
                                        final variant = _variantMap[line.variantId];

                                        return Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                flex: 4,
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      variant?.productName ?? 'Article',
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                                    ),
                                                    Text(
                                                      '${variant?.variantDescription ?? ""} • SKU: ${variant?.sku ?? ""}',
                                                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                                    ),
                                                  ],
                                                ),
                                              ),

                                              // Qty Received
                                              Expanded(
                                                flex: 2,
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    const Text('Qté Reçue', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                                                    TextFormField(
                                                      initialValue: '${line.quantityReceived}',
                                                      keyboardType: TextInputType.number,
                                                      onChanged: (v) {
                                                        final val = int.tryParse(v) ?? 1;
                                                        setState(() {
                                                          _lines[index] = ReceivedLineInput(
                                                            variantId: line.variantId,
                                                            quantityReceived: val,
                                                            quantityDamaged: line.quantityDamaged,
                                                            unitCost: line.unitCost,
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
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    const Text('Défectueux', style: TextStyle(fontSize: 11, color: AppTheme.error)),
                                                    TextFormField(
                                                      initialValue: '${line.quantityDamaged}',
                                                      keyboardType: TextInputType.number,
                                                      onChanged: (v) {
                                                        final val = int.tryParse(v) ?? 0;
                                                        setState(() {
                                                          _lines[index] = ReceivedLineInput(
                                                            variantId: line.variantId,
                                                            quantityReceived: line.quantityReceived,
                                                            quantityDamaged: val,
                                                            unitCost: line.unitCost,
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
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    const Text('Coût U. (TND)', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                                                    TextFormField(
                                                      initialValue: line.unitCost.format(includeCurrency: false, useGrouping: false),
                                                      keyboardType: TextInputType.number,
                                                      onChanged: (v) {
                                                        final val = Money.fromTnd(double.tryParse(v) ?? 0);
                                                        setState(() {
                                                          _lines[index] = ReceivedLineInput(
                                                            variantId: line.variantId,
                                                            quantityReceived: line.quantityReceived,
                                                            quantityDamaged: line.quantityDamaged,
                                                            unitCost: val,
                                                          );
                                                        });
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),

                                              IconButton(
                                                icon: const Icon(Icons.close, color: AppTheme.error, size: 18),
                                                onPressed: () => setState(() => _lines.removeAt(index)),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
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
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Ajouter des articles', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _searchCtrl,
                              decoration: const InputDecoration(
                                hintText: 'Rechercher ou scanner code-barres...',
                                prefixIcon: Icon(Icons.search),
                              ),
                              onChanged: (val) => ref.read(catalogNotifierProvider.notifier).search(val),
                            ),
                            const SizedBox(height: 12),

                            Expanded(
                              child: ListView.separated(
                                itemCount: catalogState.variants.length,
                                separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1),
                                itemBuilder: (context, index) {
                                  final v = catalogState.variants[index];
                                  return ListTile(
                                    dense: true,
                                    title: Text(v.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text('${v.variantDescription} • Coût: ${v.costPrice.format()}'),
                                    trailing: const Icon(Icons.add_circle, color: AppTheme.primaryLight, size: 20),
                                    onTap: () => _addVariantToReceiving(v),
                                  );
                                },
                              ),
                            ),

                            const Divider(color: AppTheme.border, height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('TOTAL RÉCEPTION :', style: TextStyle(fontWeight: FontWeight.bold)),
                                MoneyDisplay(amount: totalCost, fontSize: 18, color: AppTheme.primaryLight),
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
