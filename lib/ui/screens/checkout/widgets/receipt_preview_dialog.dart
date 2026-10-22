import 'package:tracepos/core/logging/pos_logger.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracepos/core/localization/app_localizations.dart';
import 'package:tracepos/core/money/money.dart';
import 'package:tracepos/hardware/hardware_manager.dart';
import 'package:tracepos/hardware/receipt_printer/receipt_document.dart';
import 'package:tracepos/providers/app_providers.dart';
import 'package:tracepos/providers/auth_provider.dart';
import 'package:tracepos/ui/theme/app_design_tokens.dart';
import 'package:tracepos/ui/widgets/common/code128_barcode.dart';

class ReceiptPreviewDialog extends ConsumerStatefulWidget {
  final ReceiptDocument document;

  const ReceiptPreviewDialog({super.key, required this.document});

  static Future<void> show(
    BuildContext context, {
    required ReceiptDocument document,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ReceiptPreviewDialog(document: document),
    );
  }

  @override
  ConsumerState<ReceiptPreviewDialog> createState() =>
      _ReceiptPreviewDialogState();
}

class _ReceiptPreviewDialogState extends ConsumerState<ReceiptPreviewDialog> {
  bool _isPrinting = false;
  String? _statusMessage;

  Future<void> _reprint() async {
    final loc = context.loc;
    setState(() {
      _isPrinting = true;
      _statusMessage = null;
    });

    try {
      final reprintDoc = widget.document.isDuplicate
          ? widget.document
          : ReceiptDocument(
              storeName: widget.document.storeName,
              storeAddress: widget.document.storeAddress,
              storePhone: widget.document.storePhone,
              fiscalId: widget.document.fiscalId,
              receiptNumber: widget.document.receiptNumber,
              dateTime: widget.document.dateTime,
              cashierName: widget.document.cashierName,
              registerCode: widget.document.registerCode,
              lines: widget.document.lines,
              subtotal: widget.document.subtotal,
              discount: widget.document.discount,
              tax: widget.document.tax,
              total: widget.document.total,
              payments: widget.document.payments,
              footerMessage: widget.document.footerMessage,
              paperWidthMm: widget.document.paperWidthMm,
              isDuplicate: true,
            );

      await HardwareManager.instance.receiptPrinter.printReceipt(reprintDoc);

      // Log audit event for duplicate reprint without creating financial movements
      try {
        final auth = ref.read(authNotifierProvider);
        await ref
            .read(auditServiceProvider)
            .logEvent(
              action: 'receipt_reprinted',
              entityType: 'sale',
              entityId: widget.document.receiptNumber,
              userId: auth.user?.id ?? 'system',
              detailsJson: jsonEncode({
                'receiptNumber': widget.document.receiptNumber,
                'isDuplicate': true,
                'reprintedAt': DateTime.now().toIso8601String(),
              }),
            );
      } catch (e) {
        PosLogger.instance.warning('Receipt', 'Could not record reprint audit entry: $e');
      }

      if (mounted) {
        setState(() {
          _isPrinting = false;
          _statusMessage = loc.receiptPrintSuccess;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPrinting = false;
          _statusMessage = loc.receiptPrintError(e.toString());
        });
      }
    }
  }

  static const _ink = Color(0xFF111B33);
  static const _deepGreen = Color(0xFF14532D);
  static const _page = Color(0xFFF1F8F4);

  /// "SOUS-TOTAL" -> "Sous-total"
  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  /// VAT rate implied by a TTC total, shown only when it is a whole number.
  static String _taxRate(ReceiptDocument d) {
    final net = d.total.millimes - d.tax.millimes;
    if (d.tax <= Money.zero || net <= 0) return '';
    final pct = d.tax.millimes * 100 / net;
    final whole = pct.round();
    return (pct - whole).abs() < 0.6 ? ' ($whole%)' : '';
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final doc = widget.document;
    final dateStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(doc.dateTime);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 560,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        decoration: BoxDecoration(
          color: _page,
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusXl),
          boxShadow: AppDesignTokens.shadowLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: ClipPath(
                  clipper: _TornEdgeClipper(),
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
                    child: _paper(context, doc, dateStr),
                  ),
                ),
              ),
            ),
            if (_statusMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  _statusMessage!,
                  style: TextStyle(
                    color: _statusMessage!.contains('Erreur')
                        ? AppDesignTokens.danger
                        : AppDesignTokens.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        foregroundColor: AppDesignTokens.primary,
                        backgroundColor: Colors.white,
                        side: const BorderSide(
                          color: AppDesignTokens.primary,
                          width: 1.4,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      child: Text(_cap(loc.close)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isPrinting ? null : _reprint,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppDesignTokens.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size(0, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      icon: _isPrinting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.print_outlined, size: 22),
                      label: Text(
                        _isPrinting
                            ? loc.printingInProgress
                            : '${_cap(loc.reprintAction)} (F11)',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paper(BuildContext context, ReceiptDocument doc, String dateStr) {
    final loc = context.loc;
    return DefaultTextStyle(
      style: const TextStyle(color: _ink, fontSize: 13, height: 1.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (doc.isDuplicate)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                border: Border.all(color: _ink, width: 1.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                loc.receiptDuplicateBanner,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 2,
                ),
              ),
            ),

          // Store header: ── NAME ──
          Row(
            children: [
              const Expanded(child: Divider(color: AppDesignTokens.primary, thickness: 1.5)),
              Flexible(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    doc.storeName.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: _ink,
                    ),
                  ),
                ),
              ),
              const Expanded(child: Divider(color: AppDesignTokens.primary, thickness: 1.5)),
            ],
          ),
          if (doc.storeAddress != null && doc.storeAddress!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                doc.storeAddress!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          if (doc.storePhone != null && doc.storePhone!.isNotEmpty)
            _contactLine(Icons.phone_rounded, 'Tél: ${doc.storePhone!}'),
          if (doc.fiscalId != null && doc.fiscalId!.isNotEmpty)
            _contactLine(Icons.storefront_rounded, 'MF: ${doc.fiscalId!}'),

          const SizedBox(height: 14),
          const _Dashed(),
          const SizedBox(height: 12),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _meta(Icons.receipt_long_outlined, '${loc.receiptTicketLabel}: ${doc.receiptNumber}'),
                    const SizedBox(height: 8),
                    _meta(Icons.calendar_month_outlined, '${loc.receiptDateLabel}: $dateStr'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _meta(Icons.point_of_sale_outlined, '${loc.receiptRegisterLabel}: ${doc.registerCode}'),
                    const SizedBox(height: 8),
                    _meta(Icons.person_outline, '${loc.receiptCashierLabel}: ${doc.cashierName}'),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const _Dashed(),
          const SizedBox(height: 14),

          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: AppDesignTokens.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(flex: 6, child: _th(loc.receiptHeaderArticle)),
                Expanded(flex: 2, child: _th(loc.receiptHeaderQty, TextAlign.center)),
                Expanded(flex: 3, child: _th(loc.receiptHeaderPrice, TextAlign.right)),
                Expanded(flex: 3, child: _th(loc.receiptHeaderTotal, TextAlign.right)),
              ],
            ),
          ),
          const SizedBox(height: 10),

          for (final line in doc.lines) _lineRow(loc, line),

          const SizedBox(height: 4),
          const _Dashed(),
          const SizedBox(height: 12),

          _kv('${_cap(loc.receiptSubtotal)} :', doc.subtotal.format()),
          if (doc.discount > Money.zero)
            _kv('${_cap(loc.receiptDiscount)} :', '-${doc.discount.format()}',
                valueColor: AppDesignTokens.danger),
          if (doc.tax > Money.zero)
            _kv('${_cap(loc.receiptTax)}${_taxRate(doc)} :', doc.tax.format()),

          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppDesignTokens.primarySoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppDesignTokens.primarySoftBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${loc.receiptTotal} :',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _deepGreen,
                  ),
                ),
                Text(
                  doc.total.format(),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _deepGreen,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          for (final p in doc.payments) ...[
            _kv('${loc.receiptPaymentMode} :', p.method.toUpperCase()),
            if (p.tendered > Money.zero)
              _kv('${_cap(loc.receiptTendered)} :', p.tendered.format()),
            if (p.change > Money.zero)
              _kv('${_cap(loc.receiptChange)} :', p.change.format(), bold: true),
          ],

          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F5F4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE3E8E5)),
            ),
            child: Column(
              children: [
                Code128Barcode(data: doc.receiptNumber, height: 52),
                const SizedBox(height: 8),
                Text(
                  doc.receiptNumber,
                  style: const TextStyle(
                    fontSize: 12,
                    letterSpacing: 3,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),
          Text(
            doc.footerMessage ?? loc.receiptFooterGreeting,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
              color: AppDesignTokens.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            loc.receiptFooterPolicy,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _contactLine(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 15, color: AppDesignTokens.primary),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ],
    ),
  );

  Widget _meta(IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 17, color: const Color(0xFF475569)),
      const SizedBox(width: 8),
      Flexible(
        child: Text(text, style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155))),
      ),
    ],
  );

  Widget _th(String text, [TextAlign align = TextAlign.left]) => Text(
    text.toUpperCase(),
    textAlign: align,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      color: _deepGreen,
      letterSpacing: 0.3,
    ),
  );

  Widget _kv(String k, String v, {bool bold = false, Color? valueColor}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(fontSize: 14)),
            Text(
              v,
              style: TextStyle(
                fontSize: 14,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                color: valueColor,
              ),
            ),
          ],
        ),
      );

  Widget _lineRow(AppLocalizations loc, ReceiptLineItem line) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 6,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.productName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                          if (line.variantDescription.isNotEmpty)
                            Text(
                              line.variantDescription,
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                            ),
                          Text(
                            line.barcode.isNotEmpty ? line.barcode : line.sku,
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text('${line.quantity}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  line.unitPrice.format(includeCurrency: false),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF334155)),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  line.total.format(includeCurrency: false),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          if (line.discount > Money.zero)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${loc.receiptLineDiscount}:',
                    style: const TextStyle(color: AppDesignTokens.danger, fontSize: 12),
                  ),
                  Text(
                    '-${line.discount.format()}',
                    style: const TextStyle(color: AppDesignTokens.danger, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Dashed horizontal separator.
class _Dashed extends StatelessWidget {
  const _Dashed();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DashPainter(), size: const Size(double.infinity, 1));
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFB6BFBA)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, 0), Offset(x + 3.5, 0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Rounded top corners and a zig-zag torn bottom edge, like a paper ticket.
class _TornEdgeClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const r = 14.0;
    const tooth = 9.0;
    final path = Path()
      ..moveTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(size.width - r, 0)
      ..quadraticBezierTo(size.width, 0, size.width, r)
      ..lineTo(size.width, size.height - tooth);
    var x = size.width;
    var down = true;
    final step = size.width / (size.width / tooth).floor();
    while (x > 0) {
      x = (x - step / 2).clamp(0, size.width);
      path.lineTo(x, down ? size.height : size.height - tooth);
      down = !down;
    }
    path.lineTo(0, size.height - tooth);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> old) => false;
}
