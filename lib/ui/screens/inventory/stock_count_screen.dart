import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/constants/permissions.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/domain/services/inventory_count_service.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'package:jazzpos/ui/widgets/barcode_scanner_listener.dart';
import 'package:jazzpos/ui/widgets/common/app_button.dart';
import 'package:jazzpos/ui/widgets/manager_override_dialog.dart';

class StockCountScreen extends ConsumerStatefulWidget {
  final String locationId;

  const StockCountScreen({super.key, this.locationId = 'LOC-SHOP'});

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
          SnackBar(
            content: Text('${context.loc.error}: $e'),
            backgroundColor: AppDesignTokens.danger,
          ),
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
            content: Text('+1 : $clean'),
            duration: const Duration(milliseconds: 700),
            backgroundColor: AppDesignTokens.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.loc.error}: $e'),
            duration: const Duration(seconds: 2),
            backgroundColor: AppDesignTokens.danger,
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
      final loc = context.loc;
      final manager = await ManagerOverrideDialog.show(
        context,
        actionTitle: loc.validateAndApplyAudit,
        requiredPermission: AppPermissions.manageInventory,
      );
      if (manager == null) return;
      managerId = manager.id;
    }

    try {
      final countService = ref.read(inventoryCountServiceProvider);
      await countService.reconcileAndComplete(
        countId: _countId!,
        managerId: managerId!,
      );

      if (mounted) {
        final loc = context.loc;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.countCompletedSuccess),
            backgroundColor: AppDesignTokens.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.loc.error}: $e'),
            backgroundColor: AppDesignTokens.danger,
          ),
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
        varianceCostMillimes +=
            l.line.differenceQuantity * l.line.unitCostMillimes;
      }
    }

    final loc = context.loc;
    return BarcodeScannerListener(
      onBarcodeScanned: _handleBarcode,
      child: Scaffold(
        backgroundColor: AppDesignTokens.canvas,
        appBar: AppBar(
          title: Text(
            loc.stockCountTitle,
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
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 16),
              child: AppButton(
                label: loc.validateAndApplyAudit,
                icon: Icons.check_circle_outline,
                variant: AppButtonVariant.success,
                isLoading: _isLoading,
                onPressed: _isLoading ? null : _reconcileAndFinish,
              ),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppDesignTokens.primary,
                ),
              )
            : Padding(
                padding: const EdgeInsetsDirectional.all(20),
                child: Column(
                  children: [
                    // Top Bar: Barcode Input + Stats Cards
                    Row(
                      children: [
                        // Rapid Barcode Input Field
                        Expanded(
                          flex: 5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppDesignTokens.surface,
                              borderRadius: BorderRadius.circular(
                                AppDesignTokens.radiusCard,
                              ),
                              border: Border.all(color: AppDesignTokens.border),
                              boxShadow: AppDesignTokens.shadowSm,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.qr_code_scanner,
                                  color: AppDesignTokens.primary,
                                  size: 26,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: _barcodeInputCtrl,
                                    focusNode: _barcodeFocus,
                                    autofocus: true,
                                    style: const TextStyle(
                                      color: AppDesignTokens.textPrimary,
                                      fontSize: 14,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: loc.scanOrTypeBarcode,
                                      hintStyle: const TextStyle(
                                        color: AppDesignTokens.textMuted,
                                      ),
                                      border: InputBorder.none,
                                    ),
                                    onSubmitted: _handleBarcode,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.send,
                                    color: AppDesignTokens.primary,
                                  ),
                                  onPressed: () =>
                                      _handleBarcode(_barcodeInputCtrl.text),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(width: 16),

                        // Stats Card 1: Total Scanned
                        _buildStatCard(
                          title: loc.totalPiecesCounted,
                          value: '$totalCounted',
                          color: AppDesignTokens.primary,
                          bgColor: AppDesignTokens.primaryLight.withValues(
                            alpha: 0.1,
                          ),
                          icon: Icons.checkroom,
                        ),

                        const SizedBox(width: 12),

                        // Stats Card 2: Discrepancies
                        _buildStatCard(
                          title: loc.itemsWithVariance,
                          value: '$totalDiscrepancies',
                          color: totalDiscrepancies > 0
                              ? AppDesignTokens.warningText
                              : AppDesignTokens.successText,
                          bgColor: totalDiscrepancies > 0
                              ? AppDesignTokens.warningBg
                              : AppDesignTokens.successBg,
                          icon: Icons.difference,
                        ),

                        const SizedBox(width: 12),

                        // Stats Card 3: Value Variance
                        _buildStatCard(
                          title: loc.varianceValue,
                          value: Money.fromMillimes(
                            varianceCostMillimes,
                          ).format(),
                          color: varianceCostMillimes < 0
                              ? AppDesignTokens.dangerText
                              : AppDesignTokens.successText,
                          bgColor: varianceCostMillimes < 0
                              ? AppDesignTokens.dangerBg
                              : AppDesignTokens.successBg,
                          icon: Icons.attach_money,
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Inventory Lines Table
                    Expanded(
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
                            itemCount: _lines.length,
                            separatorBuilder: (_, __) => const Divider(
                              color: AppDesignTokens.border,
                              height: 1,
                              thickness: 1,
                            ),
                            itemBuilder: (context, index) {
                              final item = _lines[index];
                              final diff = item.line.differenceQuantity;
                              final isDifferent = diff != 0;

                              return Container(
                                color: isDifferent
                                    ? AppDesignTokens.warningBg.withValues(
                                        alpha: 0.35,
                                      )
                                    : Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    // Product & Variant
                                    Expanded(
                                      flex: 4,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.product.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                              color:
                                                  AppDesignTokens.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${item.attributeDesc} • ${loc.barcode}: ${item.variant.barcode}',
                                            style: const TextStyle(
                                              color:
                                                  AppDesignTokens.textSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Expected Stock
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            loc.expectedQty,
                                            style: const TextStyle(
                                              color: AppDesignTokens.textMuted,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${item.line.expectedQuantity}',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color:
                                                  AppDesignTokens.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Counted Stock with Quick Adjusters
                                    Expanded(
                                      flex: 3,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                              Icons.remove_circle_outline,
                                              size: 20,
                                              color:
                                                  AppDesignTokens.textSecondary,
                                            ),
                                            onPressed:
                                                item.line.countedQuantity > 0
                                                ? () =>
                                                      _handleBarcodeManualAdjust(
                                                        item,
                                                        -1,
                                                      )
                                                : null,
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppDesignTokens
                                                  .primaryLight
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: AppDesignTokens
                                                    .primaryLight
                                                    .withValues(alpha: 0.4),
                                              ),
                                            ),
                                            child: Text(
                                              '${item.line.countedQuantity}',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: AppDesignTokens.primary,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.add_circle_outline,
                                              size: 20,
                                              color: AppDesignTokens.primary,
                                            ),
                                            onPressed: () =>
                                                _handleBarcodeManualAdjust(
                                                  item,
                                                  1,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Discrepancy / Variance
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            loc.varianceQty,
                                            style: const TextStyle(
                                              color: AppDesignTokens.textMuted,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: diff == 0
                                                  ? Colors.transparent
                                                  : (diff > 0
                                                        ? AppDesignTokens
                                                              .successBg
                                                        : AppDesignTokens
                                                              .dangerBg),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              diff > 0 ? '+$diff' : '$diff',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: diff == 0
                                                    ? AppDesignTokens
                                                          .textSecondary
                                                    : (diff > 0
                                                          ? AppDesignTokens
                                                                .successText
                                                          : AppDesignTokens
                                                                .dangerText),
                                              ),
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
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _handleBarcodeManualAdjust(
    InventoryCountLineWithDetails item,
    int delta,
  ) async {
    if (_countId == null) return;
    final countService = ref.read(inventoryCountServiceProvider);
    await countService.recordScannedVariant(
      countId: _countId!,
      barcodeOrSku: item.variant.barcode,
      increment: delta,
    );
    _loadLines();
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required Color color,
    required Color bgColor,
    required IconData icon,
  }) {
    return Container(
      width: 180,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppDesignTokens.surface,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        border: Border.all(color: AppDesignTokens.border),
        boxShadow: AppDesignTokens.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppDesignTokens.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
