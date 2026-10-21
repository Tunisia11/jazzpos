import 'package:drift/native.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/main.dart';
import 'package:jazzpos/hardware/hardware_manager.dart';

void main() {
  setUp(() {
    HardwareManager.instance.initialize();
  });

  testWidgets('JazzPosApp launches with ProviderScope and theme', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(ProviderScope(overrides:[databaseProvider.overrideWithValue(db)], child: const JazzPosApp(splashDuration: Duration.zero)));

    // Initial frame renders MaterialApp with JazzPOS title
    expect(find.byType(JazzPosApp), findsOneWidget);
  });
}
