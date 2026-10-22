import 'package:flutter/material.dart';
import 'package:tracepos/core/constants/app_constants.dart';
import 'package:tracepos/ui/theme/app_design_tokens.dart';

/// Shared display text/colours for payment methods and sale statuses.
String paymentMethodLabel(String m) {
  switch (m) {
    case AppConstants.paymentCash:
      return 'Espèces';
    case AppConstants.paymentCard:
      return 'Carte / TPE';
    case AppConstants.paymentMixed:
      return 'Mixte';
    case AppConstants.paymentStoreCredit:
      return 'Avoir';
    case '':
      return '—';
    default:
      return 'Autre';
  }
}

IconData paymentMethodIcon(String m) {
  switch (m) {
    case AppConstants.paymentCard:
      return Icons.credit_card;
    case AppConstants.paymentCash:
      return Icons.payments_outlined;
    default:
      return Icons.account_balance_wallet_outlined;
  }
}

String saleStatusLabel(String status) {
  switch (status) {
    case AppConstants.saleCompleted:
      return 'Terminée';
    case AppConstants.saleRefunded:
      return 'Remboursée';
    case AppConstants.salePartiallyRefunded:
      return 'Part. remboursée';
    case AppConstants.saleExchanged:
      return 'Échangée';
    case AppConstants.saleVoided:
      return 'Annulée';
    default:
      return status;
  }
}

Color saleStatusColor(String status) {
  switch (status) {
    case AppConstants.saleCompleted:
      return AppDesignTokens.primary;
    case AppConstants.saleRefunded:
    case AppConstants.salePartiallyRefunded:
    case AppConstants.saleVoided:
      return AppDesignTokens.danger;
    default:
      return AppDesignTokens.warning;
  }
}

/// Rounded pill showing a sale status.
class SaleStatusChip extends StatelessWidget {
  final String status;
  const SaleStatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = saleStatusColor(status);
    final done = status == AppConstants.saleCompleted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(done ? Icons.check : Icons.info_outline, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            saleStatusLabel(status),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
