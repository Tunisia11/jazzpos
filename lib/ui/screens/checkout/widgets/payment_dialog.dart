import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/domain/models/checkout_request.dart';
import 'package:jazzpos/hardware/hardware_manager.dart';
import 'package:jazzpos/hardware/receipt_printer/receipt_document.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/providers/cart_provider.dart';
import 'package:jazzpos/providers/shift_provider.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'package:jazzpos/ui/widgets/money_display.dart';
import 'package:jazzpos/ui/widgets/numpad.dart';
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
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PaymentDialog(
        totalAmount: totalAmount,
        storeId: storeId,
        registerId: registerId,
      ),
    );
  }

  @override
  ConsumerState<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<PaymentDialog> {
  String _selectedMethod = AppConstants.paymentCash;
  final StringBuffer _tenderedBuffer = StringBuffer();
  bool _isSubmitting = false;
  String? _error;

  Money get _tenderedAmount {
    if (_tenderedBuffer.isEmpty) return widget.totalAmount;
    return Money.parse(_tenderedBuffer.toString());
  }

  Money get _changeAmount {
    if (_tenderedAmount < widget.totalAmount) return Money.zero;
    return _tenderedAmount - widget.totalAmount;
  }

  void _onNumpadPress(String char) {
    setState(() {
      _tenderedBuffer.write(char);
      _error = null;
    });
  }

  void _onNumpadBackspace() {
    if (_tenderedBuffer.isNotEmpty) {
      setState(() {
        final cur = _tenderedBuffer.toString();
        _tenderedBuffer.clear();
        _tenderedBuffer.write(cur.substring(0, cur.length - 1));
      });
    }
  }

  void _onNumpadClear() {
    setState(() {
      _tenderedBuffer.clear();
    });
  }

  void _setPresetCash(Money amount) {
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
      setState(() => _error = loc.invalidUserSession);
      return;
    }
    if (shift == null) {
      setState(() => _error = loc.noActiveShift);
      return;
    }

    final payments = <PaymentSplit>[];

    if (_selectedMethod == AppConstants.paymentCash) {
      if (_tenderedAmount < widget.totalAmount) {
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
      // The visible numpad buffer is the card portion for a split payment.
      // Previously a separate, unwritten buffer made every split invalid.
      final cardAmt = _tenderedBuffer.isEmpty
          ? Money.zero
          : Money.parse(_tenderedBuffer.toString());
      final cashAmt = widget.totalAmount - cardAmt;
      if (cardAmt <= Money.zero || cashAmt <= Money.zero) {
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
      final result = await cartNotifier.checkout(
        storeId: widget.storeId,
        registerId: widget.registerId,
        shiftId: shift.id,
        cashierId: auth.user!.id,
        payments: payments,
      );

      // Receipts must show the client-configured business and register rather
      // than the development sample name or a fixed register code.
      final db = ref.read(databaseProvider);
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

      // Trigger cash drawer kick on cash sale!
      if (_selectedMethod == AppConstants.paymentCash ||
          _selectedMethod == AppConstants.paymentMixed) {
        try {
          await HardwareManager.instance.cashDrawer.openDrawer();
        } catch (_) {}
      }

      // Build receipt document and trigger printer
      final doc = ReceiptDocument(
        storeName: company?.name ?? store?.name ?? 'JAZZ POS',
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

      if (mounted) {
        Navigator.of(context).pop();
        if (!printSuccess) {
          _showHardwareFailureDialog(
            context,
            doc: doc,
            errorMessage: printErrorMessage,
          );
        } else {
          ReceiptPreviewDialog.show(context, document: doc);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = e.toString().replaceAll('PosException: ', '');
        });
      }
    }
  }

  void _showHardwareFailureDialog(
    BuildContext context, {
    required ReceiptDocument doc,
    String? errorMessage,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppDesignTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        ),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: AppDesignTokens.success, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'VENTE ENREGISTRÉE AVEC SUCCÈS ✓',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppDesignTokens.successText,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppDesignTokens.warningBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppDesignTokens.warning),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.print_disabled,
                    color: AppDesignTokens.warningText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Imprimante indisponible',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppDesignTokens.warningText,
                          ),
                        ),
                        if (errorMessage != null)
                          Text(
                            errorMessage,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppDesignTokens.warningText,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Ticket N° : ${doc.receiptNumber}\nMontant : ${doc.total.format()}\nLa vente, les stocks et les paiements ont été validés en base de données.',
              style: const TextStyle(
                fontSize: 13,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              try {
                await HardwareManager.instance.receiptPrinter.printReceipt(doc);
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                  ReceiptPreviewDialog.show(context, document: doc);
                }
              } catch (_) {}
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              ReceiptPreviewDialog.show(context, document: doc);
            },
            icon: const Icon(Icons.remove_red_eye),
            label: const Text('Aperçu ticket'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;

    return Dialog(
      backgroundColor: AppDesignTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusXl),
      ),
      child: Container(
        width: 750,
        padding: const EdgeInsets.all(AppDesignTokens.space24),
        child: Column(
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
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
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
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
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
        ),
      ),
    );
  }

  Widget _buildMethodButton(String method, String label, IconData icon) {
    final isSelected = _selectedMethod == method;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedMethod = method),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 48,
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
          child: Row(
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
