import 'label_document.dart';

/// ZPL (Zebra Programming Language) command generator
class ZplCommands {
  static String buildLabel(LabelDocument doc) {
    final buffer = StringBuffer();
    buffer.writeln('^XA'); // Start format

    // Store Name
    buffer.writeln('^FO20,15^A0N,20,20^FD${doc.storeName.toUpperCase()}^FS');

    // Product Name
    final prodName = doc.productName.length > 22 ? doc.productName.substring(0, 22) : doc.productName;
    buffer.writeln('^FO20,40^A0N,22,22^FD$prodName^FS');

    // Size & Color
    final variantDesc = doc.variantTag;
    if (variantDesc.isNotEmpty) {
      buffer.writeln('^FO20,68^A0N,20,20^FD$variantDesc^FS');
    }

    // Code 128 Barcode
    buffer.writeln('^FO20,95^BY2,2,45^BCN,45,Y,N,N^FD${doc.barcode}^FS');

    // Price in TND
    buffer.writeln('^FO180,150^A0N,28,28^FD${doc.price.format()}^FS');

    // Copies
    buffer.writeln('^PQ${doc.copies},0,1,Y');
    buffer.writeln('^XZ'); // End format

    return buffer.toString();
  }
}
