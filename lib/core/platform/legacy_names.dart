/// Names used by releases made before the app was renamed to Trace POS.
///
/// They exist only so a shop upgrading keeps its data, database and
/// auto-start entry. Nothing else in the app should use them, and this file
/// can be deleted once no pre-rename installation remains.
class LegacyNames {
  const LegacyNames._();

  /// Per-user data folder name.
  static const String dataDir = 'JazzPOS';

  /// Database file name inside the database folder.
  static const String databaseFile = 'jazzpos.sqlite';

  /// Environment variable that overrode the data folder.
  static const String dataDirEnv = 'JAZZPOS_DATA_DIR';

  /// Windows auto-start registry value name.
  static const String startupRegistryName = 'JazzPOS';
}
