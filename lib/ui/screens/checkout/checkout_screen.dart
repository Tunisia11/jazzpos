import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/core/money/money.dart';
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

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleRawKeyEvent);
    _loadShiftAndSuspended();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleRawKeyEvent);
    super.dispose();
  }

  Future<void> _loadShiftAndSuspended() async {
    await ref
        .read(shiftNotifierProvider.notifier)
        .checkActiveShift(widget.registerId);
    await _refreshSuspendedCount();
  }

  Future<void> _refreshSuspendedCount() async {
    final saleService = ref.read(saleServiceProvider);
    final carts = await saleService.getSuspendedCarts(widget.registerId);
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
    if (cart.items.isNotEmpty && shift != null) {
      PaymentDialog.show(
        context,
        totalAmount: cart.total,
        storeId: widget.storeId,
        registerId: widget.registerId,
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
            content: Text('${context.loc.barcodeNotFound} : $barcode'),
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
              await ref
                  .read(shiftNotifierProvider.notifier)
                  .openShift(
                    registerId: widget.registerId,
                    cashierId: auth.user?.id ?? 'system',
                    openingCash: Money.fromTnd(val),
                  );
              if (ctx.mounted) Navigator.of(ctx).pop();
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
                  border: Border(
                    bottom: BorderSide(color: AppDesignTokens.border),
                  ),
                ),
                child: Row(
                  children: [
                    // Brand / Menu button
                    if (widget.onOpenMenu != null)
                      IconButton(
                        icon: const Icon(
                          Icons.menu,
                          color: AppDesignTokens.textPrimary,
                        ),
                        onPressed: widget.onOpenMenu,
                        tooltip: 'Menu Principal',
                      ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppDesignTokens.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        context.loc.appTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${context.loc.register}: ${widget.registerId}',
                      style: const TextStyle(
                        color: AppDesignTokens.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const Spacer(),

                    // Shift Status Indicator
                    InkWell(
                      onTap: shift == null ? _openShiftPrompt : null,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: shift != null
                              ? AppDesignTokens.successBg
                              : AppDesignTokens.warningBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: shift != null
                                ? AppDesignTokens.success.withValues(alpha: 0.4)
                                : AppDesignTokens.warning.withValues(
                                    alpha: 0.4,
                                  ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.circle,
                              size: 9,
                              color: shift != null
                                  ? AppDesignTokens.success
                                  : AppDesignTokens.warning,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              shift != null
                                  ? '${context.loc.registerOpen} (${DateFormat('HH:mm').format(shift.openedAt)})'
                                  : context.loc.clickToOpenRegister,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: shift != null
                                    ? AppDesignTokens.successText
                                    : AppDesignTokens.warningText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Quick Actions
                    // Suspended Sales
                    Stack(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.pause_circle_outline,
                            color: AppDesignTokens.warning,
                          ),
                          onPressed: _showSuspendedSales,
                          tooltip: context.loc.suspendedSales,
                        ),
                        if (_suspendedCount > 0)
                          Positioned(
                            right: 4,
                            top: 4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: AppDesignTokens.warning,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              child: Text(
                                '$_suspendedCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),

                    // Drawer Kick
                    IconButton(
                      icon: const Icon(
                        Icons.point_of_sale,
                        color: AppDesignTokens.textSecondary,
                      ),
                      onPressed: _kickDrawer,
                      tooltip: context.loc.openCashDrawer,
                    ),

                    const SizedBox(width: 8),
                    const VerticalDivider(
                      color: AppDesignTokens.border,
                      indent: 14,
                      endIndent: 14,
                    ),
                    const SizedBox(width: 8),

                    // Cashier User & Lock
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 15,
                          backgroundColor: const Color(0xFFDBEAFE),
                          child: Text(
                            auth.user?.displayName.isNotEmpty == true
                                ? auth.user!.displayName
                                      .substring(0, 1)
                                      .toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              color: AppDesignTokens.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
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
                              auth.user?.role.toUpperCase() ?? 'CAISSIER',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppDesignTokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(
                            Icons.lock_outline,
                            color: AppDesignTokens.textSecondary,
                            size: 19,
                          ),
                          onPressed: () =>
                              ref.read(authNotifierProvider.notifier).lock(),
                          tooltip: context.loc.lockRegister,
                        ),
                      ],
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
                          storeId: widget.storeId,
                          registerId: widget.registerId,
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
