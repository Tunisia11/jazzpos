import 'dart:async';
import 'package:flutter/services.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'barcode_scanner_interface.dart';

/// Global USB HID Barcode Scanner listener that intercepts barcode input
/// without requiring focus on a specific text field.
class KeyboardBarcodeScanner implements BarcodeScanner {
  @override
  final String name;

  final _scanController = StreamController<String>.broadcast();
  final StringBuffer _buffer = StringBuffer();
  DateTime _lastKeystrokeTime = DateTime.now();
  bool _listening = false;

  KeyboardBarcodeScanner({this.name = 'USB HID Hardware Scanner'});

  @override
  Stream<String> get onScan => _scanController.stream;

  @override
  Future<void> startListening() async {
    if (_listening) return;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _listening = true;
    PosLogger.instance.info(
      'Scanner',
      'Started listening to USB HID scanner hardware',
    );
  }

  @override
  Future<void> stopListening() async {
    if (!_listening) return;
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _listening = false;
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final now = DateTime.now();
    final elapsedMs = now.difference(_lastKeystrokeTime).inMilliseconds;
    _lastKeystrokeTime = now;

    // Scanners type at superhuman speed (< 50ms between strokes).
    // If more than 300ms elapsed since last char, reset buffer.
    if (elapsedMs > 300) {
      _buffer.clear();
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final barcode = _buffer.toString().trim();
      _buffer.clear();

      if (barcode.isNotEmpty && barcode.length >= 3) {
        PosLogger.instance.info(
          'Scanner',
          'Hardware barcode scanned: $barcode',
        );
        _scanController.add(barcode);
        return true; // Handled
      }
      return false;
    }

    final char = event.character;
    if (char != null && char.isNotEmpty && char.codeUnitAt(0) >= 32) {
      _buffer.write(char);
    }

    return false;
  }
}
