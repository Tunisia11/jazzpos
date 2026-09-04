import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/domain/services/inventory_count_service.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';
import 'package:jazzpos/ui/widgets/barcode_scanner_listener.dart';
import 'package:jazzpos/ui/widgets/manager_override_dialog.dart';

class StockCountScreen extends ConsumerStatefulWidget {
  final String locationId;

  const StockCountScreen({
    super.key,
    this.locationId = 'LOC-SHOP',
  });

  @override
  ConsumerState<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends ConsumerState<StockCountScreen> {
  String? _countId;
  List<InventoryCountLineWithDetails> _lines = [];
  bool _isLoading = true;
  final TextEditingController _barcodeInputCtrl = TextEditingController();
  final FocusNode _barcodeFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _initOrResumeCount();
  }

  @override
  void dispose() {
    _barcodeInputCtrl.dispose();
    _barcodeFocus.dispose();
    super.dispose();
  }

  Future<void> _initOrResumeCount() async {
    setState(() => _isLoading = true);
    final countService = ref.read(inventoryCountServiceProvider);
    final auth = ref.read(authNotifierProvider);

    try {
      // Initiate a new audit count
      final id = await countService.initiateCount(
        locationId: widget.locationId,
        initiatedById: auth.user?.id ?? 'system',
      );
      _countId = id;
      await _loadLines();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadLines() async {
    if (_countId == null) return;
    final countService = ref.read(inventoryCountServiceProvider);
    final lines = await countService.getCountLines(_countId!);
    if (mounted) {
      setState(() => _lines = lines);
    }
  }

  Future<void> _handleBarcode(String barcode) async {
    final clean = barcode.trim();
    if (clean.isEmpty || _countId == null) return;

    final countService = ref.read(inventoryCountServiceProvider);

    try {
      await countService.recordScannedVariant(
        countId: _countId!,
        barcodeOrSku: clean,
        increment: 1,
      );

      await _loadLines();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Compté +1 : $clean'),
            duration: const Duration(milliseconds: 700),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            duration: const Duration(seconds: 2),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      _barcodeInputCtrl.clear();
      _barcodeFocus.requestFocus();
    }
  }

  Future<void> _reconcileAndFinish() async {
    if (_countId == null) return;

    final auth = ref.read(authNotifierProvider);
    String? managerId = auth.user?.id;

    // If cashier is not manager/owner, prompt manager override
    if (auth.user?.role != 'OWNER' && auth.user?.role != 'MANAGER') {
      final manager = await ManagerOverrideDialog.show(
        context,
        actionTitle: 'Clôture et réconciliation d\'inventaire',
      );
      if (manager == null) return;
      managerId = manager.id;
    }

    try {
      final countService = ref.read(inventoryCountServiceProvider);
      await countService.reconcileAndComplete(countId: _countId!, managerId: managerId!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Inventaire réconcilié et stocks ajustés avec succès !'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    int totalCounted = 0;
    int totalDiscrepancies = 0;
    int varianceCostMillimes = 0;

    for (final l in _lines) {
      totalCounted += l.line.countedQuantity;
      if (l.line.differenceQuantity != 0) {
        totalDiscrepancies++;
        varianceCostMillimes += l.line.differenceQuantity * l.line.unitCostMillimes;
      }
    }

    return BarcodeScannerListener(
      onBarcodeScanned: _handleBarcode,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Session d\'Inventaire & Audit de Stock'),
          backgroundColor: AppTheme.surface,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _reconcileAndFinish,
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, foregroundColor: Colors.white),
                icon: const Icon(Icons.check_circle_outline, size: 20),
                label: const Text('RÉCONCILIER & CLÔTURER'),
              ),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Top Bar: Barcode Input + Stats Cards
                    Row(
                      children: [
                        // Rapid Barcode Input Field
                        Expanded(
                          flex: 5,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.qr_code_scanner, color: AppTheme.primaryLight, size: 28),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: _barcodeInputCtrl,
                                    focusNode: _barcodeFocus,
                                    autofocus: true,
                                    decoration: const InputDecoration(
                                      hintText: 'Scannez le code-barres de l\'article ou tapez le SKU...',
                                      border: InputBorder.none,
                                    ),
                                    onSubmitted: _handleBarcode,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.send, color: AppTheme.primary),
                                  onPressed: () => _handleBarcode(_barcodeInputCtrl.text),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(width: 16),

                        // Stats Card 1: Total Scanned
                        _buildStatCard(
                          title: 'Total Pièces Comptées',
                          value: '$totalCounted',
                          color: AppTheme.primaryLight,
                          icon: Icons.checkroom,
                        ),

                        const SizedBox(width: 12),

                        // Stats Card 2: Discrepancies
                        _buildStatCard(
                          title: 'Articles en Écart',
                          value: '$totalDiscrepancies',
                          color: totalDiscrepancies > 0 ? AppTheme.warning : AppTheme.success,
                          icon: Icons.difference,
                        ),

                        const SizedBox(width: 12),

                        // Stats Card 3: Value Variance
                        _buildStatCard(
                          title: 'Valeur de l\'Écart',
                          value: Money.fromMillimes(varianceCostMillimes).format(),
                          color: varianceCostMillimes < 0 ? AppTheme.error : AppTheme.success,
                          icon: Icons.attach_money,
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Inventory Lines Table
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: ListView.separated(
                          itemCount: _lines.length,
                          separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1),
                          itemBuilder: (context, index) {
                            final item = _lines[index];
                            final diff = item.line.differenceQuantity;
                            final isDifferent = diff != 0;

                            return Container(
                              color: isDifferent ? AppTheme.warning.withValues(alpha: 0.05) : Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              child: Row(
                                children: [
                                  // Product & Variant
                                  Expanded(
                                    flex: 4,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.product.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        Text(
                                          '${item.attributeDesc} • Code: ${item.variant.barcode}',
                                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Expected Stock
                                  Expanded(
                                    flex: 2,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        const Text('Théorique', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                                        Text('${item.line.expectedQuantity}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),

                                  // Counted Stock with Quick Adjusters
                                  Expanded(
                                    flex: 3,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.remove, size: 16),
                                          onPressed: item.line.countedQuantity > 0
                                              ? () => _handleBarcodeManualAdjust(item, -1)
                                              : null,
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primary.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: AppTheme.primaryLight),
                                          ),
                                          child: Text(
                                            '${item.line.countedQuantity}',
                                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.add, size: 16),
                                          onPressed: () => _handleBarcodeManualAdjust(item, 1),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Discrepancy / Variance
                                  Expanded(
                                    flex: 2,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        const Text('Écart', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                                        Text(
                                          diff > 0 ? '+$diff' : '$diff',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: diff == 0
                                                ? Colors.white54
                                                : diff > 0
                                                    ? AppTheme.success
                                                    : AppTheme.error,
                                          ),
                                        ),
                                      ],
                                    ),
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
              ),
      ),
    );
  }

  Future<void> _handleBarcodeManualAdjust(InventoryCountLineWithDetails item, int delta) async {
    if (_countId == null) return;
    final countService = ref.read(inventoryCountServiceProvider);
    await countService.recordScannedVariant(
      countId: _countId!,
      barcodeOrSku: item.variant.barcode,
      increment: delta,
    );
    _loadLines();
  }

  Widget _buildStatCard({required String title, required String value, required Color color, required IconData icon}) {
    return Container(
      width: 180,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              Icon(icon, size: 14, color: color),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
