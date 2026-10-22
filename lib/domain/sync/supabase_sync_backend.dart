import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:tracepos/core/logging/pos_logger.dart';
import 'cloud_sync_backend.dart';

/// Supabase PostgREST implementation of [CloudSyncBackend].
class SupabaseSyncBackend implements CloudSyncBackend {
  final http.Client _client;
  String supabaseUrl;
  String apiKey;

  SupabaseSyncBackend({
    http.Client? client,
    this.supabaseUrl = '',
    this.apiKey = '',
  }) : _client = client ?? http.Client();

  String get _cleanBaseUrl {
    var url = supabaseUrl.trim();
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  Map<String, String> _buildHeaders({bool upsert = false}) {
    final headers = <String, String>{
      'apikey': apiKey.trim(),
      'Authorization': 'Bearer ${apiKey.trim()}',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (upsert) {
      headers['Prefer'] = 'resolution=merge-duplicates,return=representation';
    }
    return headers;
  }

  @override
  Future<bool> testConnection(String url, String key) async {
    final cleanUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleanUrl.isEmpty || key.trim().isEmpty) return false;

    try {
      final endpoint = Uri.parse('$cleanUrl/rest/v1/');
      final response = await _client
          .get(
            endpoint,
            headers: {
              'apikey': key.trim(),
              'Authorization': 'Bearer ${key.trim()}',
            },
          )
          .timeout(const Duration(seconds: 5));

      // PostgREST root returns 200 OpenAPI schema when valid key is provided
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      PosLogger.instance.warning('SupabaseSync', 'Connection test failed: $e');
      return false;
    }
  }

  @override
  Future<void> pushSale(Map<String, dynamic> saleData) async {
    if (_cleanBaseUrl.isEmpty || apiKey.isEmpty) {
      throw const SyncException('Supabase credentials not configured');
    }

    final saleRow = Map<String, dynamic>.from(saleData)
      ..remove('lines')
      ..remove('payments');

    final lines = (saleData['lines'] as List<dynamic>?) ?? [];
    final payments = (saleData['payments'] as List<dynamic>?) ?? [];

    try {
      // 1. Upsert sale header
      final saleUri = Uri.parse('$_cleanBaseUrl/rest/v1/sales');
      final saleRes = await _client
          .post(
            saleUri,
            headers: _buildHeaders(upsert: true),
            body: jsonEncode(saleRow),
          )
          .timeout(const Duration(seconds: 10));

      if (saleRes.statusCode >= 300) {
        throw SyncException(
          'Failed to upsert sale: ${saleRes.body}',
          statusCode: saleRes.statusCode,
        );
      }

      // 2. Upsert sale lines
      if (lines.isNotEmpty) {
        final linesUri = Uri.parse('$_cleanBaseUrl/rest/v1/sale_lines');
        final linesRes = await _client
            .post(
              linesUri,
              headers: _buildHeaders(upsert: true),
              body: jsonEncode(lines),
            )
            .timeout(const Duration(seconds: 10));

        if (linesRes.statusCode >= 300) {
          throw SyncException(
            'Failed to upsert sale lines: ${linesRes.body}',
            statusCode: linesRes.statusCode,
          );
        }
      }

      // 3. Upsert sale payments
      if (payments.isNotEmpty) {
        final paymentsUri = Uri.parse('$_cleanBaseUrl/rest/v1/sale_payments');
        final paymentsRes = await _client
            .post(
              paymentsUri,
              headers: _buildHeaders(upsert: true),
              body: jsonEncode(payments),
            )
            .timeout(const Duration(seconds: 10));

        if (paymentsRes.statusCode >= 300) {
          throw SyncException(
            'Failed to upsert sale payments: ${paymentsRes.body}',
            statusCode: paymentsRes.statusCode,
          );
        }
      }

      PosLogger.instance.info(
        'SupabaseSync',
        'Pushed sale #${saleRow['receipt_number'] ?? saleRow['id']} to cloud',
      );
    } catch (e) {
      if (e is SyncException) rethrow;
      throw SyncException('Network error pushing sale: $e', originalError: e);
    }
  }

  @override
  Future<void> pushReturn(Map<String, dynamic> returnData) async {
    if (_cleanBaseUrl.isEmpty || apiKey.isEmpty) {
      throw const SyncException('Supabase credentials not configured');
    }

    try {
      final returnUri = Uri.parse('$_cleanBaseUrl/rest/v1/returns');
      final res = await _client
          .post(
            returnUri,
            headers: _buildHeaders(upsert: true),
            body: jsonEncode(returnData),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode >= 300) {
        throw SyncException(
          'Failed to upsert return: ${res.body}',
          statusCode: res.statusCode,
        );
      }
    } catch (e) {
      if (e is SyncException) rethrow;
      throw SyncException('Network error pushing return: $e', originalError: e);
    }
  }

  @override
  Future<void> pushProductUpdate(Map<String, dynamic> productData) async {
    if (_cleanBaseUrl.isEmpty || apiKey.isEmpty) {
      throw const SyncException('Supabase credentials not configured');
    }

    try {
      final productUri = Uri.parse('$_cleanBaseUrl/rest/v1/products');
      final res = await _client
          .post(
            productUri,
            headers: _buildHeaders(upsert: true),
            body: jsonEncode(productData),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode >= 300) {
        throw SyncException(
          'Failed to push product update: ${res.body}',
          statusCode: res.statusCode,
        );
      }
      PosLogger.instance.info(
        'SupabaseSync',
        'Pushed product update for ${productData['name'] ?? productData['id']} to cloud',
      );
    } catch (e) {
      if (e is SyncException) rethrow;
      throw SyncException(
        'Network error pushing product update: $e',
        originalError: e,
      );
    }
  }

  @override
  Future<void> pushStockLevels(List<Map<String, dynamic>> stockLevels) async {
    if (_cleanBaseUrl.isEmpty || apiKey.isEmpty) {
      throw const SyncException('Supabase credentials not configured');
    }
    if (stockLevels.isEmpty) return;

    try {
      final stockUri = Uri.parse('$_cleanBaseUrl/rest/v1/stock_levels');
      final res = await _client
          .post(
            stockUri,
            headers: _buildHeaders(upsert: true),
            body: jsonEncode(stockLevels),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode >= 300) {
        throw SyncException(
          'Failed to upsert stock levels: ${res.body}',
          statusCode: res.statusCode,
        );
      }
    } catch (e) {
      if (e is SyncException) rethrow;
      throw SyncException(
        'Network error pushing stock levels: $e',
        originalError: e,
      );
    }
  }

  @override
  Future<List<Map<String, dynamic>>> pullCatalogUpdates({DateTime? since}) async {
    if (_cleanBaseUrl.isEmpty || apiKey.isEmpty) {
      throw const SyncException('Supabase credentials not configured');
    }

    try {
      var query = 'select=*,product_variants(*)';
      if (since != null) {
        query += '&updated_at=gt.${since.toUtc().toIso8601String()}';
      }

      final uri = Uri.parse('$_cleanBaseUrl/rest/v1/products?$query');
      final res = await _client
          .get(uri, headers: _buildHeaders())
          .timeout(const Duration(seconds: 10));

      if (res.statusCode >= 300) {
        throw SyncException(
          'Failed to pull catalog: ${res.body}',
          statusCode: res.statusCode,
        );
      }

      final decoded = jsonDecode(res.body);
      if (decoded is List) {
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (e) {
      if (e is SyncException) rethrow;
      throw SyncException('Network error pulling catalog: $e', originalError: e);
    }
  }
}
