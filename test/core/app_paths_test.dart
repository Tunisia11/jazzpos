import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/core/platform/app_paths.dart';
import 'package:tracepos/core/platform/windows_startup.dart';

void main() {
  group('AppPaths & Platform Storage', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tracepos_path_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'Initializes directory tree and passes storage health verification',
      () async {
        await AppPaths.instance.initialize(customBaseDir: tempDir);

        expect(await AppPaths.instance.databaseDir.exists(), isTrue);
        expect(await AppPaths.instance.logsDir.exists(), isTrue);
        expect(await AppPaths.instance.backupsDir.exists(), isTrue);
        expect(await AppPaths.instance.tempDir.exists(), isTrue);

        final health = await AppPaths.instance.verifyStorageHealth();
        expect(health['database'], isTrue);
        expect(health['logs'], isTrue);
        expect(health['backups'], isTrue);
        expect(health['temp'], isTrue);
      },
    );

    test(
      'WindowsStartup gracefully handles non-Windows platform without throwing',
      () async {
        final isEnabled = await WindowsStartup.isAutoStartEnabled();
        if (!Platform.isWindows) {
          expect(isEnabled, isFalse);
        }
      },
    );
  });
}
