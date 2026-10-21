import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/core/localization/locale_provider.dart';
import 'package:jazzpos/core/platform/app_paths.dart';
import 'package:jazzpos/core/platform/windows_startup.dart';
import 'package:jazzpos/core/sound/sound_effect_service.dart';
import 'package:jazzpos/domain/services/boutique_settings_service.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'package:jazzpos/ui/widgets/common/app_card.dart';

class BoutiqueGeneralTab extends ConsumerStatefulWidget {
  const BoutiqueGeneralTab({super.key});

  @override
  ConsumerState<BoutiqueGeneralTab> createState() => _BoutiqueGeneralTabState();
}

class _BoutiqueGeneralTabState extends ConsumerState<BoutiqueGeneralTab> {
  final _formKey = GlobalKey<FormState>();
  final _storeNameCtrl = TextEditingController();
  final _fiscalIdCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController(text: 'TND');
  final _receiptHeaderCtrl = TextEditingController();
  final _receiptFooterCtrl = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _autoStartEnabled = false;
  Map<String, bool>? _storageHealth;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkAutoStart();
    _checkStorageHealth();
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _fiscalIdCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _emailCtrl.dispose();
    _currencyCtrl.dispose();
    _receiptHeaderCtrl.dispose();
    _receiptFooterCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(boutiqueSettingsServiceProvider);
      final settings = await service.loadSettings();
      if (mounted) {
        setState(() {
          _storeNameCtrl.text = settings.name;
          _fiscalIdCtrl.text = settings.fiscalId ?? '';
          _phoneCtrl.text = settings.phone ?? '';
          _addressCtrl.text = settings.address ?? '';
          _emailCtrl.text = settings.email ?? '';
          _currencyCtrl.text = settings.currency;
          _receiptHeaderCtrl.text = settings.receiptHeader ?? '';
          _receiptFooterCtrl.text = settings.receiptFooter ?? 'Merci de votre visite ! À bientôt.';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur chargement paramètres : $e'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final service = ref.read(boutiqueSettingsServiceProvider);
      final updated = BoutiqueSettings(
        name: _storeNameCtrl.text.trim(),
        fiscalId: _fiscalIdCtrl.text.trim().isEmpty ? null : _fiscalIdCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        currency: _currencyCtrl.text.trim().isEmpty ? 'TND' : _currencyCtrl.text.trim().toUpperCase(),
        receiptHeader: _receiptHeaderCtrl.text.trim().isEmpty ? null : _receiptHeaderCtrl.text.trim(),
        receiptFooter: _receiptFooterCtrl.text.trim().isEmpty ? null : _receiptFooterCtrl.text.trim(),
      );
      await service.saveSettings(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Informations de la boutique enregistrées avec succès.'),
            backgroundColor: AppDesignTokens.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur enregistrement : $e'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _checkAutoStart() async {
    if (Platform.isWindows) {
      final enabled = await WindowsStartup.isAutoStartEnabled();
      if (mounted) setState(() => _autoStartEnabled = enabled);
    }
  }

  Future<void> _toggleAutoStart(bool enable) async {
    if (enable) {
      await WindowsStartup.enableAutoStart();
    } else {
      await WindowsStartup.disableAutoStart();
    }
    await _checkAutoStart();
  }

  Future<void> _checkStorageHealth() async {
    final health = await AppPaths.instance.verifyStorageHealth();
    if (mounted) setState(() => _storageHealth = health);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentLocale = ref.watch(localeProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDesignTokens.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section 1: Boutique Information Card ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Informations de la Boutique & Enseigne',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Coordonnées figurant sur les tickets de caisse, rapports et documents fiscaux',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveSettings,
                icon: _isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Enregistrer les modifications'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppDesignTokens.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignTokens.space12),

          AppCard(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _storeNameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nom de la Boutique / Enseigne *',
                            hintText: 'Ex: Trace Boutique Mode',
                            prefixIcon: Icon(Icons.storefront_outlined, size: 20),
                          ),
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? 'Le nom est obligatoire' : null,
                        ),
                      ),
                      const SizedBox(width: AppDesignTokens.space16),
                      Expanded(
                        child: TextFormField(
                          controller: _fiscalIdCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Matricule Fiscale / Identifiant Unique',
                            hintText: 'Ex: 1234567/A/M/000',
                            prefixIcon: Icon(Icons.badge_outlined, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDesignTokens.space16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _phoneCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Téléphone de la Boutique',
                            hintText: 'Ex: +216 71 234 567',
                            prefixIcon: Icon(Icons.phone_outlined, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppDesignTokens.space16),
                      Expanded(
                        child: TextFormField(
                          controller: _emailCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Email de Contact',
                            hintText: 'Ex: contact@trace-boutique.tn',
                            prefixIcon: Icon(Icons.email_outlined, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDesignTokens.space16),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _addressCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Adresse Physique',
                            hintText: 'Ex: Avenue Habib Bourguiba, Tunis',
                            prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppDesignTokens.space16),
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          controller: _currencyCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Devise Caisse',
                            hintText: 'TND',
                            prefixIcon: Icon(Icons.payments_outlined, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDesignTokens.space16),
                  const Divider(color: AppDesignTokens.border),
                  const SizedBox(height: AppDesignTokens.space12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _receiptHeaderCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'En-tête personnalisé du ticket',
                            hintText: 'Message additionnel affiché sous les coordonnées',
                            alignLabelWithHint: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppDesignTokens.space16),
                      Expanded(
                        child: TextFormField(
                          controller: _receiptFooterCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Pied de page ticket (Message de remerciement)',
                            hintText: 'Ex: Merci de votre visite ! À bientôt.',
                            alignLabelWithHint: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppDesignTokens.space24),

          // ── Section 2: Language Selection Card ──
          Text(
            context.loc.languageSection,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: AppDesignTokens.space12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.loc.selectLanguage,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: AppDesignTokens.space16),
                Row(
                  children: [
                    _buildLanguageOption(
                      title: 'Français',
                      subtitle: 'Français (Tunisie)',
                      code: 'fr',
                      flag: '🇫🇷',
                      isSelected: currentLocale.languageCode == 'fr',
                    ),
                    const SizedBox(width: AppDesignTokens.space16),
                    _buildLanguageOption(
                      title: 'العربية',
                      subtitle: 'عربي (RTL كامل)',
                      code: 'ar',
                      flag: '🇹🇳',
                      isSelected: currentLocale.languageCode == 'ar',
                    ),
                    const SizedBox(width: AppDesignTokens.space16),
                    _buildLanguageOption(
                      title: 'English',
                      subtitle: 'English (US/UK)',
                      code: 'en',
                      flag: '🇬🇧',
                      isSelected: currentLocale.languageCode == 'en',
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: AppDesignTokens.space24),

          // ── Section 3: Audio & Sound Effects ──
          const Text(
            'Retour Sonore & Audio Caisse',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: AppDesignTokens.space12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Sons des touches et du pavé numérique',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppDesignTokens.textPrimary,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Retour sonore instantané lors de la saisie des chiffres, boutons et validations',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppDesignTokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: SoundEffectService.instance.isEnabled,
                      activeThumbColor: AppDesignTokens.primary,
                      onChanged: (val) {
                        setState(() {
                          SoundEffectService.instance.isEnabled = val;
                        });
                        if (val) {
                          SoundEffectService.instance.playKeyTap();
                        }
                      },
                    ),
                  ],
                ),
                if (SoundEffectService.instance.isEnabled) ...[
                  const Divider(color: AppDesignTokens.border),
                  const SizedBox(height: 6),
                  const Text(
                    'Tester les effets sonores :',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => SoundEffectService.instance.playKeyTap(),
                        icon: const Icon(Icons.dialpad, size: 16),
                        label: const Text('Touche Chiffre', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppDesignTokens.border),
                          foregroundColor: AppDesignTokens.textPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => SoundEffectService.instance.playBackspace(),
                        icon: const Icon(Icons.backspace_outlined, size: 16),
                        label: const Text('Effacer ⌫', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppDesignTokens.border),
                          foregroundColor: AppDesignTokens.textPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => SoundEffectService.instance.playSuccess(),
                        icon: const Icon(Icons.check_circle_outline, size: 16, color: AppDesignTokens.success),
                        label: const Text('Succès / Vente', style: TextStyle(fontSize: 12, color: AppDesignTokens.success)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF86EFAC)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => SoundEffectService.instance.playError(),
                        icon: const Icon(Icons.error_outline, size: 16, color: AppDesignTokens.danger),
                        label: const Text('Erreur / Rejet', style: TextStyle(fontSize: 12, color: AppDesignTokens.danger)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFFCA5A5)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: AppDesignTokens.space24),

          // ── Section 4: System Information & Autostart ──
          const Text(
            'Informations Système & Point de Vente',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: AppDesignTokens.space12),
          AppCard(
            child: Column(
              children: [
                _InfoRow(
                  'Application :',
                  '${AppConstants.appName} Desktop v1.0.0 (Production Boutique)',
                ),
                const Divider(color: AppDesignTokens.border),
                const _InfoRow(
                  'Moteur de Base de Données :',
                  'SQLite 3 via Drift (WAL Mode, Schema v2)',
                ),
                const Divider(color: AppDesignTokens.border),
                _InfoRow(
                  'Devise Configurée :',
                  '${_currencyCtrl.text.isNotEmpty ? _currencyCtrl.text : "TND"} (3 décimales, millimes entiers)',
                ),
                const Divider(color: AppDesignTokens.border),
                const _InfoRow(
                  'Architecture Cible :',
                  'Windows 10/11 IoT & macOS POS',
                ),
                const Divider(color: AppDesignTokens.border),
                _InfoRow(
                  'Base de Données Locale :',
                  AppPaths.instance.databaseFilePath,
                ),
                const Divider(color: AppDesignTokens.border),
                _InfoRow(
                  'Dossier Sauvegardes :',
                  AppPaths.instance.backupsDir.path,
                ),
                if (_storageHealth != null) ...[
                  const Divider(color: AppDesignTokens.border),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Santé Stockage / Permissions :',
                          style: TextStyle(color: AppDesignTokens.textSecondary),
                        ),
                        Text(
                          _storageHealth!.values.every((v) => v)
                              ? 'TOUS DOSSIERS ACCESSIBLES EN ÉCRITURE (OK)'
                              : 'ERREUR PERMISSION DOSSIER',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _storageHealth!.values.every((v) => v)
                                ? AppDesignTokens.success
                                : AppDesignTokens.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (Platform.isWindows) ...[
                  const Divider(color: AppDesignTokens.border),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Démarrage automatique Windows :',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppDesignTokens.textPrimary,
                              ),
                            ),
                            Text(
                              'Lancer ${AppConstants.appName} automatiquement au démarrage du terminal caisse',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppDesignTokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        Switch(
                          value: _autoStartEnabled,
                          onChanged: (val) => _toggleAutoStart(val),
                          activeThumbColor: AppDesignTokens.primary,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageOption({
    required String title,
    required String subtitle,
    required String code,
    required String flag,
    required bool isSelected,
  }) {
    return Expanded(
      child: InkWell(
        onTap: () {
          ref.read(localeProvider.notifier).setLocale(Locale(code));
        },
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput),
        child: Container(
          padding: const EdgeInsets.all(AppDesignTokens.space16),
          decoration: BoxDecoration(
            color: isSelected
                ? AppDesignTokens.primary.withValues(alpha: 0.05)
                : AppDesignTokens.surface,
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput),
            border: Border.all(
              color: isSelected ? AppDesignTokens.primary : AppDesignTokens.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(flag, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: AppDesignTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected
                            ? AppDesignTokens.primary
                            : AppDesignTokens.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: AppDesignTokens.primary,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppDesignTokens.textSecondary)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppDesignTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
