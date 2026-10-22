import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracepos/data/database/app_database.dart';
import 'package:tracepos/providers/app_providers.dart';
import 'package:tracepos/providers/auth_provider.dart';
import 'package:tracepos/ui/theme/app_design_tokens.dart';
import 'package:tracepos/ui/widgets/common/app_card.dart';

class CategoriesManagementTab extends ConsumerStatefulWidget {
  const CategoriesManagementTab({super.key});

  @override
  ConsumerState<CategoriesManagementTab> createState() => _CategoriesManagementTabState();
}

class _CategoriesManagementTabState extends ConsumerState<CategoriesManagementTab> {
  List<Category> _categories = [];
  Map<String, int> _productCounts = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseProvider);
      final cats = await (db.select(db.categories)
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

      final allProducts = await (db.select(db.products)
            ..where((t) => t.status.equals('ACTIVE')))
          .get();

      final counts = <String, int>{};
      for (final p in allProducts) {
        if (p.categoryId != null) {
          counts[p.categoryId!] = (counts[p.categoryId!] ?? 0) + 1;
        }
      }

      if (mounted) {
        setState(() {
          _categories = cats;
          _productCounts = counts;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur chargement catégories : $e'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showAddCategoryDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard)),
          title: Row(
            children: const [
              Icon(Icons.create_new_folder_outlined, color: AppDesignTokens.primary),
              SizedBox(width: 8),
              Text('Nouvelle Catégorie', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: 380,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Nom de la Catégorie *',
                      hintText: 'Ex: T-shirts, Chemises, Robes...',
                      prefixIcon: Icon(Icons.category_outlined, size: 20),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Le nom est obligatoire' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Code court (pour préfixe SKU)',
                      hintText: 'Ex: TSH, CHE, ROB...',
                      prefixIcon: Icon(Icons.tag, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDlgState(() => isSaving = true);
                      try {
                        final auth = ref.read(authNotifierProvider);
                        final catalogService = ref.read(catalogServiceProvider);
                        await catalogService.createCategory(
                          name: nameCtrl.text.trim(),
                          code: codeCtrl.text.trim().isEmpty ? null : codeCtrl.text.trim().toUpperCase(),
                          actorId: auth.user?.id ?? 'ADMIN',
                        );
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Catégorie "${nameCtrl.text.trim()}" créée avec succès.'),
                              backgroundColor: AppDesignTokens.success,
                            ),
                          );
                          _loadCategories();
                        }
                      } catch (e) {
                        setDlgState(() => isSaving = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Erreur: $e'), backgroundColor: AppDesignTokens.danger),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppDesignTokens.primary, foregroundColor: Colors.white),
              child: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Créer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditCategoryDialog(Category cat) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: cat.name);
    final codeCtrl = TextEditingController(text: cat.code ?? '');
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard)),
          title: Text('Modifier la Catégorie "${cat.name}"', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 380,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nom de la Catégorie',
                      prefixIcon: Icon(Icons.category_outlined, size: 20),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Le nom est obligatoire' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Code court (préfixe SKU)',
                      prefixIcon: Icon(Icons.tag, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDlgState(() => isSaving = true);
                      try {
                        final auth = ref.read(authNotifierProvider);
                        final catalogService = ref.read(catalogServiceProvider);
                        await catalogService.updateCategory(
                          id: cat.id,
                          name: nameCtrl.text.trim(),
                          code: codeCtrl.text.trim().isEmpty ? null : codeCtrl.text.trim().toUpperCase(),
                          actorId: auth.user?.id ?? 'ADMIN',
                        );
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Catégorie mise à jour avec succès.'),
                              backgroundColor: AppDesignTokens.success,
                            ),
                          );
                          _loadCategories();
                        }
                      } catch (e) {
                        setDlgState(() => isSaving = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Erreur: $e'), backgroundColor: AppDesignTokens.danger),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppDesignTokens.primary, foregroundColor: Colors.white),
              child: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteCategoryDialog(Category cat) async {
    final count = _productCounts[cat.id] ?? 0;
    final otherCategories = _categories.where((c) => c.id != cat.id).toList();
    String? selectedReassignId; // null = unassign
    bool isDeleting = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard)),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: AppDesignTokens.danger),
              SizedBox(width: 8),
              Text('Supprimer la Catégorie', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Êtes-vous sûr de vouloir supprimer la catégorie "${cat.name}" ?',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                if (count > 0) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppDesignTokens.warningBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppDesignTokens.warning.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline, size: 18, color: AppDesignTokens.warningText),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Cette catégorie contient $count article(s) actif(s).',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppDesignTokens.warningText),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Les articles ne seront pas supprimés. Choisissez ce que vous souhaitez faire de leurs références de catégorie :',
                          style: TextStyle(fontSize: 11, color: AppDesignTokens.warningText),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String?>(
                    initialValue: selectedReassignId,
                    decoration: const InputDecoration(
                      labelText: 'Action sur les articles existants',
                      prefixIcon: Icon(Icons.swap_horiz, size: 20),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Détacher les articles (Sans catégorie)'),
                      ),
                      ...otherCategories.map(
                        (c) => DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text('Réassigner vers : ${c.name}'),
                        ),
                      ),
                    ],
                    onChanged: (v) => setDlgState(() => selectedReassignId = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: isDeleting
                  ? null
                  : () async {
                      setDlgState(() => isDeleting = true);
                      try {
                        final auth = ref.read(authNotifierProvider);
                        final catalogService = ref.read(catalogServiceProvider);
                        await catalogService.deleteCategory(
                          id: cat.id,
                          reassignToCategoryId: selectedReassignId,
                          actorId: auth.user?.id ?? 'ADMIN',
                        );
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Catégorie "${cat.name}" supprimée en toute sécurité.'),
                              backgroundColor: AppDesignTokens.success,
                            ),
                          );
                          _loadCategories();
                        }
                      } catch (e) {
                        setDlgState(() => isDeleting = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Erreur suppression : $e'), backgroundColor: AppDesignTokens.danger),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppDesignTokens.danger, foregroundColor: Colors.white),
              child: isDeleting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Supprimer'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDesignTokens.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Gestion des Catégories de Produits',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppDesignTokens.textPrimary),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Créez, renommez et organisez les catégories pour le catalogue et les filtres de caisse',
                    style: TextStyle(fontSize: 12, color: AppDesignTokens.textSecondary),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _showAddCategoryDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nouvelle Catégorie'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppDesignTokens.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignTokens.space16),

          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
          else if (_categories.isEmpty)
            AppCard(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      const Icon(Icons.category_outlined, size: 48, color: AppDesignTokens.textSecondary),
                      const SizedBox(height: 12),
                      const Text('Aucune catégorie pour le moment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 6),
                      const Text('Ajoutez des catégories pour classer vos articles (T-shirts, Robes, Pantalons...)', style: TextStyle(color: AppDesignTokens.textSecondary, fontSize: 13)),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _showAddCategoryDialog, child: const Text('Créer la première catégorie')),
                    ],
                  ),
                ),
              ),
            )
          else
            AppCard(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _categories.length,
                separatorBuilder: (context, index) => const Divider(color: AppDesignTokens.border),
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final productCount = _productCounts[cat.id] ?? 0;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppDesignTokens.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.category_outlined, color: AppDesignTokens.primary, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    cat.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppDesignTokens.textPrimary),
                                  ),
                                  if (cat.code != null && cat.code!.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppDesignTokens.surfaceElevated,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: AppDesignTokens.border),
                                      ),
                                      child: Text(
                                        cat.code!,
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppDesignTokens.textSecondary),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '$productCount article(s) lié(s)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: productCount > 0 ? AppDesignTokens.textSecondary : AppDesignTokens.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: 'Renommer / Modifier',
                              onPressed: () => _showEditCategoryDialog(cat),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: AppDesignTokens.danger),
                              tooltip: 'Supprimer',
                              onPressed: () => _showDeleteCategoryDialog(cat),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
