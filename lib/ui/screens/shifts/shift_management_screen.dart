import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/providers/shift_provider.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';
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
    final ctrl = TextEditingController(text: '150.000');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Ouvrir la session de caisse'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Saisissez le fond de caisse initial (TND) :'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Fond initial',
                suffixText: 'TND',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
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
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            child: const Text('Ouvrir la caisse'),
          ),
        ],
      ),
    );
  }

  void _showCashMovementDialog(String type) {
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final isPayIn = type == 'PAY_IN';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          isPayIn
              ? 'Entrée d\'espèces (Appoint)'
              : 'Sortie d\'espèces (Prélèvement / Dépense)',
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
              decoration: const InputDecoration(
                labelText: 'Montant (TND)',
                suffixText: 'TND',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(
                labelText: 'Motif / Justificatif *',
                hintText: isPayIn
                    ? 'ex: Monnaie pièces'
                    : 'ex: Dépense pressing / Prélèvement gérant',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              final val = double.tryParse(amountCtrl.text) ?? 0;
              final reason = reasonCtrl.text.trim();
              if (val <= 0 || reason.isEmpty) return;

              final auth = ref.read(authNotifierProvider);
              await ref
                  .read(shiftNotifierProvider.notifier)
                  .recordCashMovement(
                    userId: auth.user?.id ?? 'system',
                    type: type,
                    amount: Money.fromTnd(val),
                    reason: reason,
                  );
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isPayIn ? AppTheme.primary : AppTheme.warning,
            ),
            child: const Text('Valider le mouvement'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitCloseShift() async {
    final countedVal = Money.parse(_countedBuffer.toString());
    final auth = ref.read(authNotifierProvider);

    setState(() => _isClosing = true);

    try {
      await ref
          .read(shiftNotifierProvider.notifier)
          .closeShift(
            cashierId: auth.user?.id ?? 'system',
            countedCash: countedVal,
            note: 'Clôture de caisse standard',
          );

      setState(() => _isClosing = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Session de caisse clôturée avec succès (Z-Report généré)',
            ),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isClosing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shiftState = ref.watch(shiftNotifierProvider);
    final activeShift = shiftState.activeShift;
    final summary = shiftState.summary;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Gestion de Caisse & Clôture (Z-Report)'),
        backgroundColor: AppTheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref
                .read(shiftNotifierProvider.notifier)
                .checkActiveShift(widget.registerId),
            tooltip: 'Actualiser les totaux',
          ),
        ],
      ),
      body: activeShift == null
          ? Center(
              child: Container(
                width: 450,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.point_of_sale,
                      size: 64,
                      color: AppTheme.warning,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Caisse Actuellement Fermée',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Poste: ${widget.registerId}',
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _openShiftDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.lock_open),
                        label: const Text(
                          'OUVRIR LA SESSION DE CAISSE',
                          style: TextStyle(fontWeight: FontWeight.bold),
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
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Session ouverte à ${DateFormat('HH:mm le dd/MM/yyyy').format(activeShift.openedAt)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'Poste: ${widget.registerId} • Shift ID: ${activeShift.id.substring(0, 8)}...',
                                    style: const TextStyle(
                                      color: AppTheme.textSecondary,
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
                                    icon: const Icon(
                                      Icons.arrow_downward,
                                      size: 16,
                                      color: AppTheme.success,
                                    ),
                                    label: const Text(
                                      'Entrée (+)',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _showCashMovementDialog('PAY_OUT'),
                                    icon: const Icon(
                                      Icons.arrow_upward,
                                      size: 16,
                                      color: AppTheme.warning,
                                    ),
                                    label: const Text(
                                      'Sortie (-)',
                                      style: TextStyle(fontSize: 12),
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
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Column(
                            children: [
                              _buildRow(
                                'Fond de caisse initial :',
                                summary?.openingCash ?? Money.zero,
                              ),
                              const Divider(color: AppTheme.border, height: 20),
                              _buildRow(
                                'Ventes en Espèces (+):',
                                summary?.cashSales ?? Money.zero,
                                color: Colors.blueAccent,
                              ),
                              const SizedBox(height: 8),
                              _buildRow(
                                'Ventes par Carte Bancaire:',
                                summary?.cardSales ?? Money.zero,
                              ),
                              const SizedBox(height: 8),
                              _buildRow(
                                'Remboursements Espèces (-):',
                                summary?.cashRefunds ?? Money.zero,
                                color: AppTheme.error,
                              ),
                              const SizedBox(height: 8),
                              _buildRow(
                                'Entrées manuelles espèces (+):',
                                summary?.cashIn ?? Money.zero,
                              ),
                              const SizedBox(height: 8),
                              _buildRow(
                                'Sorties manuelles / Dépôt (-):',
                                summary?.cashOut ?? Money.zero,
                                color: AppTheme.warning,
                              ),
                              const Divider(color: AppTheme.border, height: 24),
                              _buildRow(
                                'SOLDE ESPÈCES ATTENDU EN CAISSE :',
                                summary?.expectedCash ?? Money.zero,
                                fontSize: 20,
                                isBold: true,
                                color: AppTheme.success,
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
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Comptage Réel & Clôture (Z-Report)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Saisissez le montant total d\'espèces compté physiquement dans le tiroir :',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 16),

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
                              _countedBuffer.isEmpty
                                  ? '0.000'
                                  : _countedBuffer.toString(),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
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
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: _isClosing ? null : _submitCloseShift,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.error,
                                foregroundColor: Colors.white,
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
                              label: const Text(
                                'CLÔTURER LA CAISSE (Z-REPORT)',
                                style: TextStyle(fontWeight: FontWeight.bold),
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
          ),
        ),
        MoneyDisplay(amount: amount, fontSize: fontSize, color: color),
      ],
    );
  }
}
