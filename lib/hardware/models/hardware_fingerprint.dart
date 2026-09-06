/// Represents a unique hardware device fingerprint to maintain device identity
/// across reboots and dynamic COM / USB port reallocations.
class HardwareFingerprint {
  final String transport; // SPOOLER, USB, SERIAL, NETWORK, VIRTUAL
  final String? vendorId; // Hex VID (e.g. "04B8", "1504")
  final String? productId; // Hex PID (e.g. "0202", "002F")
  final String? serialNumber; // Device serial number or hardware instance ID
  final String? portOrAddress; // Port (COM3, USB001, 192.168.1.100)
  final String? friendlyName;

  const HardwareFingerprint({
    required this.transport,
    this.vendorId,
    this.productId,
    this.serialNumber,
    this.portOrAddress,
    this.friendlyName,
  });

  /// Canonical serialization: "transport:vid:pid:serial:port"
  String toCanonicalKey() {
    final v = (vendorId ?? '').trim().toLowerCase();
    final p = (productId ?? '').trim().toLowerCase();
    final s = (serialNumber ?? '').trim().toLowerCase();
    final a = (portOrAddress ?? '').trim().toLowerCase();
    return '${transport.toUpperCase()}:$v:$p:$s:$a';
  }

  /// Evaluates whether another detected device matches this fingerprint.
  /// Matches on VID+PID+serial if available, or name+port.
  bool matches(HardwareFingerprint other) {
    if (transport.toUpperCase() != other.transport.toUpperCase()) return false;

    // 1. Precise match via VID + PID + Serial
    final hasVidPid =
        vendorId != null &&
        other.vendorId != null &&
        productId != null &&
        other.productId != null;
    if (hasVidPid) {
      final vidMatch = vendorId!.equalsIgnoreCase(other.vendorId!);
      final pidMatch = productId!.equalsIgnoreCase(other.productId!);
      if (vidMatch && pidMatch) {
        if (serialNumber != null && other.serialNumber != null) {
          return serialNumber!.equalsIgnoreCase(other.serialNumber!);
        }
        return true;
      }
    }

    // 2. Fallback to exact port/address match
    if (portOrAddress != null &&
        other.portOrAddress != null &&
        portOrAddress!.equalsIgnoreCase(other.portOrAddress!)) {
      return true;
    }

    // 3. Fallback to exact friendly name match within same transport
    if (friendlyName != null &&
        other.friendlyName != null &&
        friendlyName!.equalsIgnoreCase(other.friendlyName!)) {
      return true;
    }

    return false;
  }

  Map<String, dynamic> toJson() => {
    'transport': transport,
    'vendorId': vendorId,
    'productId': productId,
    'serialNumber': serialNumber,
    'portOrAddress': portOrAddress,
    'friendlyName': friendlyName,
  };

  factory HardwareFingerprint.fromJson(Map<String, dynamic> json) {
    return HardwareFingerprint(
      transport: json['transport'] as String? ?? 'UNKNOWN',
      vendorId: json['vendorId'] as String?,
      productId: json['productId'] as String?,
      serialNumber: json['serialNumber'] as String?,
      portOrAddress: json['portOrAddress'] as String?,
      friendlyName: json['friendlyName'] as String?,
    );
  }

  @override
  String toString() => toCanonicalKey();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HardwareFingerprint &&
          toCanonicalKey() == other.toCanonicalKey();

  @override
  int get hashCode => toCanonicalKey().hashCode;
}

extension _StringCaseEq on String {
  bool equalsIgnoreCase(String other) => toLowerCase() == other.toLowerCase();
}
