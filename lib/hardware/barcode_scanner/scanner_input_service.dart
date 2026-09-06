import 'dart:async';
import 'package:flutter/services.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/hardware/models/hardware_fingerprint.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';
import 'barcode_scanner_interface.dart';

/// Test event captured when scanning in the Hardware Setup Wizard
class ScannerTestEvent {
  final String barcode;
  final int characterCount;
  final Duration totalDuration;
  final double averageInterKeyMs;
  final DateTime timestamp;

  const ScannerTestEvent({
    required this.barcode,
    required this.characterCount,
    required this.totalDuration,
    required this.averageInterKeyMs,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'barcode': barcode,
    'characterCount': characterCount,
    'totalDurationMs': totalDuration.inMilliseconds,
    'averageInterKeyMs': averageInterKeyMs,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// Production-grade Barcode Scanner service supporting universal USB HID
/// Keyboard Wedge mode and optional serial COM scanner mode.
class ScannerInputService implements BarcodeScanner {
  @override
  final String name;

  final Duration maximumInterKeyDelay;
  final int minimumLength;

  final _scanController = StreamController<String>.broadcast();
  final _testEventController = StreamController<ScannerTestEvent>.broadcast();

  final List<({String char, DateTime time})> _buffer = [];
  bool _isListening = false;
  HardwareStatus _status = HardwareStatus.configured;

  ScannerInputService({
    this.name = 'USB HID Universal Barcode Scanner',
    this.maximumInterKeyDelay = const Duration(milliseconds: 80),
    this.minimumLength = 3,
  });

  @override
  Stream<String> get onScan => _scanController.stream;

  Stream<ScannerTestEvent> get onTestEvent => _testEventController.stream;

  HardwareStatus get status => _status;

  HardwareFingerprint get fingerprint => const HardwareFingerprint(
    transport: 'KEYBOARD_WEDGE',
    friendlyName: 'USB HID Keyboard Wedge Scanner',
  );

  @override
  Future<void> startListening() async {
    if (_isListening) return;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _isListening = true;
    _status = HardwareStatus.ready;
    PosLogger.instance.info(
      'ScannerService',
      'Started listening for rapid USB HID barcode bursts (< ${maximumInterKeyDelay.inMilliseconds}ms/char).',
    );
  }

  @override
  Future<void> stopListening() async {
    if (!_isListening) return;
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _isListening = false;
    _status = HardwareStatus.configured;
  }

  /// Reset internal input buffer
  void reset() {
    _buffer.clear();
  }

  /// Low-level key event handler
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final now = DateTime.now();
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;

    if (isEnter) {
      if (_buffer.length >= minimumLength) {
        // Calculate timing metrics
        final totalDuration = _buffer.last.time.difference(_buffer.first.time);
        final avgInterKey = _buffer.length > 1
            ? totalDuration.inMilliseconds / (_buffer.length - 1)
            : 0.0;

        // If average delay between characters is within scanner burst speed (<80ms)
        if (avgInterKey <= maximumInterKeyDelay.inMilliseconds + 20) {
          final barcode = _buffer.map((e) => e.char).join().trim();
          _buffer.clear();

          if (barcode.length >= minimumLength) {
            PosLogger.instance.info(
              'ScannerService',
              'Barcode burst decoded: "$barcode" (${totalDuration.inMilliseconds}ms, avg ${avgInterKey.toStringAsFixed(1)}ms/char)',
            );

            final testEvent = ScannerTestEvent(
              barcode: barcode,
              characterCount: barcode.length,
              totalDuration: totalDuration,
              averageInterKeyMs: avgInterKey,
              timestamp: now,
            );
            _testEventController.add(testEvent);
            _scanController.add(barcode);
            return true; // Consume event so enter doesn't trigger unrelated buttons
          }
        }
      }
      _buffer.clear();
      return false;
    }

    final char = event.character;
    if (char != null && char.isNotEmpty && char.codeUnitAt(0) >= 32) {
      // Check inter-key timing from previous character
      if (_buffer.isNotEmpty) {
        final lastTime = _buffer.last.time;
        if (now.difference(lastTime) > maximumInterKeyDelay) {
          // Exceeded inter-key delay threshold -> human typing, reset buffer
          _buffer.clear();
        }
      }
      _buffer.add((char: char, time: now));
    }

    return false;
  }

  /// Simulate barcode scan (for testing and manual simulated input)
  void simulateScan(String barcode) {
    _scanController.add(barcode);
    _testEventController.add(
      ScannerTestEvent(
        barcode: barcode,
        characterCount: barcode.length,
        totalDuration: const Duration(milliseconds: 30),
        averageInterKeyMs: 3.0,
        timestamp: DateTime.now(),
      ),
    );
  }
}
