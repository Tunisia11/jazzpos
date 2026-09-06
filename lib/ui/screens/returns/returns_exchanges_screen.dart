import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/localization/app_localizations.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
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
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
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
        final loc = context.loc;
        setState(() {
          _foundSale = sale;
          _saleLines = lines;
          _isSearching = false;
          for (final l in lines) {
            _selectedReturnQtys[l.id] = 0;
            _returnConditions[l.id] = AppConstants.returnConditionSellable;
            _returnReasons[l.id] = loc.returnReasonSize;
          }
        });
      }
    } else {
      if (mounted) {
        final loc = context.loc;
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.ticketNotFound(clean)),
            backgroundColor: AppDesignTokens.danger,
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
    final loc = context.loc;
    final auth = ref.read(authNotifierProvider);
    final shift = ref.read(shiftNotifierProvider).activeShift;

    if (shift == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.openRegisterSessionFirst),
          backgroundColor: AppDesignTokens.danger,
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
        SnackBar(
          content: Text(loc.selectArticleToReturnPrompt),
          backgroundColor: AppDesignTokens.danger,
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
            reason: loc.returnReasonDefault,
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
              content: Text(loc.returnSuccessWithNumber(result.returnNumber)),
              backgroundColor: AppDesignTokens.success,
            ),
          );
          _searchSale(_receiptSearchCtrl.text);
        }
      } else {
        // Exchange Mode
        if (_replacementItem == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(loc.selectReplacementArticlePrompt),
              backgroundColor: AppDesignTokens.danger,
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
            reason: loc.exchangeReasonDefault,
          ),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                loc.exchangeSuccessWithDiff(result.difference.format()),
              ),
              backgroundColor: AppDesignTokens.success,
            ),
          );
          _searchSale(_receiptSearchCtrl.text);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${loc.error}: $e'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final catalogState = ref.watch(catalogNotifierProvider);

    return BarcodeScannerListener(
      onBarcodeScanned: (code) {
        _receiptSearchCtrl.text = code;
        _searchSale(code);
      },
      child: Scaffold(
        backgroundColor: AppDesignTokens.canvas,
        appBar: AppBar(
          title: Text(
            loc.returnsExchangesTitle,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          backgroundColor: AppDesignTokens.surface,
          elevation: 0,
          iconTheme: const IconThemeData(color: AppDesignTokens.textPrimary),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: AppDesignTokens.border),
          ),
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
                      flex: 4,
                      child: TextField(
                        controller: _receiptSearchCtrl,
                        decoration: InputDecoration(
                          labelText: loc.searchReceiptPrompt,
                          hintText: 'ex: REC-20260904-0001',
                          prefixIcon: const Icon(
                            Icons.receipt,
                            color: AppDesignTokens.textSecondary,
                          ),
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
                        backgroundColor: AppDesignTokens.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 48),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDesignTokens.radiusInput,
                          ),
                        ),
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
                      label: Text(loc.searchReceipt),
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
                    color: AppDesignTokens.surface,
                    borderRadius: BorderRadius.circular(
                      AppDesignTokens.radiusCard,
                    ),
                    border: Border.all(color: AppDesignTokens.border),
                    boxShadow: AppDesignTokens.shadowSm,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.receipt_long,
                        color: AppDesignTokens.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${loc.reference}: ${_foundSale!.receiptNumber}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '${loc.date}: ${DateFormat('dd/MM/yyyy HH:mm').format(_foundSale!.createdAt)}',
                        style: const TextStyle(
                          color: AppDesignTokens.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${loc.total}: ',
                        style: const TextStyle(
                          color: AppDesignTokens.textSecondary,
                        ),
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
                      label: Text(loc.returnMode),
                      selected: !_isExchangeMode,
                      selectedColor: AppDesignTokens.primary.withValues(
                        alpha: 0.12,
                      ),
                      side: BorderSide(
                        color: !_isExchangeMode
                            ? AppDesignTokens.primary
                            : AppDesignTokens.border,
                      ),
                      labelStyle: TextStyle(
                        color: !_isExchangeMode
                            ? AppDesignTokens.primary
                            : AppDesignTokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) =>
                          setState(() => _isExchangeMode = false),
                    ),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: Text(loc.exchangeMode),
                      selected: _isExchangeMode,
                      selectedColor: AppDesignTokens.primary.withValues(
                        alpha: 0.12,
                      ),
                      side: BorderSide(
                        color: _isExchangeMode
                            ? AppDesignTokens.primary
                            : AppDesignTokens.border,
                      ),
                      labelStyle: TextStyle(
                        color: _isExchangeMode
                            ? AppDesignTokens.primary
                            : AppDesignTokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
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
                                loc.purchasedItemsToReturn,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: AppDesignTokens.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: ListView.separated(
                                  itemCount: _saleLines.length,
                                  separatorBuilder: (_, __) => const Divider(
                                    color: AppDesignTokens.border,
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
                                            activeColor:
                                                AppDesignTokens.primary,
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
                                                    color: AppDesignTokens
                                                        .textPrimary,
                                                  ),
                                                ),
                                                Text(
                                                  '${line.variantDescription} • ${line.quantity}x • ${loc.price}: ${Money.fromMillimes(line.unitPriceMillimes).format()}',
                                                  style: const TextStyle(
                                                    color: AppDesignTokens
                                                        .textSecondary,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          if (returnQty > 0) ...[
                                            // Condition: Remettable en vente ou Défectueux
                                            DropdownButton<String>(
                                              value: condition,
                                              dropdownColor:
                                                  AppDesignTokens.surface,
                                              style: const TextStyle(
                                                color:
                                                    AppDesignTokens.textPrimary,
                                                fontSize: 13,
                                              ),
                                              items: [
                                                DropdownMenuItem(
                                                  value: AppConstants
                                                      .returnConditionSellable,
                                                  child: Text(
                                                    loc.returnConditionSellable,
                                                  ),
                                                ),
                                                DropdownMenuItem(
                                                  value: AppConstants
                                                      .returnConditionDamaged,
                                                  child: Text(
                                                    loc.returnConditionDamaged,
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
                                            // Qty Stepper
                                            Container(
                                              decoration: BoxDecoration(
                                                color: AppDesignTokens
                                                    .surfaceElevated,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      AppDesignTokens
                                                          .radiusInput,
                                                    ),
                                                border: Border.all(
                                                  color: AppDesignTokens.border,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.remove,
                                                      size: 14,
                                                      color: AppDesignTokens
                                                          .textPrimary,
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
                                                      color: AppDesignTokens
                                                          .textPrimary,
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.add,
                                                      size: 14,
                                                      color: AppDesignTokens
                                                          .textPrimary,
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
                            color: AppDesignTokens.surface,
                            borderRadius: BorderRadius.circular(
                              AppDesignTokens.radiusCard,
                            ),
                            border: Border.all(color: AppDesignTokens.border),
                            boxShadow: AppDesignTokens.shadowSm,
                          ),
                          child: _isExchangeMode
                              ? _buildExchangePane(loc, catalogState)
                              : _buildReturnPane(loc),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.assignment_return_outlined,
                          size: 64,
                          color: AppDesignTokens.textMuted,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          loc.searchTicketPlaceholder,
                          style: const TextStyle(
                            color: AppDesignTokens.textSecondary,
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

  Widget _buildReturnPane(AppLocalizations loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.refundDetails,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${loc.amountToRefund} ',
              style: const TextStyle(
                color: AppDesignTokens.textSecondary,
                fontSize: 14,
              ),
            ),
            MoneyDisplay(
              amount: _totalRefundAmount,
              fontSize: 24,
              color: AppDesignTokens.warning,
            ),
          ],
        ),
        const SizedBox(height: 16),

        Text(
          '${loc.refundMethod} ',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ChoiceChip(
              label: Text(loc.paymentCash),
              selected: _refundMethod == AppConstants.paymentCash,
              selectedColor: AppDesignTokens.primary.withValues(alpha: 0.12),
              side: BorderSide(
                color: _refundMethod == AppConstants.paymentCash
                    ? AppDesignTokens.primary
                    : AppDesignTokens.border,
              ),
              labelStyle: TextStyle(
                color: _refundMethod == AppConstants.paymentCash
                    ? AppDesignTokens.primary
                    : AppDesignTokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              onSelected: (_) =>
                  setState(() => _refundMethod = AppConstants.paymentCash),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text(loc.paymentStoreCredit),
              selected: _refundMethod == AppConstants.paymentStoreCredit,
              selectedColor: AppDesignTokens.primary.withValues(alpha: 0.12),
              side: BorderSide(
                color: _refundMethod == AppConstants.paymentStoreCredit
                    ? AppDesignTokens.primary
                    : AppDesignTokens.border,
              ),
              labelStyle: TextStyle(
                color: _refundMethod == AppConstants.paymentStoreCredit
                    ? AppDesignTokens.primary
                    : AppDesignTokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              onSelected: (_) => setState(
                () => _refundMethod = AppConstants.paymentStoreCredit,
              ),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text(loc.paymentCard),
              selected: _refundMethod == AppConstants.paymentCard,
              selectedColor: AppDesignTokens.primary.withValues(alpha: 0.12),
              side: BorderSide(
                color: _refundMethod == AppConstants.paymentCard
                    ? AppDesignTokens.primary
                    : AppDesignTokens.border,
              ),
              labelStyle: TextStyle(
                color: _refundMethod == AppConstants.paymentCard
                    ? AppDesignTokens.primary
                    : AppDesignTokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
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
              backgroundColor: AppDesignTokens.warning,
              foregroundColor: Colors.black87,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  AppDesignTokens.radiusInput,
                ),
              ),
            ),
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.black87,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.check_circle, size: 20),
            label: Text(
              _isSubmitting
                  ? loc.processing.toUpperCase()
                  : loc.completeReturnAction.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExchangePane(AppLocalizations loc, CatalogState catalogState) {
    Money newTotal = _replacementItem != null
        ? _replacementItem!.total
        : Money.zero;
    Money diff = newTotal - _totalRefundAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.selectNewReplacementArticle,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 8),

        if (_replacementItem != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppDesignTokens.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput),
              border: Border.all(
                color: AppDesignTokens.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _replacementItem!.productName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      Text(
                        '${_replacementItem!.variantDescription} • ${_replacementItem!.unitPrice.format()}',
                        style: const TextStyle(
                          color: AppDesignTokens.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: AppDesignTokens.textSecondary,
                  ),
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
                  const Divider(color: AppDesignTokens.border, height: 1),
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
                    '${v.variantDescription} • ${v.salePrice.format()}',
                    style: const TextStyle(
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.add_circle,
                    color: AppDesignTokens.primary,
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

        const Divider(color: AppDesignTokens.border, height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${loc.priceDifference} ',
              style: const TextStyle(
                color: AppDesignTokens.textSecondary,
                fontSize: 14,
              ),
            ),
            if (diff == Money.zero)
              Text(
                '${Money.zero.format()} (${loc.netDifferenceZero})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppDesignTokens.success,
                  fontSize: 16,
                ),
              )
            else if (diff > Money.zero)
              Text(
                '+${diff.format()} (${loc.customerOwes})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppDesignTokens.primary,
                  fontSize: 16,
                ),
              )
            else
              Text(
                '-${diff.abs.format()} (${loc.refundDueCustomer})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppDesignTokens.warning,
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
              backgroundColor: AppDesignTokens.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  AppDesignTokens.radiusInput,
                ),
              ),
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
              _isSubmitting
                  ? loc.processing.toUpperCase()
                  : loc.completeExchangeAction.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
