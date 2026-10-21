import 'package:flutter/widgets.dart';
import '../hardware_manager.dart';
import 'scanner_input_service.dart';

/// Never carry a partial physical scan between pages or modal routes.
class ScannerRouteObserver extends NavigatorObserver {
  void _reset() {
    final scanner=HardwareManager.instance.barcodeScanner;
    if(scanner is ScannerInputService) scanner.reset();
  }
  @override void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _reset();
  @override void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _reset();
  @override void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _reset();
  @override void didReplace({Route<dynamic>? newRoute,Route<dynamic>? oldRoute}) => _reset();
}
