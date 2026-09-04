import 'dart:typed_data';

/// Low-level ESC/POS thermal printer command builder
class EscPosCommands {
  static const int esc = 0x1B;
  static const int gs = 0x1D;
  static const int fs = 0x1C;
  static const int lf = 0x0A;

  /// Initialize printer
  static List<int> initialize() => [esc, 0x40];

  /// Alignment: 0 = Left, 1 = Center, 2 = Right
  static List<int> setAlign(int align) => [esc, 0x61, align];

  /// Emphasize / Bold: 1 = ON, 0 = OFF
  static List<int> setBold(bool enabled) => [esc, 0x45, enabled ? 1 : 0];

  /// Double size (height & width): 0x11 = double both, 0x00 = normal
  static List<int> setTextSize({bool doubleWidth = false, bool doubleHeight = false}) {
    int n = 0;
    if (doubleWidth) n |= 0x20;
    if (doubleHeight) n |= 0x01;
    return [gs, 0x21, n];
  }

  /// Line feed
  static List<int> feed([int lines = 1]) => List.filled(lines, lf);

  /// Partial paper cut
  static List<int> cutPaper() => [gs, 0x56, 0x42, 0x00];

  /// Full paper cut
  static List<int> cutPaperFull() => [gs, 0x56, 0x00];

  /// Cash drawer kick pulse on pin 2 (standard ESC p 0 25 250)
  static List<int> openCashDrawer() => [esc, 0x70, 0x00, 0x19, 0xFA];

  /// Print standard Code 128 barcode
  static List<int> printBarcode128(String barcode, {int height = 64, int width = 2}) {
    final bytes = <int>[];
    bytes.addAll([gs, 0x68, height]); // Height
    bytes.addAll([gs, 0x77, width]); // Width
    bytes.addAll([gs, 0x48, 0x02]); // HRI characters below barcode
    bytes.addAll([gs, 0x6B, 0x49, barcode.length + 2, 0x7B, 0x42]); // Code 128 subset B
    bytes.addAll(barcode.codeUnits);
    return bytes;
  }

  /// Format 2-column or 3-column text line for 58mm (32 chars) or 80mm (48 chars)
  static String formatColumns({
    required String left,
    required String right,
    int width = 48,
  }) {
    final totalLen = left.length + right.length;
    if (totalLen >= width) {
      final availableForLeft = width - right.length - 1;
      final truncatedLeft = availableForLeft > 0 ? left.substring(0, availableForLeft) : left;
      final spaces = width - truncatedLeft.length - right.length;
      return '$truncatedLeft${' ' * (spaces > 0 ? spaces : 1)}$right';
    }
    final spaces = width - left.length - right.length;
    return '$left${' ' * spaces}$right';
  }

  /// Format 3-column row: Item Name, Quantity x Price, Total
  static String formatThreeColumns({
    required String col1,
    required String col2,
    required String col3,
    int width = 48,
  }) {
    final col2Width = 14;
    final col3Width = 12;
    final col1Width = width - col2Width - col3Width;

    final c1 = col1.length > col1Width ? col1.substring(0, col1Width - 1) : col1.padRight(col1Width);
    final c2 = col2.padLeft(col2Width);
    final c3 = col3.padLeft(col3Width);

    return '$c1$c2$c3';
  }

  /// Build ESC/POS raster bit image commands (GS v 0) from monochrome bitmap pixels
  static Uint8List buildRasterImage({
    required Uint8List bitmapBytes,
    required int widthBytes,
    required int heightPixels,
  }) {
    final xL = widthBytes % 256;
    final xH = widthBytes ~/ 256;
    final yL = heightPixels % 256;
    final yH = heightPixels ~/ 256;

    final header = [gs, 0x76, 0x30, 0x00, xL, xH, yL, yH];
    final result = Uint8List(header.length + bitmapBytes.length);
    result.setRange(0, header.length, header);
    result.setRange(header.length, result.length, bitmapBytes);
    return result;
  }
}
