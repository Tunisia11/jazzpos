import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/providers/shift_provider.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'package:jazzpos/ui/widgets/money_display.dart';
import 'package:jazzpos/ui/widgets/numpad.dart';

class ShiftManagementScreen extends ConsumerStatefulWidget {
  final String registerId;

  const ShiftManagementScreen({super.key, this.registerId = 'REG-01'});

  @override
  ConsumerState<ShiftManagementScreen> createState() =>
      _ShiftManagementScreenState();
}

class _ShiftManagementScreenState extends ConsumerState<ShiftManagementScreen> {
  final StringBuffer _countedBuffer = StringBuffer();
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    ref
        .read(shiftNotifierProvider.notifier)
        .checkActiveShift(widget.registerId);
  }

  void _openShiftDialog() {
    final loc = context.loc;
    final ctrl = TextEditingController(text: '150.000');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppDesignTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusDialog),
        ),
        title: Text(
          loc.openRegisterShift,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc.enterInitialCashFloat,
              style: const TextStyle(color: AppDesignTokens.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
              decoration: InputDecoration(
                labelText: loc.initialCashFloat,
                suffixText: 'TND',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(loc.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final auth = ref.read(authNotifierProvider);
              final val = double.tryParse(ctrl.text) ?? 0;
              await ref
                  .read(shiftNotifierProvider.notifier)
                  .openShift(
                    registerId: widget.registerId,
                    cashierId: auth.user?.id ?? 'system',
                    openingCash: Money.fromTnd(val),
                  );
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppDesignTokens.success,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  AppDesignTokens.radiusInput,
                ),
              ),
            ),
            child: Text(loc.openRegisterAction),
          ),
        ],
      ),
    );
  }

  void _showCashMovementDialog(String type) {
    final loc = context.loc;
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final isPayIn = type == 'PAY_IN';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppDesignTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusDialog),
        ),
        title: Text(
          isPayIn ? loc.payInCash : loc.payOutCash,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
              decoration: InputDecoration(
                labelText: loc.amountTnd,
                suffixText: 'TND',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(
                labelText: loc.reasonOrProof,
                hintText: isPayIn
                    ? loc.payInReasonExample
                    : loc.payOutReasonExample,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(loc.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final val = Money.tryParse(amountCtrl.text);
              final reason = reasonCtrl.text.trim();
              if (val == null || !val.isPositive || reason.isEmpty) return;

              final auth = ref.read(authNotifierProvider);
              await ref
                  .read(shiftNotifierProvider.notifier)
                  .recordCashMovement(
                    userId: auth.user?.id ?? 'system',
                    type: type,
                    amount: val,
                    reason: reason,
                  );
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isPayIn
                  ? AppDesignTokens.primary
                  : AppDesignTokens.warning,
              foregroundColor: isPayIn ? Colors.white : Colors.black87,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  AppDesignTokens.radiusInput,
                ),
              ),
            ),
            child: Text(loc.validateMovement),
          ),
        ],
      ),
    );
  }

  Future<void> _submitCloseShift() async {
    final loc = context.loc;
    final countedVal = Money.parse(_countedBuffer.toString());
    final auth = ref.read(authNotifierProvider);

    setState(() => _isClosing = true);

    try {
      await ref
          .read(shiftNotifierProvider.notifier)
          .closeShift(
            cashierId: auth.user?.id ?? 'system',
            countedCash: countedVal,
            note: loc.standardShiftCloseNote,
          );

      setState(() => _isClosing = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.shiftClosedZReportSuccess),
            backgroundColor: AppDesignTokens.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isClosing = false);
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
    final shiftState = ref.watch(shiftNotifierProvider);
    final activeShift = shiftState.activeShift;
    final summary = shiftState.summary;

    return Scaffold(
      backgroundColor: AppDesignTokens.canvas,
      appBar: AppBar(
        title: Text(
          loc.shiftManagementTitle,
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppDesignTokens.textPrimary),
            onPressed: () => ref
                .read(shiftNotifierProvider.notifier)
                .checkActiveShift(widget.registerId),
            tooltip: loc.refreshTotals,
          ),
        ],
      ),
      body: activeShift == null
          ? Center(
              child: Container(
                width: 450,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppDesignTokens.surface,
                  borderRadius: BorderRadius.circular(
                    AppDesignTokens.radiusCard,
                  ),
                  border: Border.all(color: AppDesignTokens.border),
                  boxShadow: AppDesignTokens.shadowSm,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppDesignTokens.warning.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.point_of_sale,
                        size: 48,
                        color: AppDesignTokens.warning,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      loc.registerCurrentlyClosed,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${loc.registerTerminal}: ${widget.registerId}',
                      style: const TextStyle(
                        color: AppDesignTokens.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _openShiftDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppDesignTokens.success,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppDesignTokens.radiusInput,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.lock_open),
                        label: Text(
                          loc.openRegisterSessionAction,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: Shift Live Financial Balance
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header info
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    loc.shiftOpenedAt(
                                      DateFormat(
                                        'HH:mm le dd/MM/yyyy',
                                      ).format(activeShift.openedAt),
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: AppDesignTokens.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${loc.registerTerminal}: ${widget.registerId} • Shift ID: ${activeShift.id.substring(0, 8)}...',
                                    style: const TextStyle(
                                      color: AppDesignTokens.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _showCashMovementDialog('PAY_IN'),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: AppDesignTokens.border,
                                      ),
                                      foregroundColor:
                                          AppDesignTokens.textPrimary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          AppDesignTokens.radiusInput,
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.arrow_downward,
                                      size: 16,
                                      color: AppDesignTokens.success,
                                    ),
                                    label: Text(
                                      '${loc.payInAction} (+)',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _showCashMovementDialog('PAY_OUT'),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: AppDesignTokens.border,
                                      ),
                                      foregroundColor:
                                          AppDesignTokens.textPrimary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          AppDesignTokens.radiusInput,
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.arrow_upward,
                                      size: 16,
                                      color: AppDesignTokens.warning,
                                    ),
                                    label: Text(
                                      '${loc.payOutAction} (-)',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Financial Breakdown Card
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppDesignTokens.surface,
                            borderRadius: BorderRadius.circular(
                              AppDesignTokens.radiusCard,
                            ),
                            border: Border.all(color: AppDesignTokens.border),
                            boxShadow: AppDesignTokens.shadowSm,
                          ),
                          child: Column(
                            children: [
                              _buildRow(
                                '${loc.initialCashFloat} :',
                                summary?.openingCash ?? Money.zero,
                              ),
                              const Divider(
                                color: AppDesignTokens.border,
                                height: 20,
                              ),
                              _buildRow(
                                loc.cashSales,
                                summary?.cashSales ?? Money.zero,
                                color: AppDesignTokens.primary,
                              ),
                              const SizedBox(height: 10),
                              _buildRow(
                                loc.cardSales,
                                summary?.cardSales ?? Money.zero,
                              ),
                              const SizedBox(height: 10),
                              _buildRow(
                                loc.cashRefunds,
                                summary?.cashRefunds ?? Money.zero,
                                color: AppDesignTokens.danger,
                              ),
                              const SizedBox(height: 10),
                              _buildRow(
                                loc.manualCashIn,
                                summary?.cashIn ?? Money.zero,
                              ),
                              const SizedBox(height: 10),
                              _buildRow(
                                loc.manualCashOut,
                                summary?.cashOut ?? Money.zero,
                                color: AppDesignTokens.warning,
                              ),
                              const Divider(
                                color: AppDesignTokens.border,
                                height: 24,
                              ),
                              _buildRow(
                                loc.expectedCashBalance,
                                summary?.expectedCash ?? Money.zero,
                                fontSize: 18,
                                isBold: true,
                                color: AppDesignTokens.success,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 24),

                  // Right: Blind Count Close Shift Numpad
                  Expanded(
                    flex: 4,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppDesignTokens.surface,
                        borderRadius: BorderRadius.circular(
                          AppDesignTokens.radiusCard,
                        ),
                        border: Border.all(color: AppDesignTokens.border),
                        boxShadow: AppDesignTokens.shadowSm,
                      ),
                      child: Column(
                        children: [
                          Text(
                            loc.blindCountTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppDesignTokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            loc.enterCountedCashPrompt,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppDesignTokens.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 16),

                          Container(
                            height: 52,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            alignment: Alignment.centerRight,
                            decoration: BoxDecoration(
                              color: AppDesignTokens.surfaceElevated,
                              borderRadius: BorderRadius.circular(
                                AppDesignTokens.radiusInput,
                              ),
                              border: Border.all(color: AppDesignTokens.border),
                            ),
                            child: Text(
                              _countedBuffer.isEmpty
                                  ? '0.000'
                                  : _countedBuffer.toString(),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                color: AppDesignTokens.textPrimary,
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          Numpad(
                            onKeyPress: (c) =>
                                setState(() => _countedBuffer.write(c)),
                            onBackspace: () {
                              if (_countedBuffer.isNotEmpty) {
                                setState(() {
                                  final s = _countedBuffer.toString();
                                  _countedBuffer.clear();
                                  _countedBuffer.write(
                                    s.substring(0, s.length - 1),
                                  );
                                });
                              }
                            },
                            onClear: () =>
                                setState(() => _countedBuffer.clear()),
                            showDecimal: true,
                          ),

                          const SizedBox(height: 20),

                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: _isClosing ? null : _submitCloseShift,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppDesignTokens.danger,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppDesignTokens.radiusInput,
                                  ),
                                ),
                              ),
                              icon: _isClosing
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.lock, size: 20),
                              label: Text(
                                _isClosing
                                    ? loc.processing.toUpperCase()
                                    : loc.closeRegisterZReportAction,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildRow(
    String label,
    Money amount, {
    double fontSize = 14,
    bool isBold = false,
    Color? color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: isBold
                ? AppDesignTokens.textPrimary
                : AppDesignTokens.textSecondary,
          ),
        ),
        MoneyDisplay(amount: amount, fontSize: fontSize, color: color),
      ],
    );
  }
}
