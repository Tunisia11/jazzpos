import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:tracepos/core/constants/app_constants.dart';
import 'package:tracepos/core/logging/pos_logger.dart';
import 'package:tracepos/core/money/money.dart';
import 'package:tracepos/domain/services/report_service.dart';
import 'package:tracepos/hardware/receipt_printer/receipt_document.dart';
import 'package:tracepos/providers/app_providers.dart';
import 'package:tracepos/providers/auth_provider.dart';
import 'package:tracepos/ui/screens/checkout/widgets/receipt_preview_dialog.dart';
import 'package:tracepos/ui/screens/dashboard/sale_labels.dart';
import 'package:tracepos/ui/theme/app_design_tokens.dart';
import 'package:tracepos/ui/widgets/common/product_thumbnail.dart';

/// Everything about one sale: items with photos, totals, payments, who sold it
/// and any returns, with a button to view / reprint the receipt.
class OrderDetailsScreen extends ConsumerStatefulWidget {
  final String saleId;
  const OrderDetailsScreen({super.key, required this.saleId});

  @override
  ConsumerState<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends ConsumerState<OrderDetailsScreen> {
  static const _green = AppDesignTokens.primary;
  static const _greenDark = Color(0xFF0F5132);

  OrderDetails? _order;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final actor = ref.read(authNotifierProvider).user?.id ?? '';
      final order = await ref
          .read(reportServiceProvider)
          .getOrderDetails(actorId: actor, saleId: widget.saleId);
      if (mounted) setState(() => _order = order);
    } catch (e) {
      PosLogger.instance.warning('OrderDetails', 'Could not load order: $e');
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Money _m(int millimes) => Money.fromMillimes(millimes);

  ReceiptDocument _receipt(OrderDetails o) {
    final sale = o.sale;
    return ReceiptDocument(
      storeName: o.company?.name ?? o.store?.name ?? AppConstants.appName,
      storeAddress: o.store?.address ?? o.company?.address,
      storePhone: o.store?.phone ?? o.company?.phone,
      fiscalId: o.company?.fiscalId,
      receiptNumber: sale.receiptNumber,
      dateTime: sale.createdAt,
      cashierName: o.cashierName,
      registerCode: o.registerCode,
      lines: [
        for (final l in o.lines)
          ReceiptLineItem(
            productName: l.line.productName,
            variantDescription: l.line.variantDescription,
            sku: l.line.sku,
            barcode: l.line.barcode,
            quantity: l.line.quantity,
            unitPrice: _m(l.line.unitPriceMillimes),
            total: _m(l.line.totalMillimes),
            discount: _m(l.line.discountMillimes),
          ),
      ],
      subtotal: _m(sale.subtotalMillimes),
      discount: _m(sale.discountMillimes),
      tax: _m(sale.taxMillimes),
      total: _m(sale.totalMillimes),
      payments: [
        for (final p in o.payments)
          ReceiptPaymentItem(
            method: p.paymentMethod,
            amount: _m(p.amountMillimes),
            tendered: _m(p.tenderedMillimes),
            change: _m(p.changeMillimes),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    return Scaffold(
      backgroundColor: AppDesignTokens.background,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(o),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : (o == null ? _errorState() : _body(o)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.receipt_long, size: 44, color: AppDesignTokens.textMuted),
        const SizedBox(height: 12),
        Text(
          _error ?? 'Commande indisponible',
          style: const TextStyle(color: AppDesignTokens.textSecondary),
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _load, child: const Text('Réessayer')),
      ],
    ),
  );

  Widget _topBar(OrderDetails? o) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).maybePop(),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppDesignTokens.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppDesignTokens.border),
              ),
              child: const Icon(
                Icons.arrow_back,
                size: 20,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Détails de la commande',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              if (o != null)
                Text(
                  o.sale.receiptNumber,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
            ],
          ),
          const Spacer(),
          if (o != null) ...[
            SaleStatusChip(o.sale.status),
            const SizedBox(width: 14),
            FilledButton.icon(
              onPressed: () =>
                  ReceiptPreviewDialog.show(context, document: _receipt(o)),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Ticket / Réimprimer'),
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _body(OrderDetails o) {
    return LayoutBuilder(
      builder: (context, c) {
        final left = Column(
          children: [
            _hero(o),
            const SizedBox(height: 16),
            _itemsCard(o),
            if (o.returns.isNotEmpty) ...[
              const SizedBox(height: 16),
              _returnsCard(o),
            ],
          ],
        );
        final right = Column(
          children: [
            _summaryCard(o),
            const SizedBox(height: 16),
            _paymentsCard(o),
            const SizedBox(height: 16),
            _infoCard(o),
          ],
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: c.maxWidth < 1000
              ? Column(children: [left, const SizedBox(height: 16), right])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: left),
                    const SizedBox(width: 16),
                    Expanded(flex: 4, child: right),
                  ],
                ),
        );
      },
    );
  }

  // ── cards ────────────────────────────────────────────────────────────────

  Widget _card({
    required IconData icon,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppDesignTokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppDesignTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _green, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _hero(OrderDetails o) {
    final sale = o.sale;
    final date = DateFormat('dd/MM/yyyy · HH:mm').format(sale.createdAt);
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_greenDark, Color(0xFF1A7A47)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TOTAL DE LA COMMANDE',
                    style: TextStyle(
                      color: Color(0xFFA7E3BE),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _m(sale.totalMillimes).format(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    date,
                    style: const TextStyle(
                      color: Color(0xFFD2F0DE),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            _heroStat('Articles', '${o.itemCount}'),
            const SizedBox(width: 32),
            _heroStat('Lignes', '${o.lines.length}'),
          ],
        ),
      ),
    );
  }

  Widget _heroStat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: Color(0xFFD2F0DE), fontSize: 13),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );

  Widget _itemsCard(OrderDetails o) {
    const head = TextStyle(fontSize: 12, color: AppDesignTokens.textSecondary);
    return _card(
      icon: Icons.checkroom,
      title: 'Articles (${o.itemCount})',
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppDesignTokens.surfaceSecondary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                SizedBox(width: 72),
                Expanded(flex: 5, child: Text('Article', style: head)),
                Expanded(flex: 1, child: Text('Qté', style: head)),
                Expanded(flex: 2, child: Text('Prix unit.', style: head)),
                Expanded(flex: 2, child: Text('Remise', style: head)),
                Expanded(
                  flex: 2,
                  child: Text('Total', style: head, textAlign: TextAlign.end),
                ),
              ],
            ),
          ),
          for (final l in o.lines) _lineRow(l),
        ],
      ),
    );
  }

  Widget _lineRow(OrderLineDetail d) {
    final l = d.line;
    final detail = [
      if (l.variantDescription.isNotEmpty && l.variantDescription != 'Standard')
        l.variantDescription,
      if (l.sku.isNotEmpty) l.sku,
    ].join('  ·  ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppDesignTokens.borderSubtle)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Align(
              alignment: Alignment.centerLeft,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 56,
                  height: 64,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: ProductThumbnail(
                      imageUrl: d.imageUrl,
                      size: 64,
                      borderRadius: 0,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.productName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                if (l.barcode.isNotEmpty)
                  Text(
                    l.barcode,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppDesignTokens.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Text('${l.quantity}', style: const TextStyle(fontSize: 14)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _m(l.unitPriceMillimes).format(),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              l.discountMillimes > 0
                  ? '-${_m(l.discountMillimes).format()}'
                  : '—',
              style: TextStyle(
                fontSize: 14,
                color: l.discountMillimes > 0
                    ? AppDesignTokens.danger
                    : AppDesignTokens.textMuted,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _m(l.totalMillimes).format(),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppDesignTokens.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 14,
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                color: valueColor ?? AppDesignTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(OrderDetails o) {
    final s = o.sale;
    return _card(
      icon: Icons.receipt_long,
      title: 'Résumé',
      child: Column(
        children: [
          _row('Sous-total', _m(s.subtotalMillimes).format()),
          _row(
            'Remise',
            s.discountMillimes > 0 ? '-${_m(s.discountMillimes).format()}' : _m(0).format(),
            valueColor: s.discountMillimes > 0 ? AppDesignTokens.danger : null,
          ),
          if (s.taxMillimes > 0) _row('TVA incluse', _m(s.taxMillimes).format()),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppDesignTokens.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Text(
                  'Total TTC',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _m(s.totalMillimes).format(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _green,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (o.returns.isNotEmpty) ...[
            const SizedBox(height: 8),
            _row(
              'Remboursé',
              '-${o.refunded.format()}',
              valueColor: AppDesignTokens.danger,
            ),
            _row(
              'Net après retours',
              (_m(s.totalMillimes) - o.refunded).format(),
              bold: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _paymentsCard(OrderDetails o) {
    return _card(
      icon: Icons.payments_outlined,
      title: 'Paiement',
      child: o.payments.isEmpty
          ? const Text(
              'Aucun paiement enregistré.',
              style: TextStyle(color: AppDesignTokens.textSecondary),
            )
          : Column(
              children: [
                for (final p in o.payments)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppDesignTokens.border),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppDesignTokens.primarySoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                paymentMethodIcon(p.paymentMethod),
                                color: _green,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                paymentMethodLabel(p.paymentMethod),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              _m(p.amountMillimes).format(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _green,
                              ),
                            ),
                          ],
                        ),
                        if (p.tenderedMillimes > 0 &&
                            p.paymentMethod == AppConstants.paymentCash) ...[
                          const SizedBox(height: 6),
                          _row('Montant reçu', _m(p.tenderedMillimes).format()),
                          _row('Rendu', _m(p.changeMillimes).format()),
                        ],
                        if ((p.reference ?? '').isNotEmpty)
                          _row('Référence', p.reference!),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _infoCard(OrderDetails o) {
    final s = o.sale;
    final c = o.customer;
    return _card(
      icon: Icons.info_outline,
      title: 'Informations',
      child: Column(
        children: [
          _row('Date', DateFormat('dd/MM/yyyy').format(s.createdAt)),
          _row('Heure', DateFormat('HH:mm:ss').format(s.createdAt)),
          _row('Caissier', o.cashierName),
          _row('Caisse', o.registerCode),
          if (o.store != null) _row('Magasin', o.store!.name),
          _row('Client', c == null ? 'Client de passage' : '${c.name}${c.phone == null ? '' : ' · ${c.phone}'}'),
          _row('Synchronisée', s.offlineSynced ? 'Oui' : 'Non'),
          if ((s.notes ?? '').trim().isNotEmpty) ...[
            const Divider(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Note',
                style: TextStyle(
                  color: AppDesignTokens.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(s.notes!.trim(), style: const TextStyle(fontSize: 14)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _returnsCard(OrderDetails o) {
    return _card(
      icon: Icons.swap_horiz,
      title: 'Retours (${o.returns.length})',
      child: Column(
        children: [
          for (final r in o.returns)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppDesignTokens.dangerBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.undo, color: AppDesignTokens.danger, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.returnNumber,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${DateFormat('dd/MM/yyyy HH:mm').format(r.createdAt)} · ${r.reason} · ${paymentMethodLabel(r.refundMethod)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '-${_m(r.totalRefundMillimes).format()}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppDesignTokens.danger,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
