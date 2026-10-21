import 'package:flutter/material.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'tabs/backup_data_tab.dart';
import 'tabs/boutique_general_tab.dart';
import 'tabs/categories_management_tab.dart';
import 'tabs/hardware_diagnostics_tab.dart';
import 'tabs/staff_management_tab.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesignTokens.canvas,
      appBar: AppBar(
        title: Text(
          context.loc.settingsTitle,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        backgroundColor: AppDesignTokens.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppDesignTokens.textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(
            children: [
              TabBar(
                controller: _tabController,
                indicatorColor: AppDesignTokens.primary,
                labelColor: AppDesignTokens.primary,
                unselectedLabelColor: AppDesignTokens.textSecondary,
                indicatorWeight: 3,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.storefront_outlined, size: 20),
                    text: 'Boutique & Général',
                  ),
                  Tab(
                    icon: Icon(Icons.people_outline, size: 20),
                    text: 'Personnel & Caissiers',
                  ),
                  Tab(
                    icon: Icon(Icons.category_outlined, size: 20),
                    text: 'Catégories',
                  ),
                  Tab(
                    icon: Icon(Icons.print_outlined, size: 20),
                    text: 'Matériel & Diagnostics',
                  ),
                  Tab(
                    icon: Icon(Icons.backup_outlined, size: 20),
                    text: 'Sauvegarde & Données',
                  ),
                ],
              ),
              const Divider(height: 1, color: AppDesignTokens.border),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          BoutiqueGeneralTab(),
          StaffManagementTab(),
          CategoriesManagementTab(),
          HardwareDiagnosticsTab(),
          BackupDataTab(),
        ],
      ),
    );
  }
}
