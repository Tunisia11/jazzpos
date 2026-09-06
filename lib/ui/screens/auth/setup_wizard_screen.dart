import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/constants/roles.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';

class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen> {
  int _currentStep = 0;
  bool _isSaving = false;

  // Form controllers - Store & Company
  final _companyNameCtrl = TextEditingController();
  final _fiscalIdCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  // Register & Location
  final _storeNameCtrl = TextEditingController();
  final _registerCodeCtrl = TextEditingController();
  final _locationNameCtrl = TextEditingController();

  // Owner Account
  final _ownerUsernameCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _ownerPinCtrl = TextEditingController();
  final _ownerPinConfirmCtrl = TextEditingController();

  // Hardware Preferences
  int _paperWidthMm = 80;

  @override
  void dispose() {
    _companyNameCtrl.dispose();
    _fiscalIdCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _storeNameCtrl.dispose();
    _registerCodeCtrl.dispose();
    _locationNameCtrl.dispose();
    _ownerUsernameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _ownerPinCtrl.dispose();
    _ownerPinConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _completeSetup() async {
    final requiredFields = [
      _companyNameCtrl,
      _storeNameCtrl,
      _registerCodeCtrl,
      _locationNameCtrl,
      _ownerUsernameCtrl,
      _ownerNameCtrl,
    ];
    if (requiredFields.any((controller) => controller.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complétez tous les champs obligatoires avant de continuer',
          ),
          backgroundColor: AppDesignTokens.danger,
        ),
      );
      return;
    }

    if (_ownerPinCtrl.text.trim() != _ownerPinConfirmCtrl.text.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Les codes PIN ne correspondent pas'),
          backgroundColor: AppDesignTokens.danger,
        ),
      );
      return;
    }

    if (_ownerPinCtrl.text.trim().length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le code PIN doit comporter au moins 4 chiffres'),
          backgroundColor: AppDesignTokens.danger,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final db = ref.read(databaseProvider);
      final authService = ref.read(authServiceProvider);
      final now = DateTime.now();

      final companyId = IdGenerator.uuid();
      final storeId = 'STORE-01';
      final registerId = _registerCodeCtrl.text.trim();
      final locationId = IdGenerator.uuid();

      await db.transaction(() async {
        // 1. Company
        await db
            .into(db.companies)
            .insert(
              CompaniesCompanion.insert(
                id: companyId,
                name: _companyNameCtrl.text.trim(),
                fiscalId: drift.Value(_fiscalIdCtrl.text.trim()),
                phone: drift.Value(_phoneCtrl.text.trim()),
                address: drift.Value(_addressCtrl.text.trim()),
                createdAt: now,
                updatedAt: now,
              ),
            );

        // 2. Store
        await db
            .into(db.stores)
            .insert(
              StoresCompanion.insert(
                id: storeId,
                companyId: companyId,
                name: _storeNameCtrl.text.trim(),
                code: 'STORE-01',
                address: drift.Value(_addressCtrl.text.trim()),
                phone: drift.Value(_phoneCtrl.text.trim()),
                createdAt: now,
                updatedAt: now,
              ),
            );

        // 3. Register
        await db
            .into(db.registers)
            .insert(
              RegistersCompanion.insert(
                id: registerId,
                storeId: storeId,
                name: 'Caisse Principale',
                code: registerId,
                createdAt: now,
                updatedAt: now,
              ),
            );

        // 4. Default Stock Location
        await db
            .into(db.stockLocations)
            .insert(
              StockLocationsCompanion.insert(
                id: locationId,
                storeId: storeId,
                name: _locationNameCtrl.text.trim(),
                code: 'LOC-SHOP',
                locationType: AppConstants.locationShopFloor,
                isDefault: const drift.Value(true),
              ),
            );

        // 5. Create Owner user with hashed PIN
        await authService.createUser(
          username: _ownerUsernameCtrl.text.trim(),
          displayName: _ownerNameCtrl.text.trim(),
          role: AppRoles.owner,
          pin: _ownerPinCtrl.text.trim(),
        );

        // 6. Seed clothing attribute types (Size, Color)
        final sizeAttrId = IdGenerator.uuid();
        final colorAttrId = IdGenerator.uuid();
        await db
            .into(db.attributeTypes)
            .insert(
              AttributeTypesCompanion.insert(
                id: sizeAttrId,
                name: 'Taille',
                code: 'SIZE',
              ),
            );
        await db
            .into(db.attributeTypes)
            .insert(
              AttributeTypesCompanion.insert(
                id: colorAttrId,
                name: 'Couleur',
                code: 'COLOR',
              ),
            );

        // Seed common clothing sizes
        final sizes = [
          'XS',
          'S',
          'M',
          'L',
          'XL',
          'XXL',
          '38',
          '40',
          '42',
          '44',
        ];
        for (int i = 0; i < sizes.length; i++) {
          await db
              .into(db.attributeValues)
              .insert(
                AttributeValuesCompanion.insert(
                  id: IdGenerator.uuid(),
                  attributeTypeId: sizeAttrId,
                  value: sizes[i],
                  code: sizes[i],
                ),
              );
        }

        // Seed common colors
        final colors = [
          ('Noir', '#000000'),
          ('Blanc', '#FFFFFF'),
          ('Bleu Marine', '#000080'),
          ('Beige', '#F5F5DC'),
          ('Rouge', '#FF0000'),
          ('Gris', '#808080'),
          ('Vert Kaki', '#556B2F'),
        ];
        for (int i = 0; i < colors.length; i++) {
          await db
              .into(db.attributeValues)
              .insert(
                AttributeValuesCompanion.insert(
                  id: IdGenerator.uuid(),
                  attributeTypeId: colorAttrId,
                  value: colors[i].$1,
                  code: colors[i].$1,
                ),
              );
        }

        // 7. Seed standard clothing categories
        final categories = [
          'Hauts & Chemises',
          'Pantalons & Jeans',
          'Robes & Ensembles',
          'Vestes & Manteaux',
          'Accessoires',
        ];
        for (final cat in categories) {
          await db
              .into(db.categories)
              .insert(
                CategoriesCompanion.insert(id: IdGenerator.uuid(), name: cat),
              );
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuration initiale terminée avec succès !'),
            backgroundColor: AppDesignTokens.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
      }
    }
  }

  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: AppDesignTokens.textSecondary,
        fontSize: 13,
      ),
      prefixIcon: Icon(icon, size: 20, color: AppDesignTokens.textSecondary),
      filled: true,
      fillColor: AppDesignTokens.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput),
        borderSide: const BorderSide(color: AppDesignTokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput),
        borderSide: const BorderSide(color: AppDesignTokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput),
        borderSide: const BorderSide(
          color: AppDesignTokens.primary,
          width: 1.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesignTokens.canvas,
      appBar: AppBar(
        title: const Text(
          'Assistant d\'Installation & Configuration JazzPOS',
          style: TextStyle(
            color: AppDesignTokens.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        backgroundColor: AppDesignTokens.surface,
        foregroundColor: AppDesignTokens.textPrimary,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppDesignTokens.border),
        ),
      ),
      body: Center(
        child: Container(
          width: 820,
          margin: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: AppDesignTokens.surface,
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
            border: Border.all(color: AppDesignTokens.border),
            boxShadow: AppDesignTokens.shadowSm,
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              canvasColor: AppDesignTokens.surface,
              colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: AppDesignTokens.primary,
                secondary: AppDesignTokens.primary,
                onSurface: AppDesignTokens.textPrimary,
              ),
            ),
            child: Stepper(
              type: StepperType.horizontal,
              currentStep: _currentStep,
              onStepContinue: () {
                if (_currentStep < 3) {
                  setState(() => _currentStep += 1);
                } else {
                  _completeSetup();
                }
              },
              onStepCancel: () {
                if (_currentStep > 0) {
                  setState(() => _currentStep -= 1);
                }
              },
              controlsBuilder: (context, details) {
                return Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Row(
                    children: [
                      if (_currentStep > 0)
                        OutlinedButton(
                          onPressed: _isSaving ? null : details.onStepCancel,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppDesignTokens.textSecondary,
                            side: const BorderSide(
                              color: AppDesignTokens.border,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppDesignTokens.radiusInput,
                              ),
                            ),
                          ),
                          child: const Text('Précédent'),
                        ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: _isSaving ? null : details.onStepContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _currentStep == 3
                              ? AppDesignTokens.accentOrange
                              : AppDesignTokens.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppDesignTokens.radiusInput,
                            ),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _currentStep == 3
                                    ? 'TERMINER ET INITIALISER'
                                    : 'Suivant',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ],
                  ),
                );
              },
              steps: [
                // Step 1: Boutique & Entreprise
                Step(
                  title: const Text('Boutique'),
                  isActive: _currentStep >= 0,
                  state: _currentStep > 0
                      ? StepState.complete
                      : StepState.indexed,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Informations sur votre commerce de prêt-à-porter :',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _companyNameCtrl,
                        decoration: _buildInputDecoration(
                          'Nom de la Boutique / Société *',
                          Icons.store,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _fiscalIdCtrl,
                        decoration: _buildInputDecoration(
                          'Matricule Fiscal (MF)',
                          Icons.badge,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _phoneCtrl,
                              decoration: _buildInputDecoration(
                                'Téléphone',
                                Icons.phone,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _addressCtrl,
                              decoration: _buildInputDecoration(
                                'Adresse',
                                Icons.location_on,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Step 2: Caisse & Stock
                Step(
                  title: const Text('Caisse'),
                  isActive: _currentStep >= 1,
                  state: _currentStep > 1
                      ? StepState.complete
                      : StepState.indexed,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Identification de ce poste de caisse :',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _storeNameCtrl,
                        decoration: _buildInputDecoration(
                          'Nom du Point de Vente',
                          Icons.domain,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _registerCodeCtrl,
                        decoration: _buildInputDecoration(
                          'Identifiant Caisse (ex: REG-01)',
                          Icons.computer,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _locationNameCtrl,
                        decoration: _buildInputDecoration(
                          'Emplacement de stock boutique',
                          Icons.warehouse,
                        ),
                      ),
                    ],
                  ),
                ),

                // Step 3: Compte Propriétaire
                Step(
                  title: const Text('Admin PIN'),
                  isActive: _currentStep >= 2,
                  state: _currentStep > 2
                      ? StepState.complete
                      : StepState.indexed,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Création du compte administrateur / gérant :',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _ownerNameCtrl,
                        decoration: _buildInputDecoration(
                          'Nom complet du gérant *',
                          Icons.person,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _ownerUsernameCtrl,
                        decoration: _buildInputDecoration(
                          'Identifiant de connexion *',
                          Icons.account_circle,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _ownerPinCtrl,
                              keyboardType: TextInputType.number,
                              obscureText: true,
                              maxLength: 6,
                              decoration: _buildInputDecoration(
                                'Code PIN (4 à 6 chiffres) *',
                                Icons.pin,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _ownerPinConfirmCtrl,
                              keyboardType: TextInputType.number,
                              obscureText: true,
                              maxLength: 6,
                              decoration: _buildInputDecoration(
                                'Confirmer Code PIN *',
                                Icons.lock_clock,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Step 4: Matériel & Prêt
                Step(
                  title: const Text('Périphériques'),
                  isActive: _currentStep >= 3,
                  state: StepState.indexed,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Configuration des périphériques POS (POSBANK) :',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Largeur de papier imprimante ticket de caisse :',
                        style: TextStyle(
                          color: AppDesignTokens.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('80 mm (Standard POS)'),
                            selected: _paperWidthMm == 80,
                            selectedColor: AppDesignTokens.primary.withValues(
                              alpha: 0.12,
                            ),
                            labelStyle: TextStyle(
                              color: _paperWidthMm == 80
                                  ? AppDesignTokens.primary
                                  : AppDesignTokens.textSecondary,
                              fontWeight: _paperWidthMm == 80
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            onSelected: (_) =>
                                setState(() => _paperWidthMm = 80),
                          ),
                          const SizedBox(width: 12),
                          ChoiceChip(
                            label: const Text('58 mm (Compact)'),
                            selected: _paperWidthMm == 58,
                            selectedColor: AppDesignTokens.primary.withValues(
                              alpha: 0.12,
                            ),
                            labelStyle: TextStyle(
                              color: _paperWidthMm == 58
                                  ? AppDesignTokens.primary
                                  : AppDesignTokens.textSecondary,
                              fontWeight: _paperWidthMm == 58
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            onSelected: (_) =>
                                setState(() => _paperWidthMm = 58),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppDesignTokens.surfaceSecondary,
                          borderRadius: BorderRadius.circular(
                            AppDesignTokens.radiusCard,
                          ),
                          border: Border.all(color: AppDesignTokens.border),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: AppDesignTokens.success,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Scanner code-barres USB HID : Détection automatique',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppDesignTokens.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: AppDesignTokens.success,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Tiroir-caisse RJ11 (Piloté via imprimante)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppDesignTokens.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: AppDesignTokens.success,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Devise système : Dinar Tunisien (TND - 3 décimales)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppDesignTokens.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
