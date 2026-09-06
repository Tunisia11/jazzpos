import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'package:jazzpos/ui/widgets/common/app_button.dart';
import 'package:jazzpos/ui/widgets/common/app_empty_state.dart';
import 'package:jazzpos/ui/widgets/money_display.dart';
import 'goods_receiving_screen.dart';

class PurchaseOrdersScreen extends ConsumerStatefulWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  ConsumerState<PurchaseOrdersScreen> createState() =>
      _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends ConsumerState<PurchaseOrdersScreen> {
  List<PurchaseOrder> _orders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    final db = ref.read(databaseProvider);
    final orders = await (db.select(
      db.purchaseOrders,
    )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();

    if (mounted) {
      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    }
  }

  void _openGoodsReceiving({String? poId}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => GoodsReceivingScreen(purchaseOrderId: poId),
      ),
    );
    _loadOrders();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    return Scaffold(
      backgroundColor: AppDesignTokens.canvas,
      appBar: AppBar(
        title: Text(
          loc.purchaseOrdersTitle,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        backgroundColor: AppDesignTokens.surface,
        foregroundColor: AppDesignTokens.textPrimary,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppDesignTokens.border),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.refresh,
              color: AppDesignTokens.textSecondary,
            ),
            onPressed: _loadOrders,
            tooltip: loc.refresh,
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: AppButton(
              onPressed: () => _openGoodsReceiving(),
              variant: AppButtonVariant.primary,
              icon: Icons.inventory,
              label: loc.goodsReceivingTitle.toUpperCase(),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppDesignTokens.primary),
            )
          : _orders.isEmpty
          ? Center(
              child: AppEmptyState(
                icon: Icons.local_shipping_outlined,
                title: loc.noOrdersRecorded,
                action: AppButton(
                  onPressed: () => _openGoodsReceiving(),
                  variant: AppButtonVariant.primary,
                  icon: Icons.add,
                  label: loc.registerSupplierReceipt,
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsetsDirectional.all(20),
              child: Container(
                decoration: BoxDecoration(
                  color: AppDesignTokens.surface,
                  borderRadius: BorderRadius.circular(
                    AppDesignTokens.radiusCard,
                  ),
                  border: Border.all(color: AppDesignTokens.border),
                  boxShadow: AppDesignTokens.shadowSm,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    AppDesignTokens.radiusCard,
                  ),
                  child: ListView.separated(
                    itemCount: _orders.length,
                    separatorBuilder: (_, __) => const Divider(
                      color: AppDesignTokens.border,
                      height: 1,
                      thickness: 1,
                    ),
                    itemBuilder: (context, index) {
                      final po = _orders[index];
                      final isReceived = po.status == 'RECEIVED';

                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isReceived
                                ? AppDesignTokens.successBg
                                : AppDesignTokens.warningBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            isReceived ? Icons.check_circle : Icons.schedule,
                            color: isReceived
                                ? AppDesignTokens.successText
                                : AppDesignTokens.warningText,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          '${loc.orderReference} #${po.poNumber}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          '${loc.date}: ${DateFormat("dd/MM/yyyy HH:mm").format(po.createdAt)} • ${loc.status}: ${po.status}',
                          style: const TextStyle(
                            color: AppDesignTokens.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MoneyDisplay(
                              amount: Money.fromMillimes(po.totalCostMillimes),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                            const SizedBox(width: 16),
                            if (!isReceived)
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _openGoodsReceiving(poId: po.id),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppDesignTokens.primary,
                                  side: const BorderSide(
                                    color: AppDesignTokens.border,
                                  ),
                                  backgroundColor: AppDesignTokens.surface,
                                ),
                                icon: const Icon(Icons.file_download, size: 16),
                                label: Text(
                                  loc.receiveGoods,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
    );
  }
}
