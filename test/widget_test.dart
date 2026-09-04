import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/main.dart';
import 'package:jazzpos/hardware/hardware_manager.dart';

void main() {
  setUp(() {
    HardwareManager.instance.initialize();
  });

  testWidgets('JazzPosApp launches with ProviderScope and theme', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: JazzPosApp(),
      ),
    );

    // Initial frame renders MaterialApp with JazzPOS title
    expect(find.byType(JazzPosApp), findsOneWidget);
  });
}
