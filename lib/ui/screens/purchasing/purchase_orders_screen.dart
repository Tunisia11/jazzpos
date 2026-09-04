import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';
import 'package:jazzpos/ui/widgets/money_display.dart';
import 'goods_receiving_screen.dart';

class PurchaseOrdersScreen extends ConsumerStatefulWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  ConsumerState<PurchaseOrdersScreen> createState() => _PurchaseOrdersScreenState();
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
    final orders = await (db.select(db.purchaseOrders)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();

    if (mounted) {
      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    }
  }

  void _openGoodsReceiving({String? poId}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (ctx) => GoodsReceivingScreen(purchaseOrderId: poId)),
    );
    _loadOrders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Achats & Commandes Fournisseurs'),
        backgroundColor: AppTheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOrders,
            tooltip: 'Actualiser',
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: () => _openGoodsReceiving(),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
              icon: const Icon(Icons.inventory, size: 20),
              label: const Text('RÉCEPTION MARCHANDISES'),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.local_shipping_outlined, size: 64, color: AppTheme.textSecondary),
                      const SizedBox(height: 16),
                      const Text('Aucune commande ou réception enregistrée', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => _openGoodsReceiving(),
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('Enregistrer une Réception Fournisseur'),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: ListView.separated(
                      itemCount: _orders.length,
                      separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1),
                      itemBuilder: (context, index) {
                        final po = _orders[index];
                        final isReceived = po.status == 'RECEIVED';

                        return ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isReceived ? AppTheme.success.withValues(alpha: 0.15) : AppTheme.warning.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              isReceived ? Icons.check_circle : Icons.schedule,
                              color: isReceived ? AppTheme.success : AppTheme.warning,
                            ),
                          ),
                          title: Text(
                            'Commande #${po.poNumber}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          subtitle: Text(
                            'Date: ${DateFormat("dd/MM/yyyy HH:mm").format(po.createdAt)} • Statut: ${po.status}',
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              MoneyDisplay(amount: Money.fromMillimes(po.totalCostMillimes), fontSize: 16),
                              const SizedBox(width: 16),
                              if (!isReceived)
                                ElevatedButton.icon(
                                  onPressed: () => _openGoodsReceiving(poId: po.id),
                                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                                  icon: const Icon(Icons.file_download, size: 16),
                                  label: const Text('Réceptionner', style: TextStyle(fontSize: 12)),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
    );
  }
}
