import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/domain/models/checkout_request.dart';
import 'package:jazzpos/hardware/hardware_manager.dart';
import 'package:jazzpos/hardware/receipt_printer/receipt_document.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/providers/cart_provider.dart';
import 'package:jazzpos/providers/shift_provider.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';
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

  // For mixed payments
  final StringBuffer _cardAmountBuffer = StringBuffer();

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
      _tenderedBuffer.write(amount.format(includeCurrency: false, useGrouping: false));
    });
  }

  Future<void> _submitCheckout() async {
    if (_isSubmitting) return; // Prevent double click!

    final auth = ref.read(authNotifierProvider);
    final shift = ref.read(shiftNotifierProvider).activeShift;

    if (auth.user == null) {
      setState(() => _error = 'Session utilisateur invalide');
      return;
    }
    if (shift == null) {
      setState(() => _error = 'Aucune session de caisse ouverte !');
      return;
    }

    final payments = <PaymentSplit>[];

    if (_selectedMethod == AppConstants.paymentCash) {
      if (_tenderedAmount < widget.totalAmount) {
        setState(() => _error = 'Montant reçu insuffisant');
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
      final cardAmt = Money.parse(_cardAmountBuffer.toString());
      final cashAmt = widget.totalAmount - cardAmt;
      if (cardAmt <= Money.zero || cashAmt <= Money.zero) {
        setState(() => _error = 'Répartition mixte invalide');
        return;
      }
      payments.add(PaymentSplit(method: AppConstants.paymentCard, amount: cardAmt));
      payments.add(PaymentSplit(method: AppConstants.paymentCash, amount: cashAmt, tendered: cashAmt));
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

      // Trigger cash drawer kick on cash sale!
      if (_selectedMethod == AppConstants.paymentCash || _selectedMethod == AppConstants.paymentMixed) {
        try {
          await HardwareManager.instance.cashDrawer.openDrawer();
        } catch (_) {}
      }

      // Build receipt document and trigger printer
      final doc = ReceiptDocument(
        storeName: 'JAZZ FASHION',
        receiptNumber: result.sale.receiptNumber,
        dateTime: result.sale.createdAt,
        cashierName: auth.user!.displayName,
        registerCode: 'REG-01',
        lines: result.lines
            .map((l) => ReceiptLineItem(
                  productName: l.productName,
                  variantDescription: l.variantDescription,
                  sku: l.sku,
                  barcode: l.barcode,
                  quantity: l.quantity,
                  unitPrice: Money.fromMillimes(l.unitPriceMillimes),
                  total: Money.fromMillimes(l.totalMillimes),
                ))
            .toList(),
        subtotal: Money.fromMillimes(result.sale.subtotalMillimes),
        discount: Money.fromMillimes(result.sale.discountMillimes),
        tax: Money.fromMillimes(result.sale.taxMillimes),
        total: Money.fromMillimes(result.sale.totalMillimes),
        payments: payments
            .map((p) => ReceiptPaymentItem(
                  method: p.method,
                  amount: p.amount,
                  tendered: p.tendered,
                  change: p.change,
                ))
            .toList(),
      );

      try {
        await HardwareManager.instance.receiptPrinter.printReceipt(doc);
      } catch (_) {}

      if (mounted) {
        Navigator.of(context).pop();
        ReceiptPreviewDialog.show(context, document: doc);
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 750,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Encaissement Vente',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                IconButton(
                  onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: AppTheme.textSecondary),
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
                          _buildMethodButton(AppConstants.paymentCash, 'ESPECES', Icons.money),
                          const SizedBox(width: 8),
                          _buildMethodButton(AppConstants.paymentCard, 'CARTE', Icons.credit_card),
                          const SizedBox(width: 8),
                          _buildMethodButton(AppConstants.paymentMixed, 'MIXTE', Icons.pie_chart),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Presets for cash
                      if (_selectedMethod == AppConstants.paymentCash) ...[
                        const Text('Billets rapides:', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildPresetButton(widget.totalAmount, label: 'Montant Exact'),
                            _buildPresetButton(const Money.fromMillimes(10000)),
                            _buildPresetButton(const Money.fromMillimes(20000)),
                            _buildPresetButton(const Money.fromMillimes(50000)),
                            _buildPresetButton(const Money.fromMillimes(100000)),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Summary Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161F2E),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total à Payer:', style: TextStyle(fontSize: 15, color: AppTheme.textSecondary)),
                                MoneyDisplay(amount: widget.totalAmount, fontSize: 20),
                              ],
                            ),
                            if (_selectedMethod == AppConstants.paymentCash) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Espèces Reçus:', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                                  MoneyDisplay(amount: _tenderedAmount, fontSize: 18, color: Colors.blueAccent),
                                ],
                              ),
                              const Divider(color: AppTheme.border, height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Monnaie à Rendre:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                                  MoneyDisplay(amount: _changeAmount, fontSize: 22, color: Colors.greenAccent),
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
                            color: Colors.red.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.redAccent),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
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
                          color: const Color(0xFF161F2E),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Text(
                          _tenderedBuffer.isEmpty ? '0.000' : _tenderedBuffer.toString(),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'monospace'),
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
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      side: const BorderSide(color: AppTheme.border),
                    ),
                    child: const Text('ANNULER (Echap)'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submitCheckout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 52),
                    ),
                    icon: _isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.check_circle_outline, size: 24),
                    label: Text(
                      _isSubmitting ? 'VALIDATION...' : 'VALIDER PAIEMENT (Entrée)',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
          height: 52,
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : const Color(0xFF161F2E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isSelected ? Colors.white : AppTheme.textSecondary),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
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
        backgroundColor: const Color(0xFF334155),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: const Size(0, 38),
      ),
      child: Text(label ?? amount.format()),
    );
  }
}
