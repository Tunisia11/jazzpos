import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/localization/app_localizations.dart';
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
  bool _showAdvancedRegister = false;

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
  void initState() {
    super.initState();
    _loadInitialDefaults();
  }

  Future<void> _loadInitialDefaults() async {
    try {
      final initService = ref.read(posInitializationServiceProvider);
      final code = await initService.generateNextRegisterCode();
      if (mounted) {
        setState(() {
          if (_registerCodeCtrl.text.isEmpty) {
            _registerCodeCtrl.text = code;
          }
          if (_storeNameCtrl.text.isEmpty) {
            _storeNameCtrl.text = 'Boutique Principale';
          }
          if (_locationNameCtrl.text.isEmpty) {
            _locationNameCtrl.text = 'Stock principal';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (_registerCodeCtrl.text.isEmpty) {
            _registerCodeCtrl.text = 'REG-001';
          }
          if (_storeNameCtrl.text.isEmpty) {
            _storeNameCtrl.text = 'Boutique Principale';
          }
          if (_locationNameCtrl.text.isEmpty) {
            _locationNameCtrl.text = 'Stock principal';
          }
        });
      }
    }
  }

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
    final loc = context.loc;
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
        SnackBar(
          content: Text(loc.wizardFillRequired),
          backgroundColor: AppDesignTokens.danger,
        ),
      );
      return;
    }

    if (_ownerPinCtrl.text.trim() != _ownerPinConfirmCtrl.text.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.wizardPinMismatch),
          backgroundColor: AppDesignTokens.danger,
        ),
      );
      return;
    }

    if (_ownerPinCtrl.text.trim().length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.wizardPinTooShort),
          backgroundColor: AppDesignTokens.danger,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final initService = ref.read(posInitializationServiceProvider);
      await initService.initializePos(
        companyName: _companyNameCtrl.text.trim(),
        fiscalId: _fiscalIdCtrl.text.trim().isEmpty ? null : _fiscalIdCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        storeName: _storeNameCtrl.text.trim(),
        registerCode: _registerCodeCtrl.text.trim(),
        registerName: 'Caisse Principale',
        locationName: _locationNameCtrl.text.trim(),
        ownerUsername: _ownerUsernameCtrl.text.trim(),
        ownerDisplayName: _ownerNameCtrl.text.trim(),
        ownerPin: _ownerPinCtrl.text.trim(),
        paperWidthMm: _paperWidthMm,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.wizardSuccess),
            backgroundColor: AppDesignTokens.success,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        final errorMessage = (e is PosException)
            ? e.message
            : (e is AuthException)
                ? e.message
                : e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.error_outline, color: AppDesignTokens.danger),
                const SizedBox(width: 8),
                Text(loc.wizardErrorTitle),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  errorMessage,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Vos informations saisies sont conservées. Vous pouvez corriger les champs ou réessayer immédiatement.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(loc.close),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppDesignTokens.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _completeSetup();
                },
                child: Text(loc.wizardRetry),
              ),
            ],
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
    final loc = context.loc;

    return Scaffold(
      backgroundColor: AppDesignTokens.canvas,
      appBar: AppBar(
        title: Text(
          loc.wizardTitle,
          style: const TextStyle(
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
                          child: Text(loc.wizardBackButton),
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
                                    ? loc.wizardFinishButton
                                    : loc.wizardNextButton,
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
                  title: Text(loc.wizardStepStore),
                  isActive: _currentStep >= 0,
                  state: _currentStep > 0
                      ? StepState.complete
                      : StepState.indexed,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.wizardStoreInfo,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _companyNameCtrl,
                        decoration: _buildInputDecoration(
                          loc.wizardCompanyName,
                          Icons.store,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _fiscalIdCtrl,
                        decoration: _buildInputDecoration(
                          loc.wizardFiscalId,
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
                                loc.wizardPhone,
                                Icons.phone,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _addressCtrl,
                              decoration: _buildInputDecoration(
                                loc.wizardAddress,
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
                  title: Text(loc.wizardStepRegister),
                  isActive: _currentStep >= 1,
                  state: _currentStep > 1
                      ? StepState.complete
                      : StepState.indexed,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.wizardRegisterInfo,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _storeNameCtrl,
                        decoration: _buildInputDecoration(
                          loc.wizardStoreName,
                          Icons.domain,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Register Code Container with auto-badge and edit toggle
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppDesignTokens.surfaceSecondary,
                          borderRadius: BorderRadius.circular(
                            AppDesignTokens.radiusInput,
                          ),
                          border: Border.all(color: AppDesignTokens.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.computer,
                                  size: 20,
                                  color: AppDesignTokens.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  loc.wizardRegisterCodeAuto,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppDesignTokens.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppDesignTokens.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _registerCodeCtrl.text.isEmpty
                                        ? 'REG-001'
                                        : _registerCodeCtrl.text,
                                    style: const TextStyle(
                                      fontFamily: 'Consolas',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppDesignTokens.primary,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _showAdvancedRegister =
                                          !_showAdvancedRegister;
                                    });
                                  },
                                  icon: Icon(
                                    _showAdvancedRegister
                                        ? Icons.check
                                        : Icons.tune,
                                    size: 16,
                                    color: AppDesignTokens.textSecondary,
                                  ),
                                  label: Text(
                                    _showAdvancedRegister
                                        ? loc.confirm
                                        : loc.wizardRegisterCodeEdit,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppDesignTokens.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_showAdvancedRegister) ...[
                              const SizedBox(height: 10),
                              TextField(
                                controller: _registerCodeCtrl,
                                decoration: _buildInputDecoration(
                                  loc.wizardRegisterCode,
                                  Icons.edit,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _locationNameCtrl,
                        decoration: _buildInputDecoration(
                          loc.wizardStockLocation,
                          Icons.warehouse,
                        ),
                      ),
                    ],
                  ),
                ),

                // Step 3: Compte Propriétaire
                Step(
                  title: Text(loc.wizardStepAdmin),
                  isActive: _currentStep >= 2,
                  state: _currentStep > 2
                      ? StepState.complete
                      : StepState.indexed,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.wizardAdminInfo,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _ownerNameCtrl,
                        decoration: _buildInputDecoration(
                          loc.wizardOwnerName,
                          Icons.person,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _ownerUsernameCtrl,
                        decoration: _buildInputDecoration(
                          loc.wizardOwnerUsername,
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
                                loc.wizardOwnerPin,
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
                                loc.wizardOwnerPinConfirm,
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
                  title: Text(loc.wizardStepHardware),
                  isActive: _currentStep >= 3,
                  state: StepState.indexed,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.wizardHardwareInfo,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Non-blocking hardware notice
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppDesignTokens.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(
                            AppDesignTokens.radiusInput,
                          ),
                          border: Border.all(
                            color: AppDesignTokens.primary.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: AppDesignTokens.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                loc.wizardHardwareNotice,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppDesignTokens.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        loc.wizardPaperWidth,
                        style: const TextStyle(
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
