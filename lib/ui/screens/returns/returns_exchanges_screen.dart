import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/models/cart_item.dart';
import 'package:jazzpos/domain/services/exchange_service.dart';
import 'package:jazzpos/domain/services/return_service.dart';
import 'package:jazzpos/hardware/hardware_manager.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/providers/catalog_provider.dart';
import 'package:jazzpos/providers/shift_provider.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';
import 'package:jazzpos/ui/widgets/barcode_scanner_listener.dart';
import 'package:jazzpos/ui/widgets/money_display.dart';

class ReturnsExchangesScreen extends ConsumerStatefulWidget {
  final String storeId;
  final String registerId;

  const ReturnsExchangesScreen({
    super.key,
    this.storeId = 'STORE-01',
    this.registerId = 'REG-01',
  });

  @override
  ConsumerState<ReturnsExchangesScreen> createState() =>
      _ReturnsExchangesScreenState();
}

class _ReturnsExchangesScreenState
    extends ConsumerState<ReturnsExchangesScreen> {
  final _receiptSearchCtrl = TextEditingController();

  Sale? _foundSale;
  List<SaleLine> _saleLines = [];
  final Map<String, int> _selectedReturnQtys = {};
  final Map<String, String> _returnConditions = {};
  final Map<String, String> _returnReasons = {};

  bool _isExchangeMode = false;
  CartItem? _replacementItem;
  String _refundMethod = AppConstants.paymentCash;
  bool _isSearching = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _receiptSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchSale(String receiptNum) async {
    final clean = receiptNum.trim();
    if (clean.isEmpty) return;

    setState(() {
      _isSearching = true;
      _foundSale = null;
      _saleLines = [];
      _selectedReturnQtys.clear();
      _returnConditions.clear();
      _returnReasons.clear();
      _replacementItem = null;
    });

    final db = ref.read(databaseProvider);
    final sale = await (db.select(
      db.sales,
    )..where((tbl) => tbl.receiptNumber.equals(clean))).getSingleOrNull();

    if (sale != null) {
      final lines = await (db.select(
        db.saleLines,
      )..where((tbl) => tbl.saleId.equals(sale.id))).get();
      if (mounted) {
        setState(() {
          _foundSale = sale;
          _saleLines = lines;
          _isSearching = false;
          for (final l in lines) {
            _selectedReturnQtys[l.id] = 0;
            _returnConditions[l.id] = AppConstants.returnConditionSellable;
            _returnReasons[l.id] = 'Taille non adaptée';
          }
        });
      }
    } else {
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Aucun ticket trouvé pour "$clean"'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Money get _totalRefundAmount {
    Money sum = Money.zero;
    for (final line in _saleLines) {
      final qty = _selectedReturnQtys[line.id] ?? 0;
      if (qty > 0) {
        sum = sum + (Money.fromMillimes(line.unitPriceMillimes) * qty);
      }
    }
    return sum;
  }

  Future<void> _submitReturn() async {
    final auth = ref.read(authNotifierProvider);
    final shift = ref.read(shiftNotifierProvider).activeShift;

    if (shift == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez d\'abord ouvrir une session de caisse'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    final returnItems = <ReturnLineItem>[];
    for (final line in _saleLines) {
      final qty = _selectedReturnQtys[line.id] ?? 0;
      if (qty > 0) {
        returnItems.add(
          ReturnLineItem(
            originalSaleLineId: line.id,
            variantId: line.variantId,
            quantity: qty,
            refundUnitPrice: Money.fromMillimes(line.unitPriceMillimes),
            condition:
                _returnConditions[line.id] ??
                AppConstants.returnConditionSellable,
          ),
        );
      }
    }

    if (returnItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Veuillez sélectionner au moins un article à retourner',
          ),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      if (!_isExchangeMode) {
        // Simple Return
        final returnService = ref.read(returnServiceProvider);
        final result = await returnService.processReturn(
          ReturnRequest(
            originalSaleId: _foundSale?.id,
            storeId: widget.storeId,
            registerId: widget.registerId,
            shiftId: shift.id,
            cashierId: auth.user?.id ?? 'system',
            refundMethod: _refundMethod,
            reason: 'Retour article',
            items: returnItems,
          ),
        );

        if (_refundMethod == AppConstants.paymentCash) {
          try {
            await HardwareManager.instance.cashDrawer.openDrawer();
          } catch (_) {}
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Retour #${result.returnNumber} validé avec succès !',
              ),
              backgroundColor: AppTheme.success,
            ),
          );
          _searchSale(_receiptSearchCtrl.text);
        }
      } else {
        // Exchange Mode
        if (_replacementItem == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Veuillez sélectionner un article de remplacement'),
              backgroundColor: AppTheme.error,
            ),
          );
          setState(() => _isSubmitting = false);
          return;
        }

        final exchangeService = ref.read(exchangeServiceProvider);
        final result = await exchangeService.processExchange(
          ExchangeRequest(
            originalSaleId: _foundSale?.id,
            storeId: widget.storeId,
            registerId: widget.registerId,
            shiftId: shift.id,
            cashierId: auth.user?.id ?? 'system',
            returnedItems: returnItems,
            newItems: [_replacementItem!],
            paymentMethod: _refundMethod,
            reason: 'Échange vêtement (taille / modèle)',
          ),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Échange validé ! Différence : ${result.difference.format()}',
              ),
              backgroundColor: AppTheme.success,
            ),
          );
          _searchSale(_receiptSearchCtrl.text);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogState = ref.watch(catalogNotifierProvider);

    return BarcodeScannerListener(
      onBarcodeScanned: (code) {
        _receiptSearchCtrl.text = code;
        _searchSale(code);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Retours & Échanges de Vêtements'),
          backgroundColor: AppTheme.surface,
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search Bar Card
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
                      flex: 4,
                      child: TextField(
                        controller: _receiptSearchCtrl,
                        decoration: const InputDecoration(
                          labelText:
                              'Numéro de Ticket ou Scanner Code-barres Ticket',
                          hintText: 'ex: REC-20260904-0001',
                          prefixIcon: Icon(Icons.receipt),
                        ),
                        onSubmitted: _searchSale,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _isSearching
                          ? null
                          : () => _searchSale(_receiptSearchCtrl.text),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 50),
                      ),
                      icon: _isSearching
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.search),
                      label: const Text('RECHERCHER TICKET'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              if (_foundSale != null) ...[
                // Ticket Summary Header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161F2E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.receipt_long,
                        color: AppTheme.primaryLight,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Ticket: ${_foundSale!.receiptNumber}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Date: ${DateFormat('dd/MM/yyyy HH:mm').format(_foundSale!.createdAt)}',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        'Total Vente: ',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      MoneyDisplay(
                        amount: Money.fromMillimes(_foundSale!.totalMillimes),
                        fontSize: 16,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Mode Selector: Return vs Exchange
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Remboursement / Avoir'),
                      selected: !_isExchangeMode,
                      onSelected: (_) =>
                          setState(() => _isExchangeMode = false),
                    ),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: const Text(
                        'Échange de Vêtement (Taille / Couleur)',
                      ),
                      selected: _isExchangeMode,
                      onSelected: (_) => setState(() => _isExchangeMode = true),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Content Split
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left: Original Items selection
                      Expanded(
                        flex: 6,
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
                              const Text(
                                'Articles achetés à retourner :',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: ListView.separated(
                                  itemCount: _saleLines.length,
                                  separatorBuilder: (_, __) => const Divider(
                                    color: AppTheme.border,
                                    height: 1,
                                  ),
                                  itemBuilder: (context, index) {
                                    final line = _saleLines[index];
                                    final returnQty =
                                        _selectedReturnQtys[line.id] ?? 0;
                                    final condition =
                                        _returnConditions[line.id] ??
                                        AppConstants.returnConditionSellable;

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          Checkbox(
                                            value: returnQty > 0,
                                            onChanged: (val) {
                                              setState(() {
                                                _selectedReturnQtys[line.id] =
                                                    (val == true) ? 1 : 0;
                                              });
                                            },
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  line.productName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                Text(
                                                  '${line.variantDescription} • Acheté : ${line.quantity}x • P.U: ${Money.fromMillimes(line.unitPriceMillimes).format()}',
                                                ),
                                              ],
                                            ),
                                          ),

                                          if (returnQty > 0) ...[
                                            // Condition: Remettable en vente ou Défectueux
                                            DropdownButton<String>(
                                              value: condition,
                                              dropdownColor: AppTheme.surface,
                                              items: const [
                                                DropdownMenuItem(
                                                  value: AppConstants
                                                      .returnConditionSellable,
                                                  child: Text(
                                                    'Re-vendable (Rayon)',
                                                  ),
                                                ),
                                                DropdownMenuItem(
                                                  value: AppConstants
                                                      .returnConditionDamaged,
                                                  child: Text(
                                                    'Défectueux (Isoler)',
                                                  ),
                                                ),
                                              ],
                                              onChanged: (v) => setState(
                                                () =>
                                                    _returnConditions[line.id] =
                                                        v!,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            // Qty
                                            Container(
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF161F2E),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: AppTheme.border,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.remove,
                                                      size: 14,
                                                    ),
                                                    onPressed: returnQty > 1
                                                        ? () => setState(
                                                            () =>
                                                                _selectedReturnQtys[line
                                                                        .id] =
                                                                    returnQty -
                                                                    1,
                                                          )
                                                        : null,
                                                  ),
                                                  Text(
                                                    '$returnQty',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.add,
                                                      size: 14,
                                                    ),
                                                    onPressed:
                                                        returnQty <
                                                            line.quantity
                                                        ? () => setState(
                                                            () =>
                                                                _selectedReturnQtys[line
                                                                        .id] =
                                                                    returnQty +
                                                                    1,
                                                          )
                                                        : null,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 16),

                      // Right: Exchange Item Selection OR Refund Summary
                      Expanded(
                        flex: 5,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: _isExchangeMode
                              ? _buildExchangePane(catalogState)
                              : _buildReturnPane(),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.assignment_return_outlined,
                          size: 64,
                          color: AppTheme.textSecondary,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Saisissez le numéro de ticket ou scannez le ticket de caisse',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 16,
                          ),
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

  Widget _buildReturnPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Détails du Remboursement',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Montant à Rembourser :'),
            MoneyDisplay(
              amount: _totalRefundAmount,
              fontSize: 24,
              color: AppTheme.warning,
            ),
          ],
        ),
        const SizedBox(height: 16),

        const Text(
          'Mode de Remboursement :',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ChoiceChip(
              label: const Text('Espèces'),
              selected: _refundMethod == AppConstants.paymentCash,
              onSelected: (_) =>
                  setState(() => _refundMethod = AppConstants.paymentCash),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Avoir Magasin'),
              selected: _refundMethod == AppConstants.paymentStoreCredit,
              onSelected: (_) => setState(
                () => _refundMethod = AppConstants.paymentStoreCredit,
              ),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Carte'),
              selected: _refundMethod == AppConstants.paymentCard,
              onSelected: (_) =>
                  setState(() => _refundMethod = AppConstants.paymentCard),
            ),
          ],
        ),

        const Spacer(),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: (_totalRefundAmount <= Money.zero || _isSubmitting)
                ? null
                : _submitReturn,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.warning,
              foregroundColor: Colors.black,
            ),
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.black,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.check_circle, size: 20),
            label: Text(
              _isSubmitting ? 'VALIDATION...' : 'VALIDER LE REMBOURSEMENT',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExchangePane(CatalogState catalogState) {
    Money newTotal = _replacementItem != null
        ? _replacementItem!.total
        : Money.zero;
    Money diff = newTotal - _totalRefundAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sélectionner le nouvel article de remplacement :',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),

        if (_replacementItem != null)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.primary),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _replacementItem!.productName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_replacementItem!.variantDescription} • ${_replacementItem!.unitPrice.format()}',
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _replacementItem = null),
                ),
              ],
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: catalogState.variants.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: AppTheme.border, height: 1),
              itemBuilder: (context, index) {
                final v = catalogState.variants[index];
                return ListTile(
                  dense: true,
                  title: Text(
                    v.productName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${v.variantDescription} • ${v.salePrice.format()}',
                  ),
                  trailing: const Icon(
                    Icons.add_circle,
                    color: AppTheme.primaryLight,
                    size: 20,
                  ),
                  onTap: () {
                    setState(() {
                      _replacementItem = CartItem(
                        variantId: v.variantId,
                        productId: v.productId,
                        productName: v.productName,
                        variantDescription: v.variantDescription,
                        sku: v.sku,
                        barcode: v.barcode,
                        unitPrice: v.salePrice,
                        originalPrice: v.salePrice,
                        quantity: 1,
                        taxRatePercent: v.taxRatePercent,
                        unitCost: v.costPrice,
                      );
                    });
                  },
                );
              },
            ),
          ),

        const Divider(color: AppTheme.border, height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Différence de Prix :'),
            if (diff == Money.zero)
              const Text(
                '0.000 TND (Échange Égal)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.success,
                  fontSize: 16,
                ),
              )
            else if (diff > Money.zero)
              Text(
                '+${diff.format()} (Client Paye)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueAccent,
                  fontSize: 16,
                ),
              )
            else
              Text(
                '-${diff.abs.format()} (À Rendre au Client)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.warning,
                  fontSize: 16,
                ),
              ),
          ],
        ),

        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed:
                (_replacementItem == null ||
                    _totalRefundAmount <= Money.zero ||
                    _isSubmitting)
                ? null
                : _submitReturn,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.swap_horiz, size: 20),
            label: Text(
              _isSubmitting ? 'VALIDATION...' : 'VALIDER L\'ÉCHANGE DE TAILLE',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
