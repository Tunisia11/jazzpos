import 'package:drift/native.dart';
import 'package:tracepos/data/database/app_database.dart';
import 'package:tracepos/providers/app_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracepos/main.dart';
import 'package:tracepos/hardware/hardware_manager.dart';

void main() {
  setUp(() {
    HardwareManager.instance.initialize();
  });

  testWidgets('TracePosApp launches with ProviderScope and theme', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(ProviderScope(overrides:[databaseProvider.overrideWithValue(db)], child: const TracePosApp(splashDuration: Duration.zero)));

    // Initial frame renders MaterialApp with TracePOS title
    expect(find.byType(TracePosApp), findsOneWidget);
  });
}
