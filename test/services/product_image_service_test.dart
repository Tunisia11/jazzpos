import 'dart:io';
import 'dart:typed_data';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/platform/app_paths.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/product_image_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempBaseDir;
  late ProductImageService service;
  late AppDatabase db;

  setUp(() async {
    tempBaseDir = await Directory.systemTemp.createTemp('jazzpos_img_test_');
    await AppPaths.instance.initialize(customBaseDir: tempBaseDir);
    service = ProductImageService();
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    if (await tempBaseDir.exists()) {
      await tempBaseDir.delete(recursive: true);
    }
  });

  group('ProductImageService - Staging & Normalization', () {
    test('Downscales large image <= 1600px main and <= 320px thumb', () async {
      // Create a 2000x1200 image
      final source = img.Image(width: 2000, height: 1200);
      img.fill(source, color: img.ColorRgb8(255, 0, 0));
      final jpgBytes = img.encodeJpg(source);

      final tempInput = File(p.join(tempBaseDir.path, 'large_sample.jpg'));
      await tempInput.writeAsBytes(jpgBytes);

      final staged = await service.stageImage(XFile(tempInput.path));
      expect(staged.width, 1600);
      expect(staged.height, 960);
      expect(staged.extension, 'jpg');
      expect(await staged.mainFile.exists(), isTrue);
      expect(await staged.thumbFile.exists(), isTrue);

      // Verify decoded thumb dimension
      final thumbBytes = await staged.thumbFile.readAsBytes();
      final decodedThumb = img.decodeImage(thumbBytes)!;
      expect(decodedThumb.width, lessThanOrEqualTo(320));
      expect(decodedThumb.height, lessThanOrEqualTo(320));

      await service.cleanStagedImage(staged);
      expect(await staged.mainFile.exists(), isFalse);
    });

    test('Preserves alpha transparency by encoding as PNG', () async {
      // Create an RGBA image with transparent pixels
      final source = img.Image(width: 400, height: 400, numChannels: 4);
      // Half transparent, half green
      for (int y = 0; y < 200; y++) {
        for (int x = 0; x < 400; x++) {
          source.setPixel(x, y, img.ColorRgba8(0, 255, 0, 128));
        }
      }
      final pngBytes = img.encodePng(source);

      final tempInput = File(p.join(tempBaseDir.path, 'transparent.png'));
      await tempInput.writeAsBytes(pngBytes);

      final staged = await service.stageImage(XFile(tempInput.path));
      expect(staged.extension, 'png');
      expect(staged.mainFile.path.endsWith('.png'), isTrue);

      await service.cleanStagedImage(staged);
    });

    test('Encodes opaque images as JPG for storage efficiency', () async {
      final source = img.Image(width: 500, height: 500, numChannels: 3);
      img.fill(source, color: img.ColorRgb8(0, 0, 255));
      final pngBytes = img.encodePng(source);

      final tempInput = File(p.join(tempBaseDir.path, 'opaque.png'));
      await tempInput.writeAsBytes(pngBytes);

      final staged = await service.stageImage(XFile(tempInput.path));
      expect(staged.extension, 'jpg');
      expect(staged.mainFile.path.endsWith('.jpg'), isTrue);

      await service.cleanStagedImage(staged);
    });

    test('Rejects corrupt or non-image files with ValidationException', () async {
      final corruptFile = File(p.join(tempBaseDir.path, 'corrupt.jpg'));
      await corruptFile.writeAsString('Definitely not an image file content');

      expect(
        () => service.stageImage(XFile(corruptFile.path)),
        throwsA(isA<ValidationException>()),
      );
    });

    test('Rejects files exceeding 20MB limit', () async {
      final largeFile = File(p.join(tempBaseDir.path, 'oversized.jpg'));
      // Write sparse or simulated oversized file
      final sink = largeFile.openWrite();
      sink.add(Uint8List(21 * 1024 * 1024)); // 21 MB
      await sink.close();

      expect(
        () => service.stageImage(XFile(largeFile.path)),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('ProductImageService - Commit & Storage', () {
    test('Atomically commits staged image to managed storage', () async {
      final source = img.Image(width: 400, height: 400);
      img.fill(source, color: img.ColorRgb8(100, 150, 200));
      final sampleFile = File(p.join(tempBaseDir.path, 'item.jpg'));
      await sampleFile.writeAsBytes(img.encodeJpg(source));

      final staged = await service.stageImage(XFile(sampleFile.path));
      final stagedMainPath = staged.mainFile.path;

      final relPath = await service.commitProductImage(
        productId: 'prod_123',
        staged: staged,
      );

      expect(relPath, 'images/products/prod_123/main.jpg');

      final resolved = AppPaths.instance.resolveImagePath(relPath);
      expect(resolved, isNotNull);
      expect(await File(resolved!).exists(), isTrue);

      // Verify thumb sibling exists
      final thumbPath = p.join(p.dirname(resolved), 'thumb.jpg');
      expect(await File(thumbPath).exists(), isTrue);

      // Staging directory should be cleaned
      expect(await File(stagedMainPath).exists(), isFalse);
    });

    test('Removes managed product image directory', () async {
      final source = img.Image(width: 200, height: 200);
      img.fill(source, color: img.ColorRgb8(50, 50, 50));
      final sampleFile = File(p.join(tempBaseDir.path, 'sample2.jpg'));
      await sampleFile.writeAsBytes(img.encodeJpg(source));

      final staged = await service.stageImage(XFile(sampleFile.path));
      final relPath = await service.commitProductImage(
        productId: 'prod_to_delete',
        staged: staged,
      );

      final resolved = AppPaths.instance.resolveImagePath(relPath)!;
      expect(await File(resolved).exists(), isTrue);

      await service.removeProductImage('prod_to_delete');
      expect(await File(resolved).exists(), isFalse);
    });
  });

  group('ProductImageService - Integrity Scanner & Orphan Cleanup', () {
    test('Detects valid, missing, orphan, and corrupted images', () async {
      // 1. Create a valid product and its managed image
      final sampleImg = img.Image(width: 100, height: 100);
      final sampleFile = File(p.join(tempBaseDir.path, 'valid.jpg'));
      await sampleFile.writeAsBytes(img.encodeJpg(sampleImg));
      final staged = await service.stageImage(XFile(sampleFile.path));
      final validRelPath = await service.commitProductImage(
        productId: 'prod_valid',
        staged: staged,
      );

      final now = DateTime.now();
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'prod_valid',
          name: 'Valid Product',
          imageUrl: drift.Value(validRelPath),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // 2. Create product referencing a missing image
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'prod_missing',
          name: 'Missing Image Product',
          imageUrl: const drift.Value('images/products/prod_missing/main.jpg'),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // 3. Create an orphan image file on disk (not referenced in db)
      final orphanDir = Directory(
        p.join(AppPaths.instance.productImagesDir.path, 'prod_orphan'),
      );
      await orphanDir.create(recursive: true);
      final orphanFile = File(p.join(orphanDir.path, 'main.jpg'));
      await orphanFile.writeAsBytes(img.encodeJpg(sampleImg));

      // 4. Create a corrupted image file on disk referenced in db
      final corruptDir = Directory(
        p.join(AppPaths.instance.productImagesDir.path, 'prod_corrupt'),
      );
      await corruptDir.create(recursive: true);
      final corruptFile = File(p.join(corruptDir.path, 'main.jpg'));
      await corruptFile.writeAsString('not a valid image content');

      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'prod_corrupt',
          name: 'Corrupt Image Product',
          imageUrl: const drift.Value('images/products/prod_corrupt/main.jpg'),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Run scanner
      final report = await service.scanImageIntegrity(db);
      expect(report.validCount, 1);
      expect(report.missingCount, 1);
      expect(report.orphanCount, 1);
      expect(report.corruptedCount, 1);

      // Run cleanup orphans
      final cleanedCount = await service.cleanupOrphans(db);
      expect(cleanedCount, 1);
      expect(await orphanFile.exists(), isFalse);

      // Valid and corrupt still exist on disk (corrupt is referenced, not orphan)
      expect(await File(AppPaths.instance.resolveImagePath(validRelPath)!).exists(), isTrue);
      expect(await corruptFile.exists(), isTrue);
    });
  });

  group('ProductImageService - Security & Path Traversal', () {
    test('AppPaths.resolveImagePath rejects path traversal attempts', () {
      expect(AppPaths.instance.resolveImagePath('../secret.txt'), isNull);
      expect(AppPaths.instance.resolveImagePath('../../windows/system32'), isNull);
      expect(AppPaths.instance.resolveImagePath('images/products/../../passwords'), isNull);
      expect(AppPaths.instance.resolveImagePath('C:\\Windows\\System32\\cmd.exe'), isNull);
      expect(AppPaths.instance.resolveImagePath('/etc/passwd'), isNull);
    });
  });
}
