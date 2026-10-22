import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:tracepos/core/errors/failure.dart';
import 'package:tracepos/core/logging/pos_logger.dart';
import 'package:tracepos/core/platform/app_paths.dart';
import 'package:tracepos/data/database/app_database.dart';

/// Represents an image validated, normalized, and staged in a temporary directory
class StagedProductImage {
  final String stageId;
  final File mainFile;
  final File thumbFile;
  final String extension;
  final int width;
  final int height;
  final int fileSizeBytes;

  const StagedProductImage({
    required this.stageId,
    required this.mainFile,
    required this.thumbFile,
    required this.extension,
    required this.width,
    required this.height,
    required this.fileSizeBytes,
  });
}

enum ImageIntegrityStatus {
  valid,
  missingReferenced,
  orphanUnreferenced,
  corrupted,
}

class ImageIntegrityItem {
  final String relativePath;
  final String? productId;
  final String? variantId;
  final ImageIntegrityStatus status;
  final int fileSizeBytes;
  final String? errorMessage;

  const ImageIntegrityItem({
    required this.relativePath,
    this.productId,
    this.variantId,
    required this.status,
    required this.fileSizeBytes,
    this.errorMessage,
  });
}

class ImageIntegrityReport {
  final List<ImageIntegrityItem> items;
  final int totalManagedImages;
  final int totalSizeBytes;

  const ImageIntegrityReport({
    required this.items,
    required this.totalManagedImages,
    required this.totalSizeBytes,
  });

  int get validCount =>
      items.where((i) => i.status == ImageIntegrityStatus.valid).length;
  int get missingCount =>
      items.where((i) => i.status == ImageIntegrityStatus.missingReferenced).length;
  int get orphanCount =>
      items.where((i) => i.status == ImageIntegrityStatus.orphanUnreferenced).length;
  int get corruptedCount =>
      items.where((i) => i.status == ImageIntegrityStatus.corrupted).length;
}

class ProductImageService {
  final AppPaths? _appPathsOverride;
  static const int maxSourceSizeBytes = 20 * 1024 * 1024; // 20 MB limit
  static const int maxMainDimension = 1600;
  static const int maxThumbDimension = 320;
  static const List<String> supportedExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  ProductImageService({AppPaths? appPaths})
      : _appPathsOverride = appPaths;

  AppPaths get _paths => _appPathsOverride ?? AppPaths.instance;

  /// Open native file picker to select an image from the computer
  Future<XFile?> pickImage() async {
    const typeGroup = XTypeGroup(
      label: 'Images (*.jpg, *.jpeg, *.png, *.webp)',
      extensions: supportedExtensions,
      uniformTypeIdentifiers: [
        'public.image',
        'public.jpeg',
        'public.png',
      ],
    );
    try {
      return await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    } catch (e) {
      PosLogger.instance.warning(
        'ImageService',
        'openFile with typeGroup failed ($e), retrying openFile without filters...',
        e,
      );
      try {
        return await openFile();
      } catch (fallbackError, fallbackSt) {
        PosLogger.instance.error(
          'ImageService',
          'openFile fallback also failed: $fallbackError',
          fallbackError,
          fallbackSt,
        );
        rethrow;
      }
    }
  }

  /// Sanitize an ID (e.g. productId) to prevent directory traversal and invalid filename characters
  String sanitizeId(String id) {
    return id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
  }

  /// Validate file header magic bytes (JPEG, PNG, WebP)
  static bool isValidImageHeader(List<int> bytes) {
    if (bytes.length < 12) return false;
    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return true;
    }
    // WebP: RIFF .... WEBP
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    return false;
  }

  /// Validate, decode, normalize, and stage an image into a temporary directory.
  /// Returns a [StagedProductImage] ready to be committed upon product save.
  Future<StagedProductImage> stageImage(XFile file) async {
    final length = await file.length();
    if (length == 0) {
      throw const ValidationException('Le fichier image sélectionné est vide.');
    }
    if (length > maxSourceSizeBytes) {
      throw const ValidationException(
        'Image trop volumineuse. Veuillez sélectionner une image de moins de 20 Mo.',
      );
    }

    final ext = p.extension(file.path).replaceAll('.', '').toLowerCase();
    if (ext.isNotEmpty && !supportedExtensions.contains(ext)) {
      throw ValidationException(
        'Format d\'image non supporté: $ext. Formats acceptés : JPG, JPEG, PNG, WebP.',
      );
    }

    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      throw PosException('Impossible de lire le fichier image sélectionné : $e');
    }

    // Decode and validate using the Dart image package
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (e) {
      throw ValidationException('Format d\'image non reconnu ou corrompu : $e');
    }

    if (decoded == null) {
      throw const ValidationException(
        'Format d\'image non reconnu ou corrompu (JPG, PNG, WebP acceptés).',
      );
    }

    // Auto-rotate according to EXIF orientation metadata
    final baked = img.bakeOrientation(decoded);

    // 1. Generate Main Image (max 1600px longest side, preserve aspect ratio)
    img.Image mainImage = baked;
    if (baked.width > maxMainDimension || baked.height > maxMainDimension) {
      if (baked.width >= baked.height) {
        mainImage = img.copyResize(
          baked,
          width: maxMainDimension,
          interpolation: img.Interpolation.linear,
        );
      } else {
        mainImage = img.copyResize(
          baked,
          height: maxMainDimension,
          interpolation: img.Interpolation.linear,
        );
      }
    }

    // 2. Generate Thumbnail (max 320px longest side)
    img.Image thumbImage = baked;
    if (baked.width > maxThumbDimension || baked.height > maxThumbDimension) {
      if (baked.width >= baked.height) {
        thumbImage = img.copyResize(
          baked,
          width: maxThumbDimension,
          interpolation: img.Interpolation.linear,
        );
      } else {
        thumbImage = img.copyResize(
          baked,
          height: maxThumbDimension,
          interpolation: img.Interpolation.linear,
        );
      }
    }

    // Encode bytes: preserve alpha transparency if source has alpha
    final bool preserveAlpha = baked.hasAlpha;
    final String targetExt = preserveAlpha ? 'png' : 'jpg';
    final Uint8List mainBytes = preserveAlpha
        ? Uint8List.fromList(img.encodePng(mainImage))
        : Uint8List.fromList(img.encodeJpg(mainImage, quality: 85));
    final Uint8List thumbBytes = preserveAlpha
        ? Uint8List.fromList(img.encodePng(thumbImage))
        : Uint8List.fromList(img.encodeJpg(thumbImage, quality: 80));

    final stageId = const Uuid().v4();
    final stageDir = Directory(p.join(_paths.stagedImagesDir.path, stageId));
    await stageDir.create(recursive: true);

    final mainFile = File(p.join(stageDir.path, 'main.$targetExt'));
    final thumbFile = File(p.join(stageDir.path, 'thumb.$targetExt'));

    await mainFile.writeAsBytes(mainBytes, flush: true);
    await thumbFile.writeAsBytes(thumbBytes, flush: true);

    PosLogger.instance.info(
      'ImageService',
      'Staged product image $stageId: ${mainImage.width}x${mainImage.height} ($targetExt, ${(mainBytes.length / 1024).toStringAsFixed(1)} KB)',
    );

    return StagedProductImage(
      stageId: stageId,
      mainFile: mainFile,
      thumbFile: thumbFile,
      extension: targetExt,
      width: mainImage.width,
      height: mainImage.height,
      fileSizeBytes: mainBytes.length,
    );
  }

  /// Clean staged temporary image files (e.g. on form cancel or failure)
  Future<void> cleanStagedImage(StagedProductImage? staged) async {
    if (staged == null) return;
    try {
      final stageDir = staged.mainFile.parent;
      if (await stageDir.exists()) {
        await stageDir.delete(recursive: true);
      }
    } catch (e) {
      PosLogger.instance.warning('ImageService', 'Could not clean staged dir: $e');
    }
  }

  /// Atomically commit a staged image to the managed product storage.
  /// Writes to a temporary file first, then renames, ensuring atomic write safety.
  /// Cleans up any previous image if different, and deletes the staged temp folder.
  /// Returns the canonical relative database path (e.g. `images/products/<productId>/main.jpg`).
  Future<String> commitProductImage({
    required String productId,
    required StagedProductImage staged,
    String? previousImagePath,
  }) async {
    final cleanId = sanitizeId(productId);
    final targetDir = Directory(p.join(_paths.productImagesDir.path, cleanId));
    await targetDir.create(recursive: true);

    final ext = staged.extension;
    final mainTarget = File(p.join(targetDir.path, 'main.$ext'));
    final thumbTarget = File(p.join(targetDir.path, 'thumb.$ext'));

    final mainTmp = File(p.join(targetDir.path, 'main.$ext.tmp'));
    final thumbTmp = File(p.join(targetDir.path, 'thumb.$ext.tmp'));

    try {
      // 1. Copy staged files to temporary targets
      await staged.mainFile.copy(mainTmp.path);
      await staged.thumbFile.copy(thumbTmp.path);

      // 2. Atomic replacement
      if (await mainTarget.exists()) await mainTarget.delete();
      if (await thumbTarget.exists()) await thumbTarget.delete();

      await mainTmp.rename(mainTarget.path);
      await thumbTmp.rename(thumbTarget.path);

      // 3. Clean any alternate extension files in targetDir (e.g. if previous was .png and now is .jpg)
      final entities = await targetDir.list().toList();
      for (final entity in entities) {
        if (entity is File &&
            entity.path != mainTarget.path &&
            entity.path != thumbTarget.path) {
          try {
            await entity.delete();
          } catch (e) { PosLogger.instance.warning('product_image_service', 'Ignored error: $e'); }
        }
      }

      // 4. Clean previous image if it was in an older or legacy directory
      if (previousImagePath != null && previousImagePath.isNotEmpty) {
        final resolvedPrev = _paths.resolveImagePath(previousImagePath);
        if (resolvedPrev != null &&
            resolvedPrev != mainTarget.path &&
            await File(resolvedPrev).exists()) {
          try {
            await File(resolvedPrev).delete();
          } catch (e) { PosLogger.instance.warning('product_image_service', 'Ignored error: $e'); }
        }
      }

      // 5. Clean staged temporary directory
      await cleanStagedImage(staged);

      final relPath = 'images/products/$cleanId/main.$ext';
      PosLogger.instance.info(
        'ImageService',
        'Committed product image for $cleanId -> $relPath',
      );
      return relPath;
    } catch (e) {
      // Rollback temporary files on write failure
      if (await mainTmp.exists()) await mainTmp.delete();
      if (await thumbTmp.exists()) await thumbTmp.delete();
      throw PosException('Erreur lors de l\'enregistrement de l\'image produit : $e');
    }
  }

  /// Remove managed image files for a product
  Future<void> removeProductImage(String productId) async {
    final cleanId = sanitizeId(productId);
    final targetDir = Directory(p.join(_paths.productImagesDir.path, cleanId));
    try {
      if (await targetDir.exists()) {
        await targetDir.delete(recursive: true);
        PosLogger.instance.info(
          'ImageService',
          'Removed managed images directory for product $cleanId',
        );
      }
    } catch (e) {
      PosLogger.instance.warning(
        'ImageService',
        'Could not remove image directory for product $cleanId: $e',
      );
    }
  }

  /// Direct save convenience method (stages then commits immediately)
  Future<String> saveProductImage({
    required XFile file,
    required String productId,
    String? previousImagePath,
  }) async {
    final staged = await stageImage(file);
    return await commitProductImage(
      productId: productId,
      staged: staged,
      previousImagePath: previousImagePath,
    );
  }

  /// Delete image file by path
  Future<void> deleteImageFile(String? imagePath) async {
    if (imagePath == null || imagePath.trim().isEmpty) return;
    try {
      final resolved = _paths.resolveImagePath(imagePath);
      if (resolved != null) {
        final f = File(resolved);
        if (await f.exists()) {
          final parent = f.parent;
          await f.delete();
          // Also delete sibling thumb if exists
          for (final ext in ['jpg', 'png', 'webp', 'jpeg']) {
            final t = File(p.join(parent.path, 'thumb.$ext'));
            if (await t.exists()) await t.delete();
          }
          // If directory is now empty, delete directory
          if (await parent.exists() && (await parent.list().isEmpty)) {
            await parent.delete();
          }
        }
      }
    } catch (e) {
      PosLogger.instance.warning('ImageService', 'Could not delete image $imagePath: $e');
    }
  }

  /// Resolve thumbnail path: looks for `thumb.*` in the same directory as `mainImagePath`.
  /// Falls back to main image if thumbnail is absent, or null if neither exists.
  String? resolveThumbnailPath(String? imagePath) {
    if (imagePath == null || imagePath.trim().isEmpty) return null;
    final resolvedMain = _paths.resolveImagePath(imagePath);
    if (resolvedMain == null) return null;

    final dir = p.dirname(resolvedMain);
    // Check for sibling thumb with common extensions
    for (final ext in ['jpg', 'png', 'webp', 'jpeg']) {
      final thumbCandidate = p.join(dir, 'thumb.$ext');
      if (File(thumbCandidate).existsSync()) {
        return thumbCandidate;
      }
    }

    return resolvedMain;
  }

  /// Scan storage integrity comparing SQLite records with filesystem assets
  Future<ImageIntegrityReport> scanImageIntegrity(AppDatabase db) async {
    final items = <ImageIntegrityItem>[];
    int totalManaged = 0;
    int totalBytes = 0;

    // 1. Gather all active image references from DB
    final allProducts = await (db.select(db.products)
          ..where((t) => t.imageUrl.isNotNull()))
        .get();
    final products = allProducts
        .where((p) => p.imageUrl != null && p.imageUrl!.trim().isNotEmpty)
        .toList();

    final allVariants = await (db.select(db.productVariants)
          ..where((t) => t.imageUrl.isNotNull()))
        .get();
    final variants = allVariants
        .where((v) => v.imageUrl != null && v.imageUrl!.trim().isNotEmpty)
        .toList();

    final referencedRelativePaths = <String, (String? prodId, String? varId)>{};
    for (final pRow in products) {
      if (pRow.imageUrl != null) {
        referencedRelativePaths[pRow.imageUrl!.replaceAll(r'\', '/')] =
            (pRow.id, null);
      }
    }
    for (final vRow in variants) {
      if (vRow.imageUrl != null) {
        final key = vRow.imageUrl!.replaceAll(r'\', '/');
        if (!referencedRelativePaths.containsKey(key)) {
          referencedRelativePaths[key] = (vRow.productId, vRow.id);
        }
      }
    }

    // 2. Check each DB reference against filesystem
    final verifiedDiskPaths = <String>{};
    for (final entry in referencedRelativePaths.entries) {
      final rel = entry.key;
      final (prodId, varId) = entry.value;
      final resolved = _paths.resolveImagePath(rel);

      if (resolved == null || !File(resolved).existsSync()) {
        items.add(
          ImageIntegrityItem(
            relativePath: rel,
            productId: prodId,
            variantId: varId,
            status: ImageIntegrityStatus.missingReferenced,
            fileSizeBytes: 0,
            errorMessage: 'Fichier introuvable sur le disque',
          ),
        );
      } else {
        verifiedDiskPaths.add(p.canonicalize(resolved));
        final file = File(resolved);
        final size = file.lengthSync();
        totalBytes += size;
        totalManaged++;

        bool isCorrupted = false;
        String? corruptReason;
        if (size < 12) {
          isCorrupted = true;
          corruptReason = 'Fichier vide ou trop petit';
        } else {
          try {
            final raf = file.openSync();
            final headerBytes = raf.readSync(12);
            raf.closeSync();
            if (!isValidImageHeader(headerBytes)) {
              isCorrupted = true;
              corruptReason = 'Entête de fichier image non reconnu ou corrompu';
            }
          } catch (e) {
            isCorrupted = true;
            corruptReason = 'Erreur de lecture du fichier: $e';
          }
        }

        if (isCorrupted) {
          items.add(
            ImageIntegrityItem(
              relativePath: rel,
              productId: prodId,
              variantId: varId,
              status: ImageIntegrityStatus.corrupted,
              fileSizeBytes: size,
              errorMessage: corruptReason,
            ),
          );
        } else {
          items.add(
            ImageIntegrityItem(
              relativePath: rel,
              productId: prodId,
              variantId: varId,
              status: ImageIntegrityStatus.valid,
              fileSizeBytes: size,
            ),
          );
        }
      }
    }

    // 3. Scan managed product images directory for orphan files
    final rootDir = _paths.productImagesDir;
    if (await rootDir.exists()) {
      await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final canonical = p.canonicalize(entity.path);
          if (!verifiedDiskPaths.contains(canonical) &&
              !entity.path.endsWith('.tmp')) {
            // Check if it's a thumbnail of a verified main image
            final isThumbOfVerified = verifiedDiskPaths.any((v) {
              final vDir = p.normalize(p.dirname(v)).toLowerCase();
              final cDir = p.normalize(p.dirname(canonical)).toLowerCase();
              final cBase = p.basename(canonical).toLowerCase();
              return cDir == vDir && cBase.startsWith('thumb.');
            });

            if (!isThumbOfVerified) {
              final rel = _paths.toRelativeImagePath(entity.path);
              final size = entity.lengthSync();
              totalBytes += size;
              totalManaged++;
              items.add(
                ImageIntegrityItem(
                  relativePath: rel,
                  status: ImageIntegrityStatus.orphanUnreferenced,
                  fileSizeBytes: size,
                  errorMessage: 'Fichier orphelin non référencé dans la base',
                ),
              );
            }
          }
        }
      }
    }

    return ImageIntegrityReport(
      items: items,
      totalManagedImages: totalManaged,
      totalSizeBytes: totalBytes,
    );
  }

  /// Clean up unreferenced orphan files safely. Never deletes referenced images.
  Future<int> cleanupOrphans(AppDatabase db) async {
    final report = await scanImageIntegrity(db);
    int deleted = 0;
    for (final item in report.items) {
      if (item.status == ImageIntegrityStatus.orphanUnreferenced) {
        final resolved = _paths.resolveImagePath(item.relativePath);
        if (resolved != null) {
          try {
            final f = File(resolved);
            if (await f.exists()) {
              await f.delete();
              deleted++;
            }
          } catch (e) {
            PosLogger.instance.warning(
              'ImageService',
              'Could not delete orphan ${item.relativePath}: $e',
            );
          }
        }
      }
    }
    PosLogger.instance.info('ImageService', 'Cleaned up $deleted orphan image files');
    return deleted;
  }
}

