import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/platform/app_paths.dart';

class ProductImageService {
  /// Open native file picker to select an image from the computer
  Future<XFile?> pickImage() async {
    const typeGroup = XTypeGroup(
      label: 'Images (*.jpg, *.jpeg, *.png, *.webp)',
      extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
    );
    return await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
  }

  /// Process, downscale/compress, and persist product image into local storage
  Future<String> saveProductImage({
    required XFile file,
    required String productId,
  }) async {
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      throw PosException('Impossible de lire le fichier image sélectionné: $e');
    }

    if (bytes.isEmpty) {
      throw const ValidationException('Le fichier image sélectionné est vide');
    }

    // Decode and validate using the Dart image package
    final img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (e) {
      throw PosException('Format d\'image non reconnu ou corrompu: $e');
    }

    if (decoded == null) {
      throw const ValidationException(
        'Format d\'image invalide ou non supporté. Formats acceptés : PNG, JPG, JPEG, WebP.',
      );
    }

    // Downscale if image is larger than 800px on its longest side
    img.Image processed = decoded;
    const maxDimension = 800;
    if (decoded.width > maxDimension || decoded.height > maxDimension) {
      if (decoded.width >= decoded.height) {
        processed = img.copyResize(
          decoded,
          width: maxDimension,
          interpolation: img.Interpolation.linear,
        );
      } else {
        processed = img.copyResize(
          decoded,
          height: maxDimension,
          interpolation: img.Interpolation.linear,
        );
      }
    }

    // Encode as optimized JPEG (quality 85)
    final Uint8List compressedBytes = Uint8List.fromList(
      img.encodeJpg(processed, quality: 85),
    );

    // Guarantee images directory exists
    final imagesDir = AppPaths.instance.imagesDir;
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    // Create target file name
    final fileName =
        'prod_${productId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final targetPath = p.join(imagesDir.path, fileName);
    final targetFile = File(targetPath);

    await targetFile.writeAsBytes(compressedBytes, flush: true);
    PosLogger.instance.info(
      'ImageService',
      'Saved product image: $fileName (${(compressedBytes.length / 1024).toStringAsFixed(1)} KB)',
    );

    return targetPath;
  }

  /// Delete an image file from local storage safely
  Future<void> deleteImageFile(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return;
    try {
      final file = File(imagePath);
      if (await file.exists()) {
        await file.delete();
        PosLogger.instance.info(
          'ImageService',
          'Deleted old image: $imagePath',
        );
      }
    } catch (e) {
      PosLogger.instance.warning(
        'ImageService',
        'Could not delete image $imagePath: $e',
      );
    }
  }
}
