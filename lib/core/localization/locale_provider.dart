import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../platform/app_paths.dart';

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('fr')) {
    _loadSavedLocale();
  }

  File get _settingsFile =>
      File(p.join(AppPaths.instance.baseDir.path, 'app_settings.json'));

  Future<void> _loadSavedLocale() async {
    try {
      final file = _settingsFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final langCode = data['languageCode'] as String?;
        if (langCode != null && ['fr', 'ar', 'en'].contains(langCode)) {
          state = Locale(langCode);
        }
      }
    } catch (_) {
      // Fallback to default Locale('fr')
    }
  }

  Future<void> setLocale(Locale newLocale) async {
    if (!['fr', 'ar', 'en'].contains(newLocale.languageCode)) return;
    state = newLocale;
    try {
      final file = _settingsFile;
      Map<String, dynamic> data = {};
      if (await file.exists()) {
        final content = await file.readAsString();
        data = jsonDecode(content) as Map<String, dynamic>;
      }
      data['languageCode'] = newLocale.languageCode;
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }
}
