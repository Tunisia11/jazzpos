import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/domain/services/catalog_service.dart';
import 'package:jazzpos/hardware/hardware_manager.dart';
import 'package:jazzpos/hardware/label_printer/label_document.dart';
import 'package:jazzpos/providers/catalog_provider.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';
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

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedVariant = widget.initialVariant;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _printLabels() async {
    if (_selectedVariant == null) return;

    setState(() {
      _isPrinting = true;
      _statusMessage = null;
    });

    final doc = LabelDocument(
      storeName: 'JAZZ FASHION',
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
        _statusMessage = '$_copies étiquette(s) envoyée(s) à l\'imprimante TSPL/ZPL';
      });
    } catch (e) {
      setState(() {
        _isPrinting = false;
        _statusMessage = 'Erreur d\'impression: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogState = ref.watch(catalogNotifierProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Studio d\'Étiquettes Code-Barres'),
        backgroundColor: AppTheme.surface,
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
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Format du rouleau d\'étiquettes (mm)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            _buildFormatChip(40, 25, '40 x 25 mm (Bijoux / Accessoires)'),
                            _buildFormatChip(40, 30, '40 x 30 mm (Standard Prêt-à-Porter)'),
                            _buildFormatChip(50, 30, '50 x 30 mm (Grand format)'),
                            _buildFormatChip(60, 40, '60 x 40 mm (Carton / Cartonnette)'),
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
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sélection de l\'article :',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: 'Rechercher un article ou scanner...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      ref.read(catalogNotifierProvider.notifier).search('');
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (val) => ref.read(catalogNotifierProvider.notifier).search(val),
                        ),
                        const SizedBox(height: 12),

                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 240),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: catalogState.variants.length,
                            separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1),
                            itemBuilder: (context, index) {
                              final v = catalogState.variants[index];
                              final isSelected = v.variantId == _selectedVariant?.variantId;

                              return ListTile(
                                dense: true,
                                selected: isSelected,
                                selectedTileColor: AppTheme.primary.withValues(alpha: 0.15),
                                title: Text(v.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('${v.variantDescription} • SKU: ${v.sku} • Stock: ${v.stock}'),
                                trailing: MoneyDisplay(amount: v.salePrice, fontSize: 13),
                                onTap: () => setState(() => _selectedVariant = v),
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
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Nombre d\'exemplaires :',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
                            if (_selectedVariant != null && _selectedVariant!.stock > 0)
                              OutlinedButton(
                                onPressed: () => setState(() => _copies = _selectedVariant!.stock),
                                child: Text('Selon Stock (${_selectedVariant!.stock})'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: _copies > 1 ? () => setState(() => _copies--) : null,
                            ),
                            Text('$_copies étiquette(s)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => setState(() => _copies++),
                            ),
                            const Spacer(),
                            ElevatedButton.icon(
                              onPressed: (_selectedVariant == null || _isPrinting) ? null : _printLabels,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                              ),
                              icon: _isPrinting
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.print, size: 20),
                              label: Text(_isPrinting ? 'IMPRESSION...' : 'LANCER L\'IMPRESSION'),
                            ),
                          ],
                        ),
                        if (_statusMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _statusMessage!,
                            style: TextStyle(
                              color: _statusMessage!.contains('Erreur') ? AppTheme.error : AppTheme.success,
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

          const VerticalDivider(color: AppTheme.border, width: 1),

          // Right: Live Visual WYSIWYG Label Preview
          Expanded(
            flex: 4,
            child: Container(
              color: const Color(0xFF0F172A),
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Aperçu Réel de l\'Étiquette Thermique',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 20),

                  if (_selectedVariant == null)
                    const Text('Veuillez sélectionner un article pour visualiser l\'étiquette', style: TextStyle(color: AppTheme.textSecondary))
                  else
                    _buildWysiwygLabel(),

                  const SizedBox(height: 20),
                  Text(
                    'Format sélectionné : $_widthMm x $_heightMm mm',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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
      onSelected: (_) => setState(() {
        _widthMm = w;
        _heightMm = h;
      }),
    );
  }

  Widget _buildCopiesButton(int count) {
    return ElevatedButton(
      onPressed: () => setState(() => _copies = count),
      style: ElevatedButton.styleFrom(
        backgroundColor: _copies == count ? AppTheme.primary : const Color(0xFF161F2E),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      child: Text('$count'),
    );
  }

  Widget _buildWysiwygLabel() {
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
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Store Name
          const Text(
            'JAZZ FASHION',
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
                'REF: ${v.sku}',
                style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w500),
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
