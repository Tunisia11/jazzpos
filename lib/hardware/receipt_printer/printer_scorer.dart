import 'printer_candidate.dart';

/// Evaluates and scores system printer entries to detect likely thermal receipt POS printers.
class PrinterScorer {
  /// Known POS thermal receipt manufacturers and brand keywords
  static const List<String> posBrands = [
    'POSBANK',
    'EPSON',
    'TM-T',
    'TM-M',
    'BIXOLON',
    'SRP-',
    'STAR',
    'TSP',
    'CITIZEN',
    'XPRINTER',
    'XP-',
    'RONGTA',
    'RP',
    'SNBC',
    'BTP-',
    'SEWOO',
    'SLK-',
    'SUNMI',
    'METAPACE',
    'DATALOGIC',
    'ZEBRA',
    'APEXA',
    'ANYPOS',
  ];

  /// POS thermal keywords
  static const List<String> posKeywords = [
    'THERMAL',
    'RECEIPT',
    'TICKET',
    'POS',
    'ESC/POS',
    'ESCPOS',
    'RECU',
    'REÇU',
    'CAISSE',
    '80MM',
    '58MM',
    'FACTURE',
    'BILL',
    'SRP',
    'TM-T',
    'TM-M',
    'TSP',
    'GENERIC / TEXT ONLY',
    'GENERIC / TEXT',
    'GENERIC TEXT',
  ];

  /// Virtual / document printers that MUST be excluded from auto-selection
  static const List<String> excludedPrinters = [
    'MICROSOFT PRINT TO PDF',
    'PDF',
    'ONENOTE',
    'SEND TO ONENOTE',
    'XPS DOCUMENT WRITER',
    'MICROSOFT XPS',
    'FAX',
    'ADOBE PDF',
    'CUTEPDF',
    'BULLZIP',
    'FOXIT',
    'VIRTUAL',
    'ROOT PRINT QUEUE',
  ];

  /// Evaluate and score a printer entry
  static PrinterCandidate evaluate({
    required String name,
    required String driverName,
    required String portName,
    bool isLocal = true,
    bool isNetwork = false,
    bool isDefault = false,
    bool isOnline = true,
    bool isPaused = false,
    int queuedJobs = 0,
    String windowsPrinterStatus = 'Ready',
  }) {
    final combined = '$name $driverName $portName'.toUpperCase();

    // 1. Hard exclusion check
    for (final excluded in excludedPrinters) {
      if (name.toUpperCase().contains(excluded) ||
          driverName.toUpperCase().contains(excluded)) {
        return PrinterCandidate(
          name: name,
          driverName: driverName,
          portName: portName,
          isLocal: isLocal,
          isNetwork: isNetwork,
          isDefault: isDefault,
          isOnline: isOnline,
          isPaused: isPaused,
          queuedJobs: queuedJobs,
          paperCapabilities: 'A4/Document',
          windowsPrinterStatus: windowsPrinterStatus,
          score: 0,
          confidence: PrinterConfidence.excluded,
          matchedEvidence: 'Excluded virtual/document printer ($excluded)',
        );
      }
    }

    int score = 0;
    final evidence = <String>[];

    // 2. POS Brand matching (e.g. POSBANK, EPSON, BIXOLON)
    for (final brand in posBrands) {
      if (combined.contains(brand)) {
        score += 35;
        evidence.add('Brand: $brand');
        break;
      }
    }

    // 3. POS Keyword matching (e.g. Thermal, Receipt, ESC/POS)
    for (final kw in posKeywords) {
      if (combined.contains(kw)) {
        score += 30;
        evidence.add('Keyword: $kw');
        break;
      }
    }

    // 4. Port analysis
    final upperPort = portName.toUpperCase();
    if (upperPort.startsWith('USB') || upperPort.startsWith('ESDPRT')) {
      score += 15;
      evidence.add('USB POS Port');
    } else if (upperPort.startsWith('COM')) {
      score += 15;
      evidence.add('Serial Port ($portName)');
    } else if (upperPort.contains('9100') || upperPort.startsWith('RAW')) {
      score += 15;
      evidence.add('Raw TCP 9100 Port');
    }

    // 5. Default printer bonus
    if (isDefault) {
      score += 10;
      evidence.add('Default System Printer');
    }

    // 6. Online state bonus
    if (isOnline && !isPaused) {
      score += 10;
    }

    // Clamp score
    if (score > 100) score = 100;

    // Estimate paper size
    String paper = '80mm';
    if (combined.contains('58') || combined.contains('58MM')) {
      paper = '58mm';
    } else if (combined.contains('A4') || combined.contains('LETTER')) {
      paper = 'A4/Document';
    }

    PrinterConfidence confidence;
    if (score >= 95) {
      confidence = PrinterConfidence.high;
    } else if (score >= 70) {
      confidence = PrinterConfidence.likely;
    } else if (score >= 40) {
      confidence = PrinterConfidence.possible;
    } else {
      confidence = PrinterConfidence.unlikely;
    }

    return PrinterCandidate(
      name: name,
      driverName: driverName,
      portName: portName,
      isLocal: isLocal,
      isNetwork: isNetwork,
      isDefault: isDefault,
      isOnline: isOnline,
      isPaused: isPaused,
      queuedJobs: queuedJobs,
      paperCapabilities: paper,
      windowsPrinterStatus: windowsPrinterStatus,
      score: score,
      confidence: confidence,
      matchedEvidence: evidence.join(', '),
    );
  }

  /// Check if a printer name or driver is excluded as virtual/document
  static bool isVirtualPrinter(String name) {
    final upper = name.toUpperCase();
    return excludedPrinters.any((e) => upper.contains(e));
  }

  /// Sort candidates in descending score order
  static List<PrinterCandidate> rankCandidates(
    List<PrinterCandidate> candidates,
  ) {
    final copy = List<PrinterCandidate>.from(candidates);
    copy.sort((a, b) => b.score.compareTo(a.score));
    return copy;
  }
}
