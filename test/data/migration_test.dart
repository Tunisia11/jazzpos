import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('jazzpos_migration_');
    file = File(p.join(dir.path, 'v1.sqlite'));

    // Build a database, then downgrade it to the v1 shape.
    final db = AppDatabase(NativeDatabase(file));
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: 'p1',
          name: 'Keep Me',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ));
    await db.close();

    final raw = sqlite.sqlite3.open(file.path);
    for (final t in ['products', 'product_variants']) {
      raw.execute('ALTER TABLE $t DROP COLUMN image_url;');
      raw.execute('ALTER TABLE $t DROP COLUMN deleted_at;');
    }
    raw.execute('PRAGMA user_version = 1;');
    raw.dispose();
  });

  tearDown(() => dir.delete(recursive: true));

  test('v1 database upgrades to v2 and keeps its data', () async {
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final product = await (db.select(db.products)
          ..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(product.name, 'Keep Me');
    expect(product.imageUrl, isNull);
    expect(product.deletedAt, isNull);

    final cols = await db.customSelect('PRAGMA table_info(product_variants);').get();
    expect(cols.map((r) => r.data['name']), containsAll(['image_url', 'deleted_at']));

    final version = await db.customSelect('PRAGMA user_version;').getSingle();
    expect(version.data['user_version'], 2);
  });

  test('re-running a half-applied upgrade does not fail', () async {
    // Column already present although user_version still says 1.
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute('ALTER TABLE products ADD COLUMN image_url TEXT;');
    raw.dispose();

    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final rows = await db.select(db.products).get();
    expect(rows.single.name, 'Keep Me');
  });
}
