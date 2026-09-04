/// Typed domain failure representing business, validation, hardware, or database errors.
class PosException implements Exception {
  final String message;
  final String? code;
  final Object? originalError;
  final StackTrace? stackTrace;

  const PosException(
    this.message, {
    this.code,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() =>
      'PosException: $message ${code != null ? '($code)' : ''}';
}

class ValidationException extends PosException {
  const ValidationException(super.message, {super.code});
}

class AuthException extends PosException {
  const AuthException(super.message, {super.code});
}

class InsufficientStockException extends PosException {
  final String variantId;
  final int availableStock;
  final int requestedQuantity;

  const InsufficientStockException({
    required this.variantId,
    required this.availableStock,
    required this.requestedQuantity,
    String message = 'Physical stock is insufficient for this sale',
  }) : super(message, code: 'INSUFFICIENT_STOCK');
}

class HardwareException extends PosException {
  final String deviceType;
  final String? deviceName;

  const HardwareException(
    super.message, {
    required this.deviceType,
    this.deviceName,
    super.code,
    super.originalError,
  });
}

class DuplicateException extends PosException {
  const DuplicateException(super.message, {super.code});
}
