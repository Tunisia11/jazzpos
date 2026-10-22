import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tracepos/core/platform/app_paths.dart';
import 'package:tracepos/core/platform/legacy_names.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a pre-rename database and its WAL files are renamed, not lost', () async {
    final root = await Directory.systemTemp.createTemp('trace_legacy_');
    addTearDown(() => root.delete(recursive: true));
    final dbDir = Directory(p.join(root.path, 'database'))..createSync();
    for (final suffix in ['', '-wal', '-shm']) {
      File(p.join(dbDir.path, '${LegacyNames.databaseFile}$suffix'))
          .writeAsStringSync('data$suffix');
    }

    await AppPaths.instance.initialize(customBaseDir: root);

    final current = AppPaths.instance.databaseFilePath;
    expect(p.basename(current), 'tracepos.sqlite');
    expect(File(current).readAsStringSync(), 'data');
    expect(File('$current-wal').readAsStringSync(), 'data-wal');
    expect(File('$current-shm').existsSync(), isTrue);
    expect(File(p.join(dbDir.path, LegacyNames.databaseFile)).existsSync(), isFalse);
  });

  test('an existing new database is never overwritten', () async {
    final root = await Directory.systemTemp.createTemp('trace_legacy2_');
    addTearDown(() => root.delete(recursive: true));
    final dbDir = Directory(p.join(root.path, 'database'))..createSync();
    File(p.join(dbDir.path, LegacyNames.databaseFile)).writeAsStringSync('old');
    File(p.join(dbDir.path, 'tracepos.sqlite')).writeAsStringSync('new');

    await AppPaths.instance.initialize(customBaseDir: root);

    expect(File(AppPaths.instance.databaseFilePath).readAsStringSync(), 'new');
  });
}
