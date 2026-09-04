import 'dart:async';
import 'package:flutter/material.dart';
import 'package:jazzpos/hardware/hardware_manager.dart';

/// Wraps an application subtree and listens to hardware barcode scanner events.
class BarcodeScannerListener extends StatefulWidget {
  final Widget child;
  final ValueChanged<String> onBarcodeScanned;

  const BarcodeScannerListener({
    super.key,
    required this.child,
    required this.onBarcodeScanned,
  });

  @override
  State<BarcodeScannerListener> createState() => _BarcodeScannerListenerState();
}

class _BarcodeScannerListenerState extends State<BarcodeScannerListener> {
  StreamSubscription<String>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = HardwareManager.instance.barcodeScanner.onScan.listen((barcode) {
      if (mounted) {
        widget.onBarcodeScanned(barcode);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
