import 'dart:async';
import 'package:flutter/services.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'barcode_scanner_interface.dart';

/// Separates scanner-speed bursts from ordinary keyboard typing.
class BarcodeInputAccumulator {
  final Duration maximumInterKeyDelay;
  final int minimumLength;
  final StringBuffer _buffer = StringBuffer();
  DateTime? _lastCharacterAt;

  BarcodeInputAccumulator({
    this.maximumInterKeyDelay = const Duration(milliseconds: 80),
    this.minimumLength = 3,
  });

  void addCharacter(String character, DateTime timestamp) {
    final previous = _lastCharacterAt;
    if (previous != null &&
        timestamp.difference(previous) > maximumInterKeyDelay) {
      _buffer.clear();
    }
    _buffer.write(character);
    _lastCharacterAt = timestamp;
  }

  String? complete(DateTime timestamp) {
    final last = _lastCharacterAt;
    final value = _buffer.toString().trim();
    clear();
    if (last == null ||
        timestamp.difference(last) > maximumInterKeyDelay ||
        value.length < minimumLength) {
      return null;
    }
    return value;
  }

  void clear() {
    _buffer.clear();
    _lastCharacterAt = null;
  }
}

/// Global USB HID Barcode Scanner listener that intercepts barcode input
/// without requiring focus on a specific text field.
class KeyboardBarcodeScanner implements BarcodeScanner {
  @override
  final String name;

  final _scanController = StreamController<String>.broadcast();
  final BarcodeInputAccumulator _input = BarcodeInputAccumulator();
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
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final barcode = _input.complete(now);

      if (barcode != null) {
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
      _input.addCharacter(char, now);
    }

    return false;
  }
}
