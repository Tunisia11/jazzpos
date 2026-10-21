import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/hardware/hardware_manager.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/providers/cart_provider.dart';
import 'package:jazzpos/providers/shift_provider.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';
import 'package:jazzpos/ui/widgets/barcode_scanner_listener.dart';
import 'widgets/cart_view.dart';
import 'widgets/payment_dialog.dart';
import 'widgets/product_catalog_grid.dart';
import 'widgets/suspended_sales_dialog.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  final String storeId;
  final String registerId;
  final VoidCallback? onOpenMenu;

  const CheckoutScreen({
    super.key,
    this.storeId = 'STORE-01',
    this.registerId = 'REG-01',
    this.onOpenMenu,
  });

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  int _suspendedCount = 0;
  String _effectiveRegisterId = 'REG-01';
  String _effectiveRegisterCode = 'REG-01';
  String _effectiveStoreId = 'STORE-01';

  @override
  void initState() {
    super.initState();
    _effectiveRegisterId = widget.registerId;
    _effectiveRegisterCode = widget.registerId;
    _effectiveStoreId = widget.storeId;
    HardwareKeyboard.instance.addHandler(_handleRawKeyEvent);
    _loadShiftAndSuspended();
    ref.read(printJobServiceProvider).reconcileAbandonedJobs().catchError((_) => 0);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleRawKeyEvent);
    super.dispose();
  }

  Future<void> _loadShiftAndSuspended() async {
    final db = ref.read(databaseProvider);
    final allRegisters = await db.select(db.registers).get();
    final reg = allRegisters.cast<Register?>().firstWhere(
      (r) => r?.id == widget.registerId || r?.code == widget.registerId,
      orElse: () => allRegisters.isNotEmpty ? allRegisters.first : null,
    );
    if (reg != null) {
      _effectiveRegisterId = reg.id;
      _effectiveRegisterCode = reg.code;
      _effectiveStoreId = reg.storeId;
      if (mounted) setState(() {});
    }

    await ref
        .read(shiftNotifierProvider.notifier)
        .checkActiveShift(_effectiveRegisterId);
    await _refreshSuspendedCount();
  }

  Future<void> _refreshSuspendedCount() async {
    final saleService = ref.read(saleServiceProvider);
    final carts = await saleService.getSuspendedCarts(_effectiveRegisterId);
    if (mounted) {
      setState(() => _suspendedCount = carts.length);
    }
  }

  bool _handleRawKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    // Check if a modal is already open
    if (ModalRoute.of(context)?.isCurrent != true) return false;

    if (event.logicalKey == LogicalKeyboardKey.f6) {
      _showSuspendedSales();
      return true;
    } else if (event.logicalKey == LogicalKeyboardKey.f10) {
      _kickDrawer();
      return true;
    } else if (event.logicalKey == LogicalKeyboardKey.f12) {
      _triggerCheckout();
      return true;
    }
    return false;
  }

  void _triggerCheckout() {
    final cart = ref.read(cartNotifierProvider);
    final shift = ref.read(shiftNotifierProvider).activeShift;
    if (shift == null) {
      _openShiftPrompt();
      return;
    }
    if (cart.items.isNotEmpty) {
      PaymentDialog.show(
        context,
        totalAmount: cart.total,
        storeId: _effectiveStoreId,
        registerId: _effectiveRegisterId,
      );
    }
  }

  Future<void> _kickDrawer() async {
    try {
      await HardwareManager.instance.cashDrawer.openDrawer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.loc.drawerKickSuccess),
            duration: const Duration(seconds: 1),
            backgroundColor: AppTheme.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.loc.error}: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _showSuspendedSales() async {
    await SuspendedSalesDialog.show(context, registerId: widget.registerId);
    _refreshSuspendedCount();
  }

  Future<void> _onBarcodeScanned(String barcode) async {
    // Priority 2: Disable scanner when any dialog or modal is open
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) {
      return;
    }

    final cartState = ref.read(cartNotifierProvider);
    if (cartState.isLocked || cartState.isProcessing) {
      return;
    }

    final success = await ref
        .read(cartNotifierProvider.notifier)
        .addItemByBarcode(barcode);
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.loc.barcodeScannedSuccess} : $barcode'),
            duration: const Duration(milliseconds: 900),
            backgroundColor: AppTheme.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Produit non trouvé : $barcode'),
            duration: const Duration(seconds: 2),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _openShiftPrompt() {
    final controller = TextEditingController(text: '150.000');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppDesignTokens.surface,
        title: Text(
          context.loc.openRegisterTitle,
          style: const TextStyle(
            color: AppDesignTokens.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${context.loc.initialCashFloat} :',
              style: const TextStyle(color: AppDesignTokens.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
              style: const TextStyle(color: AppDesignTokens.textPrimary),
              decoration: InputDecoration(
                prefixIcon: const Icon(
                  Icons.account_balance_wallet,
                  color: AppDesignTokens.primary,
                ),
                suffixText: context.loc.currencySymbol,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.loc.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final val = double.tryParse(controller.text) ?? 0.0;
              final auth = ref.read(authNotifierProvider);
              try {
                await ref
                    .read(shiftNotifierProvider.notifier)
                    .openShift(
                      registerId: _effectiveRegisterId,
                      cashierId: auth.user?.id ?? 'system',
                      openingCash: Money.fromTnd(val),
                    );
                if (ctx.mounted) Navigator.of(ctx).pop();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('Erreur lors de l\'ouverture de caisse: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppDesignTokens.success,
              foregroundColor: Colors.white,
            ),
            child: Text(context.loc.openRegisterAction),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);
    final shiftState = ref.watch(shiftNotifierProvider);
    final shift = shiftState.activeShift;

    return BarcodeScannerListener(
      onBarcodeScanned: _onBarcodeScanned,
      child: Scaffold(
        backgroundColor: AppDesignTokens.background,
        body: SafeArea(
          child: Column(
            children: [
              // Top Navigation Bar
              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  color: AppDesignTokens.surface,
                  border: Border(bottom: BorderSide(color: AppDesignTokens.border)),
                ),
                child: Row(
                  children: [
                    // Logo + brand
                    Image.asset('assets/images/trace_logo_mark.png', width: 28, height: 28),
                    const SizedBox(width: 8),
                    const Text(
                      'Trace POS',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Menu toggle
                    if (widget.onOpenMenu != null)
                      IconButton(
                        icon: const Icon(Icons.menu, color: AppDesignTokens.textSecondary, size: 20),
                        onPressed: widget.onOpenMenu,
                        tooltip: 'Menu',
                      ),
                    // Register label
                    const Icon(Icons.desktop_windows_outlined, color: AppDesignTokens.primary, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'Caisse: $_effectiveRegisterCode',
                      style: const TextStyle(
                        color: AppDesignTokens.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const Spacer(),

                    Flexible(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Shift Status Pill
                            InkWell(
                              onTap: shift == null ? _openShiftPrompt : null,
                              borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: shift != null ? AppDesignTokens.successBg : AppDesignTokens.warningBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: shift != null
                                ? AppDesignTokens.success.withValues(alpha: 0.4)
                                : AppDesignTokens.warning.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.circle,
                              size: 9,
                              color: shift != null ? AppDesignTokens.success : AppDesignTokens.warning,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              shift != null
                                  ? '${context.loc.registerOpen} (${DateFormat('HH:mm').format(shift.openedAt)})'
                                  : context.loc.clickToOpenRegister,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: shift != null ? AppDesignTokens.successText : AppDesignTokens.warningText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Notification bell (suspended sales badge)
                    Stack(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.notifications_none_outlined, color: AppDesignTokens.textSecondary, size: 22),
                          onPressed: _showSuspendedSales,
                          tooltip: context.loc.suspendedSales,
                        ),
                        if (_suspendedCount > 0)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: const BoxDecoration(
                                color: AppDesignTokens.danger,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$_suspendedCount',
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),

                    // Cash drawer button
                    IconButton(
                      icon: const Icon(Icons.point_of_sale, color: AppDesignTokens.textSecondary, size: 22),
                      onPressed: _kickDrawer,
                      tooltip: context.loc.openCashDrawer,
                    ),

                    const SizedBox(width: 4),
                    Container(width: 1, height: 30, color: AppDesignTokens.border),
                    const SizedBox(width: 12),

                    // User pill with dropdown look
                    InkWell(
                      onTap: () => ref.read(authNotifierProvider.notifier).lock(),
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppDesignTokens.surfaceElevated,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppDesignTokens.border),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: const Color(0xFFDBEAFE),
                              child: Text(
                                auth.user?.displayName.isNotEmpty == true
                                    ? auth.user!.displayName.substring(0, 1).toUpperCase()
                                    : 'U',
                                style: const TextStyle(
                                  color: AppDesignTokens.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  auth.user?.displayName ?? 'Utilisateur',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppDesignTokens.textPrimary,
                                  ),
                                ),
                                Text(
                                  auth.user?.role.toUpperCase() ?? 'OWNER',
                                  style: const TextStyle(fontSize: 10, color: AppDesignTokens.textSecondary),
                                ),
                              ],
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.keyboard_arrow_down, color: AppDesignTokens.textSecondary, size: 18),
                          ],
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

              // Main Workspace Split: 65% Catalog Grid, 35% Cart Panel
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppDesignTokens.space12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Catalog & Grid (65%)
                      const Expanded(flex: 13, child: ProductCatalogGrid()),

                      const SizedBox(width: AppDesignTokens.space12),

                      // Cart Panel (35%)
                      Expanded(
                        flex: 7,
                        child: CartView(
                          storeId: _effectiveStoreId,
                          registerId: _effectiveRegisterId,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
