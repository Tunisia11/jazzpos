/// Contract defining the cloud sync transport layer.
abstract class CloudSyncBackend {
  /// Test connectivity and authentication against the remote endpoint.
  /// Returns `true` if server responded with 2xx status.
  Future<bool> testConnection(String url, String apiKey);

  /// Push a completed sale record (including items and payments) to the cloud.
  Future<void> pushSale(Map<String, dynamic> saleData);

  /// Push a completed return record to the cloud.
  Future<void> pushReturn(Map<String, dynamic> returnData);

  /// Push inventory stock level snapshot to the cloud.
  Future<void> pushStockLevels(List<Map<String, dynamic>> stockLevels);

  /// Push a product catalog update (e.g. price change by owner) to the cloud.
  Future<void> pushProductUpdate(Map<String, dynamic> productData);

  /// Pull products and variants that have been modified or created since [since].
  Future<List<Map<String, dynamic>>> pullCatalogUpdates({DateTime? since});
}

/// Generic exception thrown during cloud synchronization failures.
class SyncException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic originalError;

  const SyncException(this.message, {this.statusCode, this.originalError});

  @override
  String toString() =>
      'SyncException: $message${statusCode != null ? ' (status: $statusCode)' : ''}';
}
