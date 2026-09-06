import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'esc_pos_commands.dart';

/// Utility to rasterize custom graphics, logos, and non-ASCII text (such as Arabic)
/// into 1-bit monochrome ESC/POS raster bit-images (GS v 0).
class ReceiptRasterizer {
  /// Converts an `img.Image` into raw 1-bit monochrome bitmap bytes suitable for ESC/POS `GS v 0`.
  /// [threshold] is the luminance cut-off (0-255) below which a pixel is considered black.
  static Uint8List imageToMonochromeBytes(
    img.Image image, {
    int threshold = 180,
  }) {
    // Width in bytes must be a multiple of 8
    final widthPixels = image.width;
    final widthBytes = (widthPixels + 7) ~/ 8;
    final heightPixels = image.height;

    final result = Uint8List(widthBytes * heightPixels);

    for (int y = 0; y < heightPixels; y++) {
      for (int x = 0; x < widthPixels; x++) {
        final pixel = image.getPixel(x, y);
        // Calculate grayscale luminance: Y = 0.299 R + 0.587 G + 0.114 B
        final r = pixel.r;
        final g = pixel.g;
        final b = pixel.b;
        final luminance = (r * 0.299 + g * 0.587 + b * 0.114).round();

        // 1 = black dot on paper, 0 = white paper
        if (luminance < threshold) {
          final byteIndex = y * widthBytes + (x ~/ 8);
          final bitPosition = 7 - (x % 8);
          result[byteIndex] |= (1 << bitPosition);
        }
      }
    }

    return result;
  }

  /// Builds a complete ESC/POS `GS v 0` raster command sequence from an `img.Image`.
  static Uint8List rasterizeImage(img.Image image, {int threshold = 180}) {
    // Ensure image width is padded to a byte multiple
    final widthPixels = image.width;
    final widthBytes = (widthPixels + 7) ~/ 8;
    final monoBytes = imageToMonochromeBytes(image, threshold: threshold);

    return EscPosCommands.buildRasterImage(
      bitmapBytes: monoBytes,
      widthBytes: widthBytes,
      heightPixels: image.height,
    );
  }

  /// Generates a test pattern raster image (576 pixels wide for 80mm paper)
  /// containing store header, divider, and graphic lines.
  static img.Image createTestRasterPattern({
    int width = 576,
    int height = 120,
    String text = 'JAZZ POS ARABIC / RASTER ENGINE',
  }) {
    final image = img.Image(width: width, height: height);
    // Fill white
    img.fill(image, color: img.ColorRgb8(255, 255, 255));

    // Draw top & bottom borders
    img.drawLine(
      image,
      x1: 0,
      y1: 10,
      x2: width - 1,
      y2: 10,
      color: img.ColorRgb8(0, 0, 0),
    );
    img.drawLine(
      image,
      x1: 0,
      y1: 14,
      x2: width - 1,
      y2: 14,
      color: img.ColorRgb8(0, 0, 0),
    );

    // Draw center test graphic
    img.drawCircle(
      image,
      x: width ~/ 2,
      y: height ~/ 2,
      radius: 30,
      color: img.ColorRgb8(0, 0, 0),
    );

    img.drawLine(
      image,
      x1: 0,
      y1: height - 12,
      x2: width - 1,
      y2: height - 12,
      color: img.ColorRgb8(0, 0, 0),
    );

    return image;
  }
}
