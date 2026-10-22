import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tracepos/hardware/barcode_scanner/scanner_input_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracepos/core/constants/app_constants.dart';
import 'package:tracepos/core/localization/app_localizations_delegate.dart';
import 'package:tracepos/core/money/money.dart';
import 'package:tracepos/domain/models/checkout_request.dart';
import 'package:tracepos/hardware/hardware_manager.dart';
import 'package:tracepos/hardware/receipt_printer/receipt_document.dart';
import 'package:tracepos/providers/auth_provider.dart';
import 'package:tracepos/providers/app_providers.dart';
import 'package:tracepos/providers/catalog_provider.dart';
import 'package:tracepos/providers/cart_provider.dart';
import 'package:tracepos/providers/shift_provider.dart';
import 'package:tracepos/core/logging/pos_logger.dart';
import 'package:tracepos/ui/theme/app_design_tokens.dart';
import 'package:tracepos/core/sound/sound_effect_service.dart';
import 'package:tracepos/ui/widgets/money_display.dart';
import 'package:tracepos/ui/widgets/numpad.dart';
import 'receipt_preview_dialog.dart';

class PaymentDialog extends ConsumerStatefulWidget {
  final Money totalAmount;
  final String storeId;
  final String registerId;

  const PaymentDialog({
    super.key,
    required this.totalAmount,
    required this.storeId,
    required this.registerId,
  });

  static Future<void> show(
    BuildContext context, {
    required Money totalAmount,
    required String storeId,
    required String registerId,
  }) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final state = container.read(cartNotifierProvider);
    if (state.isLocked || state.isProcessing) return;
    final cart = container.read(cartNotifierProvider.notifier);
    final session = cart.beginPaymentSession();
    void resetScanner() {
      if (!HardwareManager.instance.isInitialized) return;
      final scanner = HardwareManager.instance.barcodeScanner;
      if (scanner is ScannerInputService) scanner.reset();
    }
    resetScanner();
    ({ReceiptDocument document, String? error})? result;
    try {
      result = await showDialog<({ReceiptDocument document, String? error})>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PaymentDialog(
          totalAmount: totalAmount, storeId: storeId, registerId: registerId,
        ),
      );
    } finally {
      resetScanner();
      session.release();
    }
    if (result != null && context.mounted) {
      if (result.error != null) {
        _showHardwareFailureDialog(context, doc: result.document, errorMessage: result.error);
      } else {
        ReceiptPreviewDialog.show(context, document: result.document);
      }
    }
  }

  static void _showHardwareFailureDialog(BuildContext context, {
    required ReceiptDocument doc, String? errorMessage,
  }) {
    showDialog<void>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Vente enregistrée'),
        content: Text("L'impression du ticket a échoué.\nTicket ${doc.receiptNumber} — ${doc.total.format()}\n${errorMessage ?? ''}\nVérifiez le papier et la file Windows avant de réessayer : une impression peut être en attente."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
          TextButton(onPressed: () {
            Navigator.pop(ctx);
            if (context.mounted) ReceiptPreviewDialog.show(context, document: doc);
          }, child: const Text('Aperçu / Réimprimer')),
        ],
      ),
    ));
  }

  @override
  ConsumerState<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<PaymentDialog> {
  String _selectedMethod = AppConstants.paymentCash;
  final StringBuffer _tenderedBuffer = StringBuffer();
  bool _isSubmitting = false;
  String? _error;

  final FocusNode _keyboardFocusNode = FocusNode();

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || _isSubmitting) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('0');
    } else if (key == LogicalKeyboardKey.digit1 ||
        key == LogicalKeyboardKey.numpad1) {
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('1');
    } else if (key == LogicalKeyboardKey.digit2 ||
        key == LogicalKeyboardKey.numpad2) {
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('2');
    } else if (key == LogicalKeyboardKey.digit3 ||
        key == LogicalKeyboardKey.numpad3) {
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('3');
    } else if (key == LogicalKeyboardKey.digit4 ||
        key == LogicalKeyboardKey.numpad4) {
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('4');
    } else if (key == LogicalKeyboardKey.digit5 ||
        key == LogicalKeyboardKey.numpad5) {
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('5');
    } else if (key == LogicalKeyboardKey.digit6 ||
        key == LogicalKeyboardKey.numpad6) {
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('6');
    } else if (key == LogicalKeyboardKey.digit7 ||
        key == LogicalKeyboardKey.numpad7) {
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('7');
    } else if (key == LogicalKeyboardKey.digit8 ||
        key == LogicalKeyboardKey.numpad8) {
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('8');
    } else if (key == LogicalKeyboardKey.digit9 ||
        key == LogicalKeyboardKey.numpad9) {
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('9');
    } else if (key == LogicalKeyboardKey.period ||
        key == LogicalKeyboardKey.comma ||
        key == LogicalKeyboardKey.numpadDecimal) {
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('.');
    } else if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      SoundEffectService.instance.playBackspace();
      _onNumpadBackspace();
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _submitCheckout();
    }
  }

  /// Priority 3: Safe tendered money calculation. NEVER throws on invalid/incomplete input.
  Money get _tenderedAmount {
    final text = _tenderedBuffer.toString().trim();
    if (text.isEmpty) return widget.totalAmount;
    final parsed = Money.tryParse(text);
    if (parsed != null) return parsed;
    // For trailing or lone separators, safely extract valid prefix
    if (text == '.' || text == ',') return Money.zero;
    if (text.endsWith('.') || text.endsWith(',')) {
      final stripped = text.substring(0, text.length - 1);
      return Money.tryParse(stripped) ?? Money.zero;
    }
    return Money.zero;
  }

  Money get _changeAmount {
    if (_tenderedAmount < widget.totalAmount) return Money.zero;
    return _tenderedAmount - widget.totalAmount;
  }

  /// Priority 3: Robust numpad handler rejecting repeated decimals, limiting decimals to 3 (TND millimes)
  void _onNumpadPress(String char) {
    if (_isSubmitting) return;
    setState(() {
      _error = null;
      final cur = _tenderedBuffer.toString();
      final normalized = char == ',' ? '.' : char;

      // 1. Decimal point validation
      if (normalized == '.') {
        if (cur.contains('.')) {
          // Reject repeated decimal point
          return;
        }
        if (cur.isEmpty) {
          _tenderedBuffer.write('0.');
        } else {
          _tenderedBuffer.write('.');
        }
        return;
      }

      // 2. Double-zero '00' validation
      if (normalized == '00') {
        if (cur.contains('.')) {
          final parts = cur.split('.');
          final decimals = parts.length > 1 ? parts[1] : '';
          if (decimals.length >= 3) return;
          if (decimals.length == 2) {
            _tenderedBuffer.write('0');
            return;
          }
          if (decimals.length <= 1) {
            _tenderedBuffer.write('00');
            return;
          }
        } else {
          if (cur.isNotEmpty && cur != '0') {
            _tenderedBuffer.write('00');
          }
        }
        return;
      }

      // 3. Numeric digits (0-9)
      if (RegExp(r'^[0-9]$').hasMatch(normalized)) {
        if (cur == '0' && normalized != '0') {
          _tenderedBuffer.clear();
          _tenderedBuffer.write(normalized);
          return;
        }
        if (cur == '0' && normalized == '0') {
          return; // Prevent multiple leading zeros
        }
        if (cur.contains('.')) {
          final parts = cur.split('.');
          if (parts.length > 1 && parts[1].length >= 3) {
            // TND supports at most 3 decimal places (millimes)
            return;
          }
        }
        _tenderedBuffer.write(normalized);
      }
    });
  }

  void _onNumpadBackspace() {
    if (_isSubmitting) return;
    if (_tenderedBuffer.isNotEmpty) {
      setState(() {
        final cur = _tenderedBuffer.toString();
        _tenderedBuffer.clear();
        _tenderedBuffer.write(cur.substring(0, cur.length - 1));
      });
    }
  }

  void _onNumpadClear() {
    if (_isSubmitting) return;
    setState(() {
      _tenderedBuffer.clear();
    });
  }

  void _setPresetCash(Money amount) {
    if (_isSubmitting) return;
    SoundEffectService.instance.playKeyTap();
    setState(() {
      _tenderedBuffer.clear();
      _tenderedBuffer.write(
        amount.format(includeCurrency: false, useGrouping: false),
      );
    });
  }

  Future<void> _submitCheckout() async {
    if (_isSubmitting) return; // Prevent double click!

    final loc = context.loc;
    final auth = ref.read(authNotifierProvider);
    final shift = ref.read(shiftNotifierProvider).activeShift;

    if (auth.user == null) {
      SoundEffectService.instance.playError();
      setState(() => _error = loc.invalidUserSession);
      return;
    }
    if (shift == null) {
      SoundEffectService.instance.playError();
      setState(() => _error = loc.noActiveShift);
      return;
    }

    final payments = <PaymentSplit>[];

    if (_selectedMethod == AppConstants.paymentCash) {
      if (_tenderedAmount < widget.totalAmount) {
        SoundEffectService.instance.playError();
        setState(() => _error = loc.insufficientAmount);
        return;
      }
      payments.add(
        PaymentSplit(
          method: AppConstants.paymentCash,
          amount: widget.totalAmount,
          tendered: _tenderedAmount,
          change: _changeAmount,
        ),
      );
    } else if (_selectedMethod == AppConstants.paymentCard) {
      payments.add(
        PaymentSplit(
          method: AppConstants.paymentCard,
          amount: widget.totalAmount,
        ),
      );
    } else if (_selectedMethod == AppConstants.paymentMixed) {
      final cardAmt = _tenderedBuffer.isEmpty
          ? Money.zero
          : (Money.tryParse(_tenderedBuffer.toString().trim()) ?? Money.zero);
      final cashAmt = widget.totalAmount - cardAmt;
      if (cardAmt <= Money.zero || cashAmt <= Money.zero) {
        SoundEffectService.instance.playError();
        setState(() => _error = loc.invalidSplit);
        return;
      }
      payments.add(
        PaymentSplit(method: AppConstants.paymentCard, amount: cardAmt),
      );
      payments.add(
        PaymentSplit(
          method: AppConstants.paymentCash,
          amount: cashAmt,
          tendered: cashAmt,
        ),
      );
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final cartNotifier = ref.read(cartNotifierProvider.notifier);
      final imageByVariant = {
        for (final i in ref.read(cartNotifierProvider).items)
          i.variantId: i.imageUrl,
      };
      final db = ref.read(databaseProvider);


      // Receipts must show the client-configured business and register rather
      // than the development sample name or a fixed register code.
      final store = await (db.select(
        db.stores,
      )..where((tbl) => tbl.id.equals(widget.storeId))).getSingleOrNull();
      final register = await (db.select(
        db.registers,
      )..where((tbl) => tbl.id.equals(widget.registerId))).getSingleOrNull();
      final company = store == null
          ? null
          : await (db.select(db.companies)
                  ..where((tbl) => tbl.id.equals(store.companyId)))
                .getSingleOrNull();

      final result = await cartNotifier.checkout(
        storeId: widget.storeId,
        registerId: widget.registerId,
        shiftId: shift.id,
        cashierId: auth.user!.id,
        payments: payments,
      );
      // Stock changed: reload the catalog so the POS grid shows new counts.
      if (mounted) ref.read(catalogNotifierProvider.notifier).refresh();

      SoundEffectService.instance.playSuccess();

      // Trigger cash drawer kick on cash sale!
      if (_selectedMethod == AppConstants.paymentCash ||
          _selectedMethod == AppConstants.paymentMixed) {
        try {
          await HardwareManager.instance.cashDrawer.openDrawer();
        } catch (e) {
          PosLogger.instance.warning(
            'Hardware',
            'Could not kick cash drawer: $e',
          );
        }
      }

      // Build receipt document and trigger printer
      final doc = ReceiptDocument(
        storeName: company?.name ?? store?.name ?? AppConstants.appName,
        storeAddress: store?.address ?? company?.address,
        storePhone: store?.phone ?? company?.phone,
        fiscalId: company?.fiscalId,
        receiptNumber: result.sale.receiptNumber,
        dateTime: result.sale.createdAt,
        cashierName: auth.user!.displayName,
        registerCode: register?.code ?? widget.registerId,
        lines: result.lines
            .map(
              (l) => ReceiptLineItem(
                productName: l.productName,
                variantDescription: l.variantDescription,
                sku: l.sku,
                barcode: l.barcode,
                quantity: l.quantity,
                unitPrice: Money.fromMillimes(l.unitPriceMillimes),
                total: Money.fromMillimes(l.totalMillimes),
                imageUrl: imageByVariant[l.variantId],
              ),
            )
            .toList(),
        subtotal: Money.fromMillimes(result.sale.subtotalMillimes),
        discount: Money.fromMillimes(result.sale.discountMillimes),
        tax: Money.fromMillimes(result.sale.taxMillimes),
        total: Money.fromMillimes(result.sale.totalMillimes),
        payments: payments
            .map(
              (p) => ReceiptPaymentItem(
                method: p.method,
                amount: p.amount,
                tendered: p.tendered,
                change: p.change,
              ),
            )
            .toList(),
      );

      bool printSuccess = true;
      String? printErrorMessage;
      try {
        await HardwareManager.instance.receiptPrinter.printReceipt(doc);
      } catch (e) {
        printSuccess = false;
        printErrorMessage = e.toString().replaceAll('Exception: ', '');
      }

      try {
        await ref.read(printJobServiceProvider).markResult(
          result.printJobId,
          ok: printSuccess,
          error: printErrorMessage,
        );
      } catch (e) {
        PosLogger.instance.warning('PrintJobs', 'Could not record print result: $e');
      }

      if (mounted) {
        setState(() => _isSubmitting = false);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.of(context).pop((document: doc, error: printSuccess ? null : printErrorMessage));
      }
    } catch (e) {
      SoundEffectService.instance.playError();
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = e.toString().replaceAll('PosException: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;

    return PopScope(
      canPop: !_isSubmitting,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_isSubmitting) Navigator.of(context).pop();
        }},
        child: KeyboardListener(
          focusNode: _keyboardFocusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Dialog(
      backgroundColor: AppDesignTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusXl),
      ),
      child: Container(
        width: 1000,
        padding: const EdgeInsets.all(AppDesignTokens.space24),
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  loc.paymentTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
                IconButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: Payment Methods & Presets
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Method Selector
                      Row(
                        children: [
                          _buildMethodButton(
                            AppConstants.paymentCash,
                            loc.paymentCash.toUpperCase(),
                            Icons.money,
                          ),
                          const SizedBox(width: 8),
                          _buildMethodButton(
                            AppConstants.paymentCard,
                            loc.paymentCard.toUpperCase(),
                            Icons.credit_card,
                          ),
                          const SizedBox(width: 8),
                          _buildMethodButton(
                            AppConstants.paymentMixed,
                            loc.paymentSplit.toUpperCase(),
                            Icons.pie_chart,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Presets for cash
                      if (_selectedMethod == AppConstants.paymentCash) ...[
                        Text(
                          loc.quickBills,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppDesignTokens.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildPresetButton(
                              widget.totalAmount,
                              label: loc.exactAmount,
                            ),
                            _buildPresetButton(const Money.fromMillimes(10000)),
                            _buildPresetButton(const Money.fromMillimes(20000)),
                            _buildPresetButton(const Money.fromMillimes(50000)),
                            _buildPresetButton(
                              const Money.fromMillimes(100000),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Summary Card
                      Container(
                        padding: const EdgeInsets.all(AppDesignTokens.space16),
                        decoration: BoxDecoration(
                          color: AppDesignTokens.surfaceSecondary,
                          borderRadius: BorderRadius.circular(
                            AppDesignTokens.radiusMd,
                          ),
                          border: Border.all(color: AppDesignTokens.border),
                        ),
                        child: Column(
                          children: [
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              spacing: 12,
                              children: [
                                Text(
                                  '${loc.total}:',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppDesignTokens.textSecondary,
                                  ),
                                ),
                                MoneyDisplay(
                                  amount: widget.totalAmount,
                                  fontSize: 18,
                                  color: AppDesignTokens.textPrimary,
                                ),
                              ],
                            ),
                            if (_selectedMethod ==
                                AppConstants.paymentCash) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                spacing: 12,
                                children: [
                                  Text(
                                    '${loc.tenderedAmount}:',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppDesignTokens.textSecondary,
                                    ),
                                  ),
                                  MoneyDisplay(
                                    amount: _tenderedAmount,
                                    fontSize: 17,
                                    color: AppDesignTokens.primary,
                                  ),
                                ],
                              ),
                              const Divider(
                                color: AppDesignTokens.border,
                                height: 16,
                              ),
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                spacing: 12,
                                children: [
                                  Text(
                                    '${loc.changeDue}:',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: AppDesignTokens.textPrimary,
                                    ),
                                  ),
                                  MoneyDisplay(
                                    amount: _changeAmount,
                                    fontSize: 20,
                                    color: AppDesignTokens.success,
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppDesignTokens.dangerBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppDesignTokens.danger),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: AppDesignTokens.dangerText,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 24),

                // Right Column: Numpad for entering cash tendered
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.centerRight,
                        decoration: BoxDecoration(
                          color: AppDesignTokens.surfaceSecondary,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppDesignTokens.border),
                        ),
                        child: Text(
                          _tenderedBuffer.isEmpty
                              ? '0.000'
                              : _tenderedBuffer.toString(),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppDesignTokens.textPrimary,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Numpad(
                        onKeyPress: _onNumpadPress,
                        onBackspace: _onNumpadBackspace,
                        onClear: _onNumpadClear,
                        showDecimal: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      side: const BorderSide(color: AppDesignTokens.border),
                      foregroundColor: AppDesignTokens.textPrimary,
                    ),
                    child: Text('${loc.cancel.toUpperCase()} (Echap)'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submitCheckout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppDesignTokens.success,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 50),
                    ),
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline, size: 22),
                    label: Text(
                      _isSubmitting
                          ? '${loc.loading.toUpperCase()}...'
                          : loc.validatePayment,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        )),
      ),
    ))));
  }

  Widget _buildMethodButton(String method, String label, IconData icon) {
    final isSelected = _selectedMethod == method;
    return Expanded(
      child: InkWell(
        onTap: _isSubmitting ? null : () => setState(() => _selectedMethod = method),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            color: isSelected
                ? AppDesignTokens.primary
                : AppDesignTokens.surfaceSecondary,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? AppDesignTokens.primary
                  : AppDesignTokens.border,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? Colors.white
                    : AppDesignTokens.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isSelected
                      ? Colors.white
                      : AppDesignTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetButton(Money amount, {String? label}) {
    return ElevatedButton(
      onPressed: () => _setPresetCash(amount),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppDesignTokens.surfaceSecondary,
        foregroundColor: AppDesignTokens.textPrimary,
        elevation: 0,
        side: const BorderSide(color: AppDesignTokens.border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: const Size(0, 36),
      ),
      child: Text(
        label ?? amount.format(),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}
