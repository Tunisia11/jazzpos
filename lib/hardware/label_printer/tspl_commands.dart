import 'label_document.dart';

/// TSPL / TSPL2 command generator for TSC, XPrinter, and compatible label printers
class TsplCommands {
  static String buildLabel(LabelDocument doc) {
    final buffer = StringBuffer();

    // Setup dimensions and paper gap
    buffer.writeln('SIZE ${doc.widthMm} mm, ${doc.heightMm} mm');
    buffer.writeln('GAP 2 mm, 0');
    buffer.writeln('DIRECTION 1');
    buffer.writeln('CLS');

    // Store Name
    buffer.writeln('TEXT 20, 15, "2", 0, 1, 1, "${doc.storeName.toUpperCase()}"');

    // Brand and Collection if available
    if (doc.brandName != null && doc.brandName!.isNotEmpty) {
      buffer.writeln('TEXT 20, 35, "1", 0, 1, 1, "${doc.brandName}"');
    }

    // Product Name (truncated to 20 chars if needed)
    final prodName = doc.productName.length > 22 ? doc.productName.substring(0, 22) : doc.productName;
    buffer.writeln('TEXT 20, 55, "2", 0, 1, 1, "$prodName"');

    // Color & Size
    final variantDesc = doc.variantTag;
    if (variantDesc.isNotEmpty) {
      buffer.writeln('TEXT 20, 80, "2", 0, 1, 1, "$variantDesc"');
    }

    // Barcode (Code 128)
    buffer.writeln('BARCODE 20, 105, "128", 45, 1, 0, 2, 2, "${doc.barcode}"');

    // SKU
    buffer.writeln('TEXT 20, 155, "1", 0, 1, 1, "${doc.sku}"');

    // Price in TND (Big and Bold)
    buffer.writeln('TEXT 180, 150, "3", 0, 1, 1, "${doc.price.format()}"');

    // Old price if promotion / sale
    if (doc.oldPrice != null) {
      buffer.writeln('TEXT 180, 130, "1", 0, 1, 1, "Av: ${doc.oldPrice!.format()}"');
    }

    // Print command: PRINT copies, 1
    buffer.writeln('PRINT ${doc.copies}, 1\n');

    return buffer.toString();
  }
}
