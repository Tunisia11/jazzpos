import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/core/platform/app_paths.dart';
import 'package:tracepos/core/sound/sound_effect_service.dart';
import 'package:tracepos/ui/widgets/numpad.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('pos_sound_test_');
    await AppPaths.instance.initialize(customBaseDir: tempDir);
    await SoundEffectService.instance.initialize();
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('SoundEffectService', () {
    test('sound assets are generated and cached in temp directory', () async {
      final soundDir = Directory('${AppPaths.instance.tempDir.path}/pos_sounds');
      expect(await soundDir.exists(), isTrue);

      final files = soundDir.listSync().whereType<File>().toList();
      final fileNames = files.map((f) => f.uri.pathSegments.last).toSet();

      expect(fileNames.contains('key_tap.wav'), isTrue);
      expect(fileNames.contains('button_tap.wav'), isTrue);
      expect(fileNames.contains('backspace.wav'), isTrue);
      expect(fileNames.contains('clear.wav'), isTrue);
      expect(fileNames.contains('success.wav'), isTrue);
      expect(fileNames.contains('error.wav'), isTrue);
    });

    test('generated WAV files contain valid RIFF headers', () async {
      final keyTap = File('${AppPaths.instance.tempDir.path}/pos_sounds/key_tap.wav');
      final bytes = await keyTap.readAsBytes();

      expect(bytes.length, greaterThan(44));
      // "RIFF"
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      // "WAVE"
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      // "fmt "
      expect(String.fromCharCodes(bytes.sublist(12, 16)), 'fmt ');
      // "data"
      expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data');
    });

    test('sound effect methods execute without throwing', () {
      final sound = SoundEffectService.instance;
      sound.isEnabled = true;

      expect(() => sound.playKeyTap(), returnsNormally);
      expect(() => sound.playButtonTap(), returnsNormally);
      expect(() => sound.playBackspace(), returnsNormally);
      expect(() => sound.playClear(), returnsNormally);
      expect(() => sound.playSuccess(), returnsNormally);
      expect(() => sound.playError(), returnsNormally);
    });

    test('sound effects respect isEnabled toggle', () {
      final sound = SoundEffectService.instance;

      sound.isEnabled = false;
      expect(sound.isEnabled, isFalse);
      expect(() => sound.playKeyTap(), returnsNormally);
      expect(() => sound.playSuccess(), returnsNormally);

      sound.isEnabled = true;
      expect(sound.isEnabled, isTrue);
      expect(() => sound.playKeyTap(), returnsNormally);
    });

    testWidgets('Numpad tapping invokes audio callback without crashing', (tester) async {
      String lastPressed = '';
      bool backspaced = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Numpad(
              onKeyPress: (k) => lastPressed = k,
              onBackspace: () => backspaced = true,
              onClear: () {},
            ),
          ),
        ),
      );

      // Tap key '5'
      await tester.tap(find.text('5'));
      await tester.pump();
      expect(lastPressed, '5');

      // Tap backspace
      await tester.tap(find.text('⌫'));
      await tester.pump();
      expect(backspaced, isTrue);

      // Tap '00'
      await tester.tap(find.text('00'));
      await tester.pump();
      expect(lastPressed, '00');
    });
  });
}
