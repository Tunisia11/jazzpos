import 'package:jazzpos/hardware/receipt_printer/printer_candidate.dart';
import 'package:jazzpos/hardware/receipt_printer/printer_profile.dart';
import 'hardware_discovery_service.dart';

enum RecommendationConfidence {
  high, // Preselect and allow operator review
  medium, // Show recommendation and request selection
  low, // Do not auto-configure; manual selection required
}

class PeripheralRecommendation {
  final String peripheralType; // PRINTER, SCANNER, DRAWER, DISPLAY
  final String recommendedName;
  final String transport;
  final String details;
  final RecommendationConfidence confidence;
  final PrinterProfile? printerProfile;

  const PeripheralRecommendation({
    required this.peripheralType,
    required this.recommendedName,
    required this.transport,
    required this.details,
    required this.confidence,
    this.printerProfile,
  });

  Map<String, dynamic> toJson() => {
    'peripheralType': peripheralType,
    'recommendedName': recommendedName,
    'transport': transport,
    'details': details,
    'confidence': confidence.name,
    'profile': printerProfile?.id,
  };
}

class HardwareRecommendationBundle {
  final PeripheralRecommendation? receiptPrinter;
  final PeripheralRecommendation barcodeScanner;
  final PeripheralRecommendation cashDrawer;
  final PeripheralRecommendation customerDisplay;

  const HardwareRecommendationBundle({
    this.receiptPrinter,
    required this.barcodeScanner,
    required this.cashDrawer,
    required this.customerDisplay,
  });

  Map<String, dynamic> toJson() => {
    'receiptPrinter': receiptPrinter?.toJson(),
    'barcodeScanner': barcodeScanner.toJson(),
    'cashDrawer': cashDrawer.toJson(),
    'customerDisplay': customerDisplay.toJson(),
  };
}

/// Recommendation engine that analyzes system discovery reports and formulates
/// safe, non-binding hardware configuration recommendations.
class HardwareRecommendationEngine {
  /// Generate peripheral configuration recommendations based on discovery results
  static HardwareRecommendationBundle generateRecommendations(
    HardwareDiscoveryReport discovery,
  ) {
    // 1. Receipt Printer Recommendation
    PeripheralRecommendation? printerRec;
    final topPrinter = discovery.topPrinterCandidate;

    if (topPrinter != null) {
      RecommendationConfidence conf;
      if (topPrinter.confidence == PrinterConfidence.high) {
        conf = RecommendationConfidence.high;
      } else if (topPrinter.confidence == PrinterConfidence.likely) {
        conf = RecommendationConfidence.medium;
      } else {
        conf = RecommendationConfidence.low;
      }

      // Determine profile from name / evidence
      PrinterProfile profile = PrinterProfile.genericWindows;
      final upperName = topPrinter.name.toUpperCase();
      if (upperName.contains('POSBANK') || upperName.contains('APEXA')) {
        profile = PrinterProfile.posbank;
      } else if (upperName.contains('EPSON') || upperName.contains('TM-T')) {
        profile = PrinterProfile.epsonEscPos;
      } else if (upperName.contains('BIXOLON') || upperName.contains('SRP')) {
        profile = PrinterProfile.bixolon;
      } else if (upperName.contains('STAR') || upperName.contains('TSP')) {
        profile = PrinterProfile.star;
      } else if (topPrinter.paperCapabilities == '58mm') {
        profile = PrinterProfile.genericEscPos58;
      }

      printerRec = PeripheralRecommendation(
        peripheralType: 'PRINTER',
        recommendedName: topPrinter.name,
        transport: 'WINDOWS_SPOOLER',
        details:
            '${topPrinter.paperCapabilities} via Windows Spooler (${topPrinter.matchedEvidence ?? 'Detected'})',
        confidence: conf,
        printerProfile: profile,
      );
    }

    // 2. Barcode Scanner Recommendation (Universal USB HID / Keyboard Wedge)
    final scannerRec = const PeripheralRecommendation(
      peripheralType: 'SCANNER',
      recommendedName: 'Lecteur Code-barres USB HID (Clavier)',
      transport: 'KEYBOARD_WEDGE',
      details: 'Détection automatique rapide sans pilote requis (Plug & Play)',
      confidence: RecommendationConfidence.high,
    );

    // 3. Cash Drawer Recommendation
    PeripheralRecommendation drawerRec;
    if (printerRec != null &&
        (printerRec.printerProfile?.hasDrawerPort ?? true)) {
      drawerRec = PeripheralRecommendation(
        peripheralType: 'DRAWER',
        recommendedName: 'Tiroir connecté à l\'imprimante ticket',
        transport: 'THROUGH_PRINTER',
        details:
            'Impulsion électrique RJ11/RJ12 via ${printerRec.recommendedName} (Nécessite test)',
        confidence: RecommendationConfidence.medium,
      );
    } else {
      drawerRec = const PeripheralRecommendation(
        peripheralType: 'DRAWER',
        recommendedName: 'Désactivé',
        transport: 'DISABLED',
        details: 'Aucune imprimante avec port tiroir détectée',
        confidence: RecommendationConfidence.low,
      );
    }

    // 4. Customer Display Recommendation
    PeripheralRecommendation displayRec;
    if (discovery.displays.length > 1) {
      final secondary = discovery.displays.firstWhere((d) => !d.isPrimary);
      displayRec = PeripheralRecommendation(
        peripheralType: 'DISPLAY',
        recommendedName:
            'Deuxième Écran Client (${secondary.width}x${secondary.height})',
        transport: 'SECOND_MONITOR',
        details: 'Écran auxiliaire Windows détecté pour affichage des prix',
        confidence: RecommendationConfidence.high,
      );
    } else {
      displayRec = const PeripheralRecommendation(
        peripheralType: 'DISPLAY',
        recommendedName: 'Désactivé',
        transport: 'DISABLED',
        details: 'Aucun écran secondaire détecté',
        confidence: RecommendationConfidence.low,
      );
    }

    return HardwareRecommendationBundle(
      receiptPrinter: printerRec,
      barcodeScanner: scannerRec,
      cashDrawer: drawerRec,
      customerDisplay: displayRec,
    );
  }
}
