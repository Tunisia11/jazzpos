import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/data/database/app_database.dart';
import 'package:tracepos/domain/services/catalog_service.dart';
import 'package:tracepos/domain/services/inventory_service.dart';
import 'package:tracepos/providers/catalog_provider.dart';

void main() {
  late AppDatabase db;
  late CatalogNotifier notifier;

  Future<void> product(String id, String? cat, {DateTime? at}) async {
    final now = at ?? DateTime(2026, 10, 1);
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: id,
          name: 'Produit $id',
          categoryId: Value(cat),
          createdAt: now,
          updatedAt: now,
        ));
    await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
          id: 'v$id',
          productId: id,
          sku: 'SKU$id',
          barcode: 'BAR$id',
          createdAt: now,
          updatedAt: now,
        ));
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.categories).insert(CategoriesCompanion.insert(id: 'c1', name: 'Hauts'));
    await db.into(db.categories).insert(CategoriesCompanion.insert(id: 'c2', name: 'Vestes'));
    await product('a', 'c1', at: DateTime(2026, 10, 1));
    await product('b', 'c1', at: DateTime(2026, 10, 2));
    await product('c', 'c2', at: DateTime(2026, 10, 3));
    final inventory = InventoryService(db);
    notifier = CatalogNotifier(CatalogService(db, inventory), db);
    await notifier.refresh();
  });
  tearDown(() => db.close());

  Set<String> ids() => notifier.state.variants.map((v) => v.productId).toSet();

  test('newest products come first', () {
    expect(notifier.state.variants.first.productId, 'c');
  });

  test('selecting a category filters, and "Tous" brings everything back', () async {
    await notifier.selectCategory('c2');
    expect(ids(), {'c'});
    expect(notifier.state.selectedCategoryId, 'c2');

    await notifier.selectCategory('c1');
    expect(ids(), {'a', 'b'});

    await notifier.selectCategory(null);
    expect(notifier.state.selectedCategoryId, isNull);
    expect(ids(), {'a', 'b', 'c'});
  });

  test('tapping the active category again clears the filter', () async {
    await notifier.selectCategory('c1');
    await notifier.selectCategory('c1');
    expect(notifier.state.selectedCategoryId, isNull);
    expect(ids(), {'a', 'b', 'c'});
  });

  test('search respects the selected category', () async {
    await notifier.selectCategory('c1');
    await notifier.search('Produit');
    expect(ids(), {'a', 'b'});
  });

  test('a slow older request never overwrites the latest selection', () async {
    final first = notifier.selectCategory('c1');
    final second = notifier.selectCategory('c2');
    await Future.wait([first, second]);
    expect(notifier.state.selectedCategoryId, 'c2');
    expect(ids(), {'c'});
  });

  test('refresh shows changed stock', () async {
    int stockOfC() =>
        notifier.state.variants.firstWhere((v) => v.variantId == 'vc').stock;
    expect(stockOfC(), 0);

    await db.customStatement('PRAGMA foreign_keys = OFF;');
    await db.into(db.stockLevels).insert(StockLevelsCompanion.insert(
          id: 'sl',
          variantId: 'vc',
          locationId: 'loc',
          quantity: const Value(7),
          updatedAt: DateTime(2026, 10, 4),
        ));

    expect(stockOfC(), 0, reason: 'grid is stale until refreshed');
    await notifier.refresh();
    expect(stockOfC(), 7);
  });

  test('isTruncated is false for a small catalog', () {
    expect(notifier.state.isTruncated, isFalse);
  });
}
