import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/hardware/models/hardware_fingerprint.dart';
import 'package:jazzpos/hardware/receipt_printer/printer_candidate.dart';
import 'package:jazzpos/hardware/receipt_printer/printer_scorer.dart';

/// Discovered USB peripheral information
class DiscoveredUsbDevice {
  final String name;
  final String? manufacturer;
  final String? vendorId;
  final String? productId;
  final String? serialNumber;
  final String? deviceClass;
  final String? port;
  final bool isConnected;

  const DiscoveredUsbDevice({
    required this.name,
    this.manufacturer,
    this.vendorId,
    this.productId,
    this.serialNumber,
    this.deviceClass,
    this.port,
    this.isConnected = true,
  });

  HardwareFingerprint toFingerprint({String transport = 'USB'}) {
    return HardwareFingerprint(
      transport: transport,
      vendorId: vendorId,
      productId: productId,
      serialNumber: serialNumber,
      portOrAddress: port,
      friendlyName: name,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'manufacturer': manufacturer,
    'vendorId': vendorId,
    'productId': productId,
    'serialNumber': serialNumber,
    'deviceClass': deviceClass,
    'port': port,
    'isConnected': isConnected,
  };
}

/// Discovered COM serial port information
class DiscoveredSerialPort {
  final String portName; // e.g. "COM1", "COM3"
  final String friendlyName;
  final String description;
  final String? hardwareId;
  final String? vendorId;
  final String? productId;

  const DiscoveredSerialPort({
    required this.portName,
    required this.friendlyName,
    required this.description,
    this.hardwareId,
    this.vendorId,
    this.productId,
  });

  HardwareFingerprint toFingerprint() {
    return HardwareFingerprint(
      transport: 'SERIAL',
      portOrAddress: portName,
      vendorId: vendorId,
      productId: productId,
      friendlyName: friendlyName,
    );
  }

  Map<String, dynamic> toJson() => {
    'portName': portName,
    'friendlyName': friendlyName,
    'description': description,
    'hardwareId': hardwareId,
    'vendorId': vendorId,
    'productId': productId,
  };
}

/// Discovered display monitor information
class DiscoveredDisplay {
  final int id;
  final int width;
  final int height;
  final double dpiScale;
  final bool isPrimary;

  const DiscoveredDisplay({
    required this.id,
    required this.width,
    required this.height,
    required this.dpiScale,
    required this.isPrimary,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'width': width,
    'height': height,
    'dpiScale': dpiScale,
    'isPrimary': isPrimary,
  };
}

/// Complete peripheral discovery report
class HardwareDiscoveryReport {
  final DateTime timestamp;
  final List<PrinterCandidate> printers;
  final List<DiscoveredUsbDevice> usbDevices;
  final List<DiscoveredSerialPort> serialPorts;
  final List<DiscoveredDisplay> displays;

  const HardwareDiscoveryReport({
    required this.timestamp,
    required this.printers,
    required this.usbDevices,
    required this.serialPorts,
    required this.displays,
  });

  List<PrinterCandidate> get receiptPrinterCandidates =>
      printers.where((p) => p.isReceiptPrinterCandidate).toList()
        ..sort((a, b) => b.score.compareTo(a.score));

  PrinterCandidate? get topPrinterCandidate =>
      receiptPrinterCandidates.isNotEmpty
      ? receiptPrinterCandidates.first
      : null;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'printers': printers.map((p) => p.toJson()).toList(),
    'usbDevices': usbDevices.map((u) => u.toJson()).toList(),
    'serialPorts': serialPorts.map((s) => s.toJson()).toList(),
    'displays': displays.map((d) => d.toJson()).toList(),
  };
}

/// Service that discovers and enumerates connected POS hardware peripherals.
class HardwareDiscoveryService {
  /// Run complete discovery scan across Printers, USB, Serial, and Displays
  Future<HardwareDiscoveryReport> discoverAll() async {
    PosLogger.instance.info('Discovery', 'Scanning system for POS hardware...');

    final printers = await discoverPrinters();
    final usbDevices = await discoverUsbDevices();
    final serialPorts = await discoverSerialPorts();
    final displays = discoverDisplays();

    final report = HardwareDiscoveryReport(
      timestamp: DateTime.now(),
      printers: printers,
      usbDevices: usbDevices,
      serialPorts: serialPorts,
      displays: displays,
    );

    PosLogger.instance.info(
      'Discovery',
      'Scan finished. Found ${printers.length} printers (${report.receiptPrinterCandidates.length} receipt candidates), '
          '${usbDevices.length} USB devices, ${serialPorts.length} COM ports, ${displays.length} displays.',
    );

    return report;
  }

  /// Discover installed Windows print queues via Spooler / PowerShell
  Future<List<PrinterCandidate>> discoverPrinters() async {
    final candidates = <PrinterCandidate>[];

    if (Platform.isWindows) {
      try {
        final psScript = '''
Get-CimInstance Win32_Printer | Select-Object Name, DriverName, PortName, Local, Network, Default, WorkOffline | ConvertTo-Json -Compress
''';
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          psScript,
        ]);

        if (result.exitCode == 0 &&
            (result.stdout as String).trim().isNotEmpty) {
          final raw = jsonDecode((result.stdout as String).trim());
          final list = raw is List ? raw : [raw];

          for (final item in list) {
            final name = item['Name']?.toString() ?? 'Unknown';
            final driver = item['DriverName']?.toString() ?? '';
            final port = item['PortName']?.toString() ?? '';
            final isLocal = item['Local'] == true;
            final isNet = item['Network'] == true;
            final isDefault = item['Default'] == true;
            final isOffline = item['WorkOffline'] == true;

            final candidate = PrinterScorer.evaluate(
              name: name,
              driverName: driver,
              portName: port,
              isLocal: isLocal,
              isNetwork: isNet,
              isDefault: isDefault,
              isOnline: !isOffline,
            );
            candidates.add(candidate);
          }
        }
      } catch (e) {
        PosLogger.instance.warning(
          'Discovery',
          'Printer discovery error on Windows: $e',
        );
      }
    }

    // If no physical printers found (e.g. macOS / Linux / test environment),
    // provide clear discovery results
    if (candidates.isEmpty) {
      if (Platform.isMacOS) {
        // Safe fallback for macOS developers / demonstrators
        candidates.add(
          PrinterScorer.evaluate(
            name: 'Generic 80mm Receipt Printer (USB)',
            driverName: 'ESC/POS Thermal Driver',
            portName: 'USB001',
            isDefault: true,
          ),
        );
      }
    }

    return candidates;
  }

  /// Discover USB devices connected to system
  Future<List<DiscoveredUsbDevice>> discoverUsbDevices() async {
    final devices = <DiscoveredUsbDevice>[];

    if (Platform.isWindows) {
      try {
        final psScript = '''
Get-CimInstance Win32_PnPEntity | Where-Object { \$_.DeviceID -like 'USB*' } | Select-Object Name, Manufacturer, DeviceID, Status, Service | ConvertTo-Json -Compress
''';
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          psScript,
        ]);

        if (result.exitCode == 0 &&
            (result.stdout as String).trim().isNotEmpty) {
          final raw = jsonDecode((result.stdout as String).trim());
          final list = raw is List ? raw : [raw];

          for (final item in list) {
            final name = item['Name']?.toString() ?? 'USB Device';
            final manufacturer = item['Manufacturer']?.toString();
            final deviceId = item['DeviceID']?.toString() ?? '';
            final isConnected = (item['Status']?.toString() ?? '') == 'OK';

            // Extract VID & PID if present (format: USB\VID_xxxx&PID_yyyy\...)
            String? vid;
            String? pid;
            final vidMatch = RegExp(
              r'VID_([0-9A-Fa-f]{4})',
            ).firstMatch(deviceId);
            final pidMatch = RegExp(
              r'PID_([0-9A-Fa-f]{4})',
            ).firstMatch(deviceId);
            if (vidMatch != null) vid = vidMatch.group(1);
            if (pidMatch != null) pid = pidMatch.group(1);

            devices.add(
              DiscoveredUsbDevice(
                name: name,
                manufacturer: manufacturer,
                vendorId: vid,
                productId: pid,
                deviceClass: item['Service']?.toString(),
                isConnected: isConnected,
              ),
            );
          }
        }
      } catch (e) {
        PosLogger.instance.warning('Discovery', 'USB discovery error: $e');
      }
    }

    return devices;
  }

  /// Discover COM serial ports on Windows
  Future<List<DiscoveredSerialPort>> discoverSerialPorts() async {
    final ports = <DiscoveredSerialPort>[];

    if (Platform.isWindows) {
      try {
        final psScript = '''
Get-CimInstance Win32_SerialPort | Select-Object DeviceID, Name, Description, PNPDeviceID | ConvertTo-Json -Compress
''';
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          psScript,
        ]);

        if (result.exitCode == 0 &&
            (result.stdout as String).trim().isNotEmpty) {
          final raw = jsonDecode((result.stdout as String).trim());
          final list = raw is List ? raw : [raw];

          for (final item in list) {
            final portId = item['DeviceID']?.toString() ?? 'COM1';
            final name = item['Name']?.toString() ?? portId;
            final desc = item['Description']?.toString() ?? '';
            final pnpId = item['PNPDeviceID']?.toString();

            String? vid;
            String? pid;
            if (pnpId != null) {
              final vidMatch = RegExp(
                r'VID_([0-9A-Fa-f]{4})',
              ).firstMatch(pnpId);
              final pidMatch = RegExp(
                r'PID_([0-9A-Fa-f]{4})',
              ).firstMatch(pnpId);
              if (vidMatch != null) vid = vidMatch.group(1);
              if (pidMatch != null) pid = pidMatch.group(1);
            }

            ports.add(
              DiscoveredSerialPort(
                portName: portId,
                friendlyName: name,
                description: desc,
                hardwareId: pnpId,
                vendorId: vid,
                productId: pid,
              ),
            );
          }
        }
      } catch (e) {
        PosLogger.instance.warning('Discovery', 'Serial discovery error: $e');
      }
    }

    return ports;
  }

  /// Enumerate displays attached to the computer
  List<DiscoveredDisplay> discoverDisplays() {
    final list = <DiscoveredDisplay>[];
    try {
      final dispatcher = WidgetsBinding.instance.platformDispatcher;
      final displays = dispatcher.displays.toList();
      for (int i = 0; i < displays.length; i++) {
        final d = displays[i];
        list.add(
          DiscoveredDisplay(
            id: i,
            width: d.size.width.round(),
            height: d.size.height.round(),
            dpiScale: d.devicePixelRatio,
            isPrimary: i == 0,
          ),
        );
      }
    } catch (_) {}

    if (list.isEmpty) {
      list.add(
        const DiscoveredDisplay(
          id: 0,
          width: 1920,
          height: 1080,
          dpiScale: 1.0,
          isPrimary: true,
        ),
      );
    }

    return list;
  }
}
