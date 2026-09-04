import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/core/utils/id_generator.dart';

/// An attribute selection for matrix generation (e.g. Color with values [Black, White])
class MatrixAttribute {
  final String attributeTypeId;
  final String attributeTypeName;
  final List<MatrixAttributeValue> selectedValues;

  const MatrixAttribute({
    required this.attributeTypeId,
    required this.attributeTypeName,
    required this.selectedValues,
  });
}

class MatrixAttributeValue {
  final String id;
  final String value;
  final String code;

  const MatrixAttributeValue({
    required this.id,
    required this.value,
    required this.code,
  });
}

/// A single variant generated from the matrix
class MatrixVariantItem {
  final String id;
  final Map<String, MatrixAttributeValue> selectedAttributes; // attributeTypeId -> value
  String sku;
  String barcode;
  Money costPrice;
  Money salePrice;
  int initialStock;
  int minStockAlert;
  bool isEnabled;

  MatrixVariantItem({
    required this.id,
    required this.selectedAttributes,
    required this.sku,
    required this.barcode,
    required this.costPrice,
    required this.salePrice,
    this.initialStock = 0,
    this.minStockAlert = 2,
    this.isEnabled = true,
  });

  String get attributeDescription {
    return selectedAttributes.values.map((v) => v.value).join(' / ');
  }
}

/// Fast Matrix Generator for clothing products
class VariantMatrixGenerator {
  /// Generate the full Cartesian product of variants from attributes
  static List<MatrixVariantItem> generateMatrix({
    required String productCode,
    required List<MatrixAttribute> attributes,
    required Money defaultCost,
    required Money defaultPrice,
  }) {
    if (attributes.isEmpty) return [];

    // Filter out attributes with no selected values
    final activeAttributes = attributes.where((a) => a.selectedValues.isNotEmpty).toList();
    if (activeAttributes.isEmpty) return [];

    List<Map<String, MatrixAttributeValue>> combinations = [{}];

    for (final attr in activeAttributes) {
      final List<Map<String, MatrixAttributeValue>> newCombinations = [];
      for (final existing in combinations) {
        for (final val in attr.selectedValues) {
          final copy = Map<String, MatrixAttributeValue>.from(existing);
          copy[attr.attributeTypeId] = val;
          newCombinations.add(copy);
        }
      }
      combinations = newCombinations;
    }

    final variants = <MatrixVariantItem>[];
    int counter = 1;

    for (final comb in combinations) {
      final codes = comb.values.map((v) => v.code).toList();
      final sku = IdGenerator.generateSku(
        productCode: productCode,
        colorCode: codes.isNotEmpty ? codes[0] : null,
        sizeCode: codes.length > 1 ? codes[1] : null,
        sequenceNumber: codes.length > 2 ? counter : null,
      );
      final barcode = IdGenerator.generateInternalBarcode();

      variants.add(
        MatrixVariantItem(
          id: IdGenerator.uuid(),
          selectedAttributes: comb,
          sku: sku,
          barcode: barcode,
          costPrice: defaultCost,
          salePrice: defaultPrice,
          initialStock: 0,
          minStockAlert: 2,
          isEnabled: true,
        ),
      );
      counter++;
    }

    return variants;
  }
}
