enum PrinterConfidence {
  high, // 95 - 100: high confidence receipt printer
  likely, // 70 - 94: likely receipt printer
  possible, // 40 - 69: possible receipt printer
  unlikely, // < 40: do not auto-select
  excluded, // Virtual/document printer (PDF, OneNote, XPS, Fax)
}

/// Represents a printer discovered via the OS printing subsystem.
class PrinterCandidate {
  final String name;
  final String driverName;
  final String portName;
  final bool isLocal;
  final bool isNetwork;
  final bool isDefault;
  final bool isOnline;
  final bool isPaused;
  final int queuedJobs;
  final String paperCapabilities; // "80mm", "58mm", "A4/Document"
  final String windowsPrinterStatus;
  final int score;
  final PrinterConfidence confidence;
  final String? matchedEvidence;

  const PrinterCandidate({
    required this.name,
    required this.driverName,
    required this.portName,
    this.isLocal = true,
    this.isNetwork = false,
    this.isDefault = false,
    this.isOnline = true,
    this.isPaused = false,
    this.queuedJobs = 0,
    this.paperCapabilities = '80mm',
    this.windowsPrinterStatus = 'Ready',
    this.score = 0,
    this.confidence = PrinterConfidence.unlikely,
    this.matchedEvidence,
  });

  bool get isReceiptPrinterCandidate =>
      confidence == PrinterConfidence.high ||
      confidence == PrinterConfidence.likely ||
      confidence == PrinterConfidence.possible;

  bool get isHighConfidence => confidence == PrinterConfidence.high;

  Map<String, dynamic> toJson() => {
    'name': name,
    'driverName': driverName,
    'portName': portName,
    'isLocal': isLocal,
    'isNetwork': isNetwork,
    'isDefault': isDefault,
    'isOnline': isOnline,
    'isPaused': isPaused,
    'queuedJobs': queuedJobs,
    'paperCapabilities': paperCapabilities,
    'windowsPrinterStatus': windowsPrinterStatus,
    'score': score,
    'confidence': confidence.name,
    'matchedEvidence': matchedEvidence,
  };

  factory PrinterCandidate.fromJson(Map<String, dynamic> json) {
    return PrinterCandidate(
      name: json['name'] as String? ?? 'Unknown',
      driverName: json['driverName'] as String? ?? '',
      portName: json['portName'] as String? ?? '',
      isLocal: json['isLocal'] as bool? ?? true,
      isNetwork: json['isNetwork'] as bool? ?? false,
      isDefault: json['isDefault'] as bool? ?? false,
      isOnline: json['isOnline'] as bool? ?? true,
      isPaused: json['isPaused'] as bool? ?? false,
      queuedJobs: json['queuedJobs'] as int? ?? 0,
      paperCapabilities: json['paperCapabilities'] as String? ?? '80mm',
      windowsPrinterStatus: json['windowsPrinterStatus'] as String? ?? 'Ready',
      score: json['score'] as int? ?? 0,
      confidence: PrinterConfidence.values.firstWhere(
        (c) => c.name == json['confidence'],
        orElse: () => PrinterConfidence.unlikely,
      ),
      matchedEvidence: json['matchedEvidence'] as String?,
    );
  }
}
