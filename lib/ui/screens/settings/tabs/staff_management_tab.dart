import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/constants/roles.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'package:jazzpos/ui/widgets/common/app_card.dart';

class StaffManagementTab extends ConsumerStatefulWidget {
  const StaffManagementTab({super.key});

  @override
  ConsumerState<StaffManagementTab> createState() => _StaffManagementTabState();
}

class _StaffManagementTabState extends ConsumerState<StaffManagementTab> {
  List<User> _staffList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    setState(() => _isLoading = true);
    try {
      final authService = ref.read(authServiceProvider);
      final users = await authService.getAllUsers();
      if (mounted) setState(() => _staffList = users);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors du chargement des employés : $e'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _roleLabel(String role) {
    switch (role.toLowerCase()) {
      case AppRoles.owner:
        return 'Propriétaire (Admin)';
      case AppRoles.manager:
        return 'Responsable Boutique';
      case AppRoles.cashier:
        return 'Caissier / Vendeur';
      default:
        return role.toUpperCase();
    }
  }

  Color _roleColor(String role) {
    switch (role.toLowerCase()) {
      case AppRoles.owner:
        return Colors.purple;
      case AppRoles.manager:
        return AppDesignTokens.primary;
      case AppRoles.cashier:
        return AppDesignTokens.success;
      default:
        return AppDesignTokens.textSecondary;
    }
  }

  Future<void> _showAddUserDialog() async {
    final formKey = GlobalKey<FormState>();
    final usernameCtrl = TextEditingController();
    final displayNameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    final confirmPinCtrl = TextEditingController();
    String selectedRole = AppRoles.cashier;
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard)),
          title: Row(
            children: const [
              Icon(Icons.person_add_outlined, color: AppDesignTokens.primary),
              SizedBox(width: 8),
              Text('Ajouter un Employé / Caissier', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: usernameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Identifiant de Connexion *',
                      hintText: 'Ex: caissier1 (sans espaces)',
                      prefixIcon: Icon(Icons.alternate_email, size: 20),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Identifiant obligatoire';
                      if (v.trim().contains(' ')) return 'Pas d\'espaces dans l\'identifiant';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: displayNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nom & Prénom *',
                      hintText: 'Ex: Amine Ben Salem',
                      prefixIcon: Icon(Icons.badge_outlined, size: 20),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Nom obligatoire' : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Rôle & Permissions *',
                      prefixIcon: Icon(Icons.security_outlined, size: 20),
                    ),
                    items: [
                      DropdownMenuItem(value: AppRoles.cashier, child: Text(_roleLabel(AppRoles.cashier))),
                      DropdownMenuItem(value: AppRoles.manager, child: Text(_roleLabel(AppRoles.manager))),
                      DropdownMenuItem(value: AppRoles.owner, child: Text(_roleLabel(AppRoles.owner))),
                    ],
                    onChanged: (v) {
                      if (v != null) setDlgState(() => selectedRole = v);
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: pinCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Code PIN Caisse (4 à 6 chiffres) *',
                      hintText: '••••',
                      prefixIcon: Icon(Icons.dialpad, size: 20),
                    ),
                    validator: (v) {
                      if (v == null || v.length < 4) return 'PIN de 4 chiffres minimum';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: confirmPinCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Confirmer le Code PIN *',
                      hintText: '••••',
                      prefixIcon: Icon(Icons.check_outlined, size: 20),
                    ),
                    validator: (v) {
                      if (v != pinCtrl.text) return 'Les codes PIN ne correspondent pas';
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDlgState(() => isSaving = true);
                      try {
                        final authService = ref.read(authServiceProvider);
                        await authService.createUser(
                          username: usernameCtrl.text.trim(),
                          displayName: displayNameCtrl.text.trim(),
                          role: selectedRole,
                          pin: pinCtrl.text.trim(),
                        );
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Employé "${displayNameCtrl.text.trim()}" créé avec succès.'),
                              backgroundColor: AppDesignTokens.success,
                            ),
                          );
                          _loadStaff();
                        }
                      } catch (e) {
                        setDlgState(() => isSaving = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Erreur création : $e'),
                              backgroundColor: AppDesignTokens.danger,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppDesignTokens.primary,
                foregroundColor: Colors.white,
              ),
              child: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Créer l\'Employé'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditUserDialog(User user) async {
    final formKey = GlobalKey<FormState>();
    final displayNameCtrl = TextEditingController(text: user.displayName);
    String selectedRole = user.role;
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard)),
          title: Text('Modifier l\'employé @${user.username}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 400,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: displayNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nom & Prénom',
                      prefixIcon: Icon(Icons.badge_outlined, size: 20),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Nom obligatoire' : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Rôle & Droits',
                      prefixIcon: Icon(Icons.security_outlined, size: 20),
                    ),
                    items: [
                      DropdownMenuItem(value: AppRoles.cashier, child: Text(_roleLabel(AppRoles.cashier))),
                      DropdownMenuItem(value: AppRoles.manager, child: Text(_roleLabel(AppRoles.manager))),
                      DropdownMenuItem(value: AppRoles.owner, child: Text(_roleLabel(AppRoles.owner))),
                    ],
                    onChanged: (v) {
                      if (v != null) setDlgState(() => selectedRole = v);
                    },
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
                        final authService = ref.read(authServiceProvider);
                        await authService.updateUser(
                          userId: user.id,
                          displayName: displayNameCtrl.text.trim(),
                          role: selectedRole,
                        );
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Informations mises à jour.'),
                              backgroundColor: AppDesignTokens.success,
                            ),
                          );
                          _loadStaff();
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

  Future<void> _showResetPinDialog(User user) async {
    final formKey = GlobalKey<FormState>();
    final pinCtrl = TextEditingController();
    final confirmPinCtrl = TextEditingController();
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard)),
          title: Text('Réinitialiser le PIN de ${user.displayName}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 380,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Le nouveau code PIN sera immédiatement hashé avec un sel cryptographique aléatoire.',
                    style: TextStyle(fontSize: 12, color: AppDesignTokens.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: pinCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Nouveau Code PIN (4 à 6 chiffres) *',
                      hintText: '••••',
                      prefixIcon: Icon(Icons.lock_reset, size: 20),
                    ),
                    validator: (v) {
                      if (v == null || v.length < 4) return 'PIN de 4 chiffres minimum';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: confirmPinCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Confirmer le nouveau PIN *',
                      hintText: '••••',
                      prefixIcon: Icon(Icons.check_circle_outline, size: 20),
                    ),
                    validator: (v) {
                      if (v != pinCtrl.text) return 'Les codes PIN ne correspondent pas';
                      return null;
                    },
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
                        final authService = ref.read(authServiceProvider);
                        await authService.resetUserPin(userId: user.id, newPin: pinCtrl.text.trim());
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Code PIN réinitialisé pour ${user.displayName}.'),
                              backgroundColor: AppDesignTokens.success,
                            ),
                          );
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
                  : const Text('Changer le PIN'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleUserActive(User user) async {
    final currentUser = ref.read(authNotifierProvider).user;
    if (currentUser?.id == user.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vous ne pouvez pas désactiver votre propre compte actuellement connecté.'),
          backgroundColor: AppDesignTokens.warning,
        ),
      );
      return;
    }

    try {
      final authService = ref.read(authServiceProvider);
      await authService.toggleUserActive(user.id, !user.isActive);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(user.isActive ? 'Compte "${user.displayName}" désactivé.' : 'Compte "${user.displayName}" activé.'),
          backgroundColor: AppDesignTokens.success,
        ),
      );
      _loadStaff();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: AppDesignTokens.danger),
      );
    }
  }

  Future<void> _confirmDeleteUser(User user) async {
    final currentUser = ref.read(authNotifierProvider).user;
    if (currentUser?.id == user.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de supprimer le compte actuellement utilisé.'),
          backgroundColor: AppDesignTokens.danger,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer la suppression'),
        content: Text('Êtes-vous sûr de vouloir supprimer définitivement le compte de ${user.displayName} (@${user.username}) ? Cette action est irréversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppDesignTokens.danger, foregroundColor: Colors.white),
            child: const Text('Supprimer définitivement'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final authService = ref.read(authServiceProvider);
        await authService.deleteUser(user.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Compte ${user.displayName} supprimé.'),
              backgroundColor: AppDesignTokens.success,
            ),
          );
          _loadStaff();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur: $e'), backgroundColor: AppDesignTokens.danger),
          );
        }
      }
    }
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
                    'Gestion des Employés & Caissiers',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppDesignTokens.textPrimary),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Création, rôles, codes PIN sécurisés et activation des comptes du personnel de caisse',
                    style: TextStyle(fontSize: 12, color: AppDesignTokens.textSecondary),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _showAddUserDialog,
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Ajouter un Employé'),
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
          else if (_staffList.isEmpty)
            AppCard(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      const Icon(Icons.people_outline, size: 48, color: AppDesignTokens.textSecondary),
                      const SizedBox(height: 12),
                      const Text('Aucun employé configuré', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _showAddUserDialog, child: const Text('Créer le premier compte')),
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
                itemCount: _staffList.length,
                separatorBuilder: (context, index) => const Divider(color: AppDesignTokens.border),
                itemBuilder: (context, index) {
                  final user = _staffList[index];
                  final roleColor = _roleColor(user.role);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: roleColor.withValues(alpha: 0.15),
                          child: Text(
                            user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : 'U',
                            style: TextStyle(fontWeight: FontWeight.bold, color: roleColor, fontSize: 16),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    user.displayName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppDesignTokens.textPrimary),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: roleColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: roleColor.withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      _roleLabel(user.role),
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: roleColor),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: user.isActive ? AppDesignTokens.successBg : AppDesignTokens.danger.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      user.isActive ? 'Actif' : 'Inactif',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: user.isActive ? AppDesignTokens.successText : AppDesignTokens.danger,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Identifiant: @${user.username} | PIN: •••• (hash PBKDF2)',
                                style: const TextStyle(fontSize: 12, color: AppDesignTokens.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: 'Modifier les infos',
                              onPressed: () => _showEditUserDialog(user),
                            ),
                            IconButton(
                              icon: const Icon(Icons.lock_reset, size: 18, color: AppDesignTokens.primary),
                              tooltip: 'Changer le code PIN',
                              onPressed: () => _showResetPinDialog(user),
                            ),
                            Switch(
                              value: user.isActive,
                              activeThumbColor: AppDesignTokens.success,
                              onChanged: (_) => _toggleUserActive(user),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: AppDesignTokens.danger),
                              tooltip: 'Supprimer',
                              onPressed: () => _confirmDeleteUser(user),
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
