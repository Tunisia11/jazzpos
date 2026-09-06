/// Reusable POS thermal printer profile defining capabilities, line widths, and hardware commands.
class PrinterProfile {
  final String id;
  final String name;
  final int paperWidthMm;
  final int charactersPerLine;
  final bool hasCutter;
  final bool hasDrawerPort;
  final List<int> drawerKickCommand;
  final List<int> cutCommand;
  final bool supportsRaster;
  final bool supportsBarcode128;
  final bool supportsQr;
  final String defaultCodePage;
  final List<String> supportedTransports;

  const PrinterProfile({
    required this.id,
    required this.name,
    this.paperWidthMm = 80,
    this.charactersPerLine = 48,
    this.hasCutter = true,
    this.hasDrawerPort = true,
    this.drawerKickCommand = const [
      0x1B,
      0x70,
      0x00,
      0x19,
      0xFA,
    ], // ESC p 0 25 250
    this.cutCommand = const [0x1D, 0x56, 0x42, 0x00], // GS V 66 0
    this.supportsRaster = true,
    this.supportsBarcode128 = true,
    this.supportsQr = true,
    this.defaultCodePage = 'PC850', // Multilingual Western
    this.supportedTransports = const [
      'WINDOWS_SPOOLER',
      'USB',
      'NETWORK',
      'SERIAL',
    ],
  });

  /// Standard generic Windows driver / Spooler profile
  static const PrinterProfile genericWindows = PrinterProfile(
    id: 'GENERIC_WINDOWS',
    name: 'Pilote Windows Standard (Spooler)',
    paperWidthMm: 80,
    charactersPerLine: 48,
    hasCutter: true,
    hasDrawerPort: true,
    supportedTransports: ['WINDOWS_SPOOLER'],
  );

  /// Generic 80mm ESC/POS thermal printer
  static const PrinterProfile genericEscPos80 = PrinterProfile(
    id: 'GENERIC_ESC_POS_80',
    name: 'Générique ESC/POS 80mm',
    paperWidthMm: 80,
    charactersPerLine: 48,
    hasCutter: true,
    hasDrawerPort: true,
  );

  /// Generic 58mm compact ESC/POS thermal printer
  static const PrinterProfile genericEscPos58 = PrinterProfile(
    id: 'GENERIC_ESC_POS_58',
    name: 'Générique ESC/POS 58mm (Compact)',
    paperWidthMm: 58,
    charactersPerLine: 32,
    hasCutter: false,
    hasDrawerPort: true,
    cutCommand: [],
  );

  /// POSBANK Apexa / A7 / A11 series
  static const PrinterProfile posbank = PrinterProfile(
    id: 'POSBANK',
    name: 'POSBANK Apexa / A7 / A11',
    paperWidthMm: 80,
    charactersPerLine: 48,
    hasCutter: true,
    hasDrawerPort: true,
    // POSBANK pin 2 drawer pulse: ESC p 0 25 250
    drawerKickCommand: [0x1B, 0x70, 0x00, 0x19, 0xFA],
    cutCommand: [0x1D, 0x56, 0x42, 0x00],
  );

  /// Epson TM-T88 / TM-T20 standard
  static const PrinterProfile epsonEscPos = PrinterProfile(
    id: 'EPSON_ESC_POS',
    name: 'Epson TM Series (TM-T88 / TM-T20)',
    paperWidthMm: 80,
    charactersPerLine: 48,
    hasCutter: true,
    hasDrawerPort: true,
    drawerKickCommand: [0x1B, 0x70, 0x00, 0x19, 0xFA],
    cutCommand: [0x1D, 0x56, 0x42, 0x00],
  );

  /// Bixolon SRP-350 / SRP-330 standard
  static const PrinterProfile bixolon = PrinterProfile(
    id: 'BIXOLON',
    name: 'Bixolon SRP Series',
    paperWidthMm: 80,
    charactersPerLine: 48,
    hasCutter: true,
    hasDrawerPort: true,
    drawerKickCommand: [0x1B, 0x70, 0x00, 0x19, 0xFA],
    cutCommand: [0x1D, 0x56, 0x42, 0x00],
  );

  /// Star Micronics Line Mode
  static const PrinterProfile star = PrinterProfile(
    id: 'STAR',
    name: 'Star Micronics TSP Series (Star Emulation)',
    paperWidthMm: 80,
    charactersPerLine: 48,
    hasCutter: true,
    hasDrawerPort: true,
    drawerKickCommand: [0x07], // BEL command on Star Micronics
    cutCommand: [0x1B, 0x64, 0x02], // Star cut command
  );

  /// Custom profile for specialized hardware
  static PrinterProfile custom({
    required String name,
    int paperWidthMm = 80,
    int charactersPerLine = 48,
    bool hasCutter = true,
    bool hasDrawerPort = true,
    List<int> drawerKickCommand = const [0x1B, 0x70, 0x00, 0x19, 0xFA],
    List<int> cutCommand = const [0x1D, 0x56, 0x42, 0x00],
  }) {
    return PrinterProfile(
      id: 'CUSTOM',
      name: name,
      paperWidthMm: paperWidthMm,
      charactersPerLine: charactersPerLine,
      hasCutter: hasCutter,
      hasDrawerPort: hasDrawerPort,
      drawerKickCommand: drawerKickCommand,
      cutCommand: cutCommand,
    );
  }

  static const List<PrinterProfile> standardProfiles = [
    genericWindows,
    genericEscPos80,
    genericEscPos58,
    posbank,
    epsonEscPos,
    bixolon,
    star,
  ];

  static PrinterProfile fromId(String? id) {
    if (id == null) return genericWindows;
    return standardProfiles.firstWhere(
      (p) => p.id.toUpperCase() == id.toUpperCase(),
      orElse: () => genericWindows,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'paperWidthMm': paperWidthMm,
    'charactersPerLine': charactersPerLine,
    'hasCutter': hasCutter,
    'hasDrawerPort': hasDrawerPort,
    'drawerKickCommand': drawerKickCommand,
    'cutCommand': cutCommand,
    'supportsRaster': supportsRaster,
    'supportsBarcode128': supportsBarcode128,
    'supportsQr': supportsQr,
    'defaultCodePage': defaultCodePage,
    'supportedTransports': supportedTransports,
  };

  factory PrinterProfile.fromJson(Map<String, dynamic> json) {
    return PrinterProfile(
      id: json['id'] as String? ?? 'GENERIC_WINDOWS',
      name: json['name'] as String? ?? 'Generic Windows',
      paperWidthMm: json['paperWidthMm'] as int? ?? 80,
      charactersPerLine: json['charactersPerLine'] as int? ?? 48,
      hasCutter: json['hasCutter'] as bool? ?? true,
      hasDrawerPort: json['hasDrawerPort'] as bool? ?? true,
      drawerKickCommand:
          (json['drawerKickCommand'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          const [0x1B, 0x70, 0x00, 0x19, 0xFA],
      cutCommand:
          (json['cutCommand'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          const [0x1D, 0x56, 0x42, 0x00],
      supportsRaster: json['supportsRaster'] as bool? ?? true,
      supportsBarcode128: json['supportsBarcode128'] as bool? ?? true,
      supportsQr: json['supportsQr'] as bool? ?? true,
      defaultCodePage: json['defaultCodePage'] as String? ?? 'PC850',
      supportedTransports:
          (json['supportedTransports'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['WINDOWS_SPOOLER', 'USB', 'NETWORK', 'SERIAL'],
    );
  }
}
