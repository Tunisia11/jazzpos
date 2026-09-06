import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'app_localizations.dart';
export 'app_localizations.dart';
import 'translations/translations_ar.dart';
import 'translations/translations_en.dart';
import 'translations/translations_fr.dart';

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['fr', 'ar', 'en'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(_lookupLocalizations(locale));
  }

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;

  static AppLocalizations _lookupLocalizations(Locale locale) {
    switch (locale.languageCode) {
      case 'ar':
        return AppLocalizationsAr();
      case 'en':
        return AppLocalizationsEn();
      case 'fr':
      default:
        return AppLocalizationsFr();
    }
  }
}
