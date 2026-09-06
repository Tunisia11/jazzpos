import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/localization/app_localizations.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/domain/services/catalog_service.dart';
import 'package:jazzpos/hardware/hardware_manager.dart';
import 'package:jazzpos/hardware/label_printer/label_document.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/providers/catalog_provider.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'package:jazzpos/ui/widgets/money_display.dart';

class LabelStudioScreen extends ConsumerStatefulWidget {
  final VariantSearchResult? initialVariant;

  const LabelStudioScreen({super.key, this.initialVariant});

  @override
  ConsumerState<LabelStudioScreen> createState() => _LabelStudioScreenState();
}

class _LabelStudioScreenState extends ConsumerState<LabelStudioScreen> {
  VariantSearchResult? _selectedVariant;
  int _widthMm = 40;
  int _heightMm = 30;
  int _copies = 1;
  bool _isPrinting = false;
  String? _statusMessage;
  String _storeName = 'JAZZ POS';

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedVariant = widget.initialVariant;
    _loadStoreName();
  }

  Future<void> _loadStoreName() async {
    final db = ref.read(databaseProvider);
    final company = await (db.select(db.companies)..limit(1)).getSingleOrNull();
    if (mounted && company != null && company.name.trim().isNotEmpty) {
      setState(() => _storeName = company.name.trim());
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _printLabels() async {
    if (_selectedVariant == null) return;

    final loc = context.loc;
    setState(() {
      _isPrinting = true;
      _statusMessage = null;
    });

    final doc = LabelDocument(
      storeName: _storeName,
      productName: _selectedVariant!.productName,
      size: _selectedVariant!.variantDescription,
      sku: _selectedVariant!.sku,
      barcode: _selectedVariant!.barcode,
      price: _selectedVariant!.salePrice,
      widthMm: _widthMm,
      heightMm: _heightMm,
      copies: _copies,
    );

    try {
      await HardwareManager.instance.labelPrinter.printLabel(doc);
      setState(() {
        _isPrinting = false;
        _statusMessage = loc.labelsSentToPrinter(_copies);
      });
    } catch (e) {
      setState(() {
        _isPrinting = false;
        _statusMessage = loc.printError('$e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final catalogState = ref.watch(catalogNotifierProvider);

    return Scaffold(
      backgroundColor: AppDesignTokens.canvas,
      appBar: AppBar(
        title: Text(
          loc.labelStudioTitle,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        backgroundColor: AppDesignTokens.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppDesignTokens.textPrimary),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppDesignTokens.border),
        ),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Controls & Variant Selector
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Label format selection
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppDesignTokens.surface,
                      borderRadius: BorderRadius.circular(
                        AppDesignTokens.radiusCard,
                      ),
                      border: Border.all(color: AppDesignTokens.border),
                      boxShadow: AppDesignTokens.shadowSm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc.labelRollFormat,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            _buildFormatChip(
                              40,
                              25,
                              loc.formatJewelryAccessories,
                            ),
                            _buildFormatChip(40, 30, loc.formatStandardApparel),
                            _buildFormatChip(50, 30, loc.formatLarge),
                            _buildFormatChip(60, 40, loc.formatCardboardTag),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Article Selection
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppDesignTokens.surface,
                      borderRadius: BorderRadius.circular(
                        AppDesignTokens.radiusCard,
                      ),
                      border: Border.all(color: AppDesignTokens.border),
                      boxShadow: AppDesignTokens.shadowSm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc.selectProductForLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: loc.searchProductOrBarcode,
                            prefixIcon: const Icon(
                              Icons.search,
                              color: AppDesignTokens.textSecondary,
                            ),
                            suffixIcon: _searchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear,
                                      size: 16,
                                      color: AppDesignTokens.textSecondary,
                                    ),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      ref
                                          .read(
                                            catalogNotifierProvider.notifier,
                                          )
                                          .search('');
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (val) => ref
                              .read(catalogNotifierProvider.notifier)
                              .search(val),
                        ),
                        const SizedBox(height: 12),

                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 240),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: catalogState.variants.length,
                            separatorBuilder: (_, __) => const Divider(
                              color: AppDesignTokens.border,
                              height: 1,
                            ),
                            itemBuilder: (context, index) {
                              final v = catalogState.variants[index];
                              final isSelected =
                                  v.variantId == _selectedVariant?.variantId;

                              return ListTile(
                                dense: true,
                                selected: isSelected,
                                selectedTileColor: AppDesignTokens.primary
                                    .withValues(alpha: 0.08),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppDesignTokens.radiusInput,
                                  ),
                                ),
                                title: Text(
                                  v.productName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppDesignTokens.textPrimary,
                                  ),
                                ),
                                subtitle: Text(
                                  '${v.variantDescription} • ${loc.sku}: ${v.sku} • ${loc.stock}: ${v.stock}',
                                  style: const TextStyle(
                                    color: AppDesignTokens.textSecondary,
                                  ),
                                ),
                                trailing: MoneyDisplay(
                                  amount: v.salePrice,
                                  fontSize: 13,
                                ),
                                onTap: () =>
                                    setState(() => _selectedVariant = v),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Quantity & Print Button
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppDesignTokens.surface,
                      borderRadius: BorderRadius.circular(
                        AppDesignTokens.radiusCard,
                      ),
                      border: Border.all(color: AppDesignTokens.border),
                      boxShadow: AppDesignTokens.shadowSm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc.printCopies,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _buildCopiesButton(1),
                            const SizedBox(width: 8),
                            _buildCopiesButton(5),
                            const SizedBox(width: 8),
                            _buildCopiesButton(10),
                            const SizedBox(width: 8),
                            _buildCopiesButton(20),
                            const SizedBox(width: 12),
                            if (_selectedVariant != null &&
                                _selectedVariant!.stock > 0)
                              OutlinedButton(
                                onPressed: () => setState(
                                  () => _copies = _selectedVariant!.stock,
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: AppDesignTokens.border,
                                  ),
                                  foregroundColor: AppDesignTokens.textPrimary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppDesignTokens.radiusInput,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  '${loc.byStockCount} (${_selectedVariant!.stock})',
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: AppDesignTokens.textSecondary,
                              ),
                              onPressed: _copies > 1
                                  ? () => setState(() => _copies--)
                                  : null,
                            ),
                            Text(
                              loc.nLabels(_copies),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppDesignTokens.textPrimary,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.add_circle_outline,
                                color: AppDesignTokens.textSecondary,
                              ),
                              onPressed: () => setState(() => _copies++),
                            ),
                            const Spacer(),
                            ElevatedButton.icon(
                              onPressed:
                                  (_selectedVariant == null || _isPrinting)
                                  ? null
                                  : _printLabels,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppDesignTokens.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppDesignTokens.radiusInput,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 14,
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
                                  : const Icon(Icons.print, size: 20),
                              label: Text(
                                _isPrinting
                                    ? loc.processing.toUpperCase()
                                    : loc.printLabelsAction.toUpperCase(),
                              ),
                            ),
                          ],
                        ),
                        if (_statusMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _statusMessage!,
                            style: TextStyle(
                              color:
                                  _statusMessage!.contains('Erreur') ||
                                      _statusMessage!.contains('Error') ||
                                      _statusMessage!.contains('خطأ')
                                  ? AppDesignTokens.danger
                                  : AppDesignTokens.success,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const VerticalDivider(color: AppDesignTokens.border, width: 1),

          // Right: Live Visual WYSIWYG Label Preview
          Expanded(
            flex: 4,
            child: Container(
              color: AppDesignTokens.canvas,
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    loc.realThermalLabelPreview,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (_selectedVariant == null)
                    Text(
                      loc.selectArticleToPreview,
                      style: const TextStyle(
                        color: AppDesignTokens.textSecondary,
                      ),
                    )
                  else
                    _buildWysiwygLabel(loc),

                  const SizedBox(height: 20),
                  Text(
                    loc.selectedFormat(_widthMm, _heightMm),
                    style: const TextStyle(
                      color: AppDesignTokens.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatChip(int w, int h, String label) {
    final isSelected = _widthMm == w && _heightMm == h;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: AppDesignTokens.primary.withValues(alpha: 0.12),
      side: BorderSide(
        color: isSelected ? AppDesignTokens.primary : AppDesignTokens.border,
      ),
      labelStyle: TextStyle(
        color: isSelected
            ? AppDesignTokens.primary
            : AppDesignTokens.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      onSelected: (_) => setState(() {
        _widthMm = w;
        _heightMm = h;
      }),
    );
  }

  Widget _buildCopiesButton(int count) {
    final isSelected = _copies == count;
    return ElevatedButton(
      onPressed: () => setState(() => _copies = count),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
            ? AppDesignTokens.primary
            : AppDesignTokens.surface,
        foregroundColor: isSelected
            ? Colors.white
            : AppDesignTokens.textPrimary,
        elevation: 0,
        side: BorderSide(
          color: isSelected ? AppDesignTokens.primary : AppDesignTokens.border,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      child: Text('$count'),
    );
  }

  Widget _buildWysiwygLabel(AppLocalizations loc) {
    final v = _selectedVariant!;
    // Scale mm to pixels for preview (e.g. 1mm = 7 pixels)
    final previewWidth = _widthMm * 7.5;
    final previewHeight = _heightMm * 7.5;

    return Container(
      width: previewWidth,
      height: previewHeight,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppDesignTokens.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Store Name
          Text(
            _storeName,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),

          // Product Name
          Text(
            v.productName,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),

          // Variant Description (Taille / Couleur)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              v.variantDescription,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),

          const Spacer(),

          // Barcode rendered with barcode_widget
          SizedBox(
            height: previewHeight * 0.32,
            child: BarcodeWidget(
              barcode: Barcode.code128(),
              data: v.barcode.isNotEmpty ? v.barcode : v.sku,
              color: Colors.black,
              drawText: true,
              style: const TextStyle(fontSize: 9, color: Colors.black),
            ),
          ),

          const Spacer(),

          // Price row in TND
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${loc.reference}: ${v.sku}',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                v.salePrice.format(),
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
