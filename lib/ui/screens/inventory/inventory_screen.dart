import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/catalog_service.dart';
import 'package:jazzpos/domain/services/inventory_service.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';
import 'package:jazzpos/ui/widgets/money_display.dart';
import 'stock_count_screen.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<StockLocation> _locations = [];
  List<StockMovement> _movements = [];
  List<VariantSearchResult> _variants = [];
  String? _selectedLocationId;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final db = ref.read(databaseProvider);
    final catalogService = ref.read(catalogServiceProvider);

    final locations = await db.select(db.stockLocations).get();
    final movements = await (db.select(db.stockMovements)
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(100))
        .get();
    final variants = await catalogService.searchVariants(_searchCtrl.text);

    if (mounted) {
      setState(() {
        _locations = locations;
        _movements = movements;
        _variants = variants;
        if (_locations.isNotEmpty && _selectedLocationId == null) {
          _selectedLocationId = _locations.first.id;
        }
        _isLoading = false;
      });
    }
  }

  void _openStockCount() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => StockCountScreen(
          locationId: _selectedLocationId ?? 'LOC-SHOP',
        ),
      ),
    );
    _loadData();
  }

  Future<void> _showTransferDialog(VariantSearchResult variant) async {
    if (_locations.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Au moins deux emplacements de stock sont requis'), backgroundColor: AppTheme.warning),
      );
      return;
    }

    String fromLoc = _locations.first.id;
    String toLoc = _locations[1].id;
    final qtyCtrl = TextEditingController(text: '1');
    final reasonCtrl = TextEditingController(text: 'Réassort rayon');

    final success = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text('Transfert de stock : ${variant.productName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Variante: ${variant.variantDescription} (SKU: ${variant.sku})'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: fromLoc,
                decoration: const InputDecoration(labelText: 'Emplacement Source'),
                items: _locations.map((l) => DropdownMenuItem(value: l.id, child: Text(l.name))).toList(),
                onChanged: (v) => setDialogState(() => fromLoc = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: toLoc,
                decoration: const InputDecoration(labelText: 'Emplacement Destination'),
                items: _locations.map((l) => DropdownMenuItem(value: l.id, child: Text(l.name))).toList(),
                onChanged: (v) => setDialogState(() => toLoc = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantité à transférer'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(labelText: 'Motif du transfert'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                final qty = int.tryParse(qtyCtrl.text) ?? 0;
                if (qty <= 0 || fromLoc == toLoc) return;

                final invService = ref.read(inventoryServiceProvider);
                final auth = ref.read(authNotifierProvider);

                await invService.transferStock(
                  variantId: variant.variantId,
                  fromLocationId: fromLoc,
                  toLocationId: toLoc,
                  quantity: qty,
                  actorId: auth.user?.id ?? 'system',
                  reason: reasonCtrl.text.trim(),
                );
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Effectuer le Transfert'),
            ),
          ],
        ),
      ),
    );

    if (success == true) {
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transfert effectué avec succès !'), backgroundColor: AppTheme.success),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Gestion des Stocks & Mouvements'),
        backgroundColor: AppTheme.surface,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(icon: Icon(Icons.inventory_2), text: 'NIVEAUX DE STOCK PAR ARTICLE'),
            Tab(icon: Icon(Icons.history), text: 'HISTORIQUE DES MOUVEMENTS (AUDIT)'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: _openStockCount,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning, foregroundColor: Colors.black),
              icon: const Icon(Icons.fact_check, size: 20),
              label: const Text('LANCER UN INVENTAIRE', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Current Stock Levels
                _buildStockLevelsTab(),

                // Tab 2: Stock Movements Ledger
                _buildMovementsTab(),
              ],
            ),
    );
  }

  Widget _buildStockLevelsTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Filter Bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Filtrer les articles par nom, SKU ou code-barres...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchCtrl.clear();
                                _loadData();
                              },
                            )
                          : null,
                    ),
                    onSubmitted: (_) => _loadData(),
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadData,
                  tooltip: 'Actualiser',
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Variants Stock Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: ListView.separated(
                itemCount: _variants.length,
                separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1),
                itemBuilder: (context, index) {
                  final v = _variants[index];
                  final isLowStock = v.stock <= 2;

                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isLowStock ? AppTheme.error.withValues(alpha: 0.15) : AppTheme.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isLowStock ? Icons.warning_amber : Icons.check_circle_outline,
                        color: isLowStock ? AppTheme.error : AppTheme.success,
                      ),
                    ),
                    title: Text(v.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text('${v.variantDescription} • SKU: ${v.sku} • Code: ${v.barcode}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${v.stock} en stock',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: isLowStock ? AppTheme.error : Colors.white,
                              ),
                            ),
                            MoneyDisplay(amount: v.salePrice, fontSize: 12),
                          ],
                        ),
                        const SizedBox(width: 16),
                        OutlinedButton.icon(
                          onPressed: () => _showTransferDialog(v),
                          icon: const Icon(Icons.swap_horiz, size: 16),
                          label: const Text('Transférer', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovementsTab() {
    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: _movements.isEmpty
          ? const Center(child: Text('Aucun mouvement de stock enregistré', style: TextStyle(color: AppTheme.textSecondary)))
          : ListView.separated(
              itemCount: _movements.length,
              separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1),
              itemBuilder: (context, index) {
                final m = _movements[index];
                final isPositive = m.quantityDelta > 0;

                return ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isPositive ? AppTheme.success.withValues(alpha: 0.15) : AppTheme.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      isPositive ? Icons.arrow_downward : Icons.arrow_upward,
                      color: isPositive ? AppTheme.success : AppTheme.error,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    'Type: ${m.movementType} (${m.referenceType ?? ""})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Réf: ${m.referenceId ?? "Manuel"} • Date: ${DateFormat("dd/MM/yyyy HH:mm").format(m.createdAt)}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  trailing: Text(
                    isPositive ? '+${m.quantityDelta}' : '${m.quantityDelta}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isPositive ? AppTheme.success : AppTheme.error,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
