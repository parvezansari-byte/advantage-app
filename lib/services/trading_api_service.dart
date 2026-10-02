import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_service.dart';

class TradingApiException implements Exception {
  final String message;
  TradingApiException(this.message);
  @override
  String toString() => message;
}

/// Talks to the /trading/ endpoints on research-api, which proxy your own
/// Dhan account server-side (your Dhan client ID/access token never touch
/// this app). This is personal trading only - one Dhan account, manual
/// orders you explicitly submit.
class TradingApiService {
  static String get _base => ApiService.baseUrl;

  static Map<String, dynamic> _decodeObj(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic>) return body;
      return {'data': body};
    }
    String msg = 'Request failed (${res.statusCode})';
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['detail'] != null) msg = body['detail'].toString();
    } catch (_) {}
    throw TradingApiException(msg);
  }

  static Future<Map<String, dynamic>> getFunds(String ownerEmail) async {
    final res = await http.get(Uri.parse('$_base/trading/$ownerEmail/funds'));
    return _decodeObj(res);
  }

  static Future<List<Map<String, dynamic>>> getHoldings(String ownerEmail) async {
    final res = await http.get(Uri.parse('$_base/trading/$ownerEmail/holdings'));
    final body = _decodeObj(res);
    final list = (body['holdings'] as List? ?? []);
    return list.cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> getPositions(String ownerEmail) async {
    final res = await http.get(Uri.parse('$_base/trading/$ownerEmail/positions'));
    final body = _decodeObj(res);
    final list = (body['positions'] as List? ?? []);
    return list.cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> listOrders(String ownerEmail) async {
    final res = await http.get(Uri.parse('$_base/trading/$ownerEmail/orders'));
    final body = _decodeObj(res);
    final list = (body['orders'] as List? ?? []);
    return list.cast<Map<String, dynamic>>();
  }

  static Future<double> getLtp(String ownerEmail, {required String symbol, String exchange = 'NSE'}) async {
    final uri = Uri.parse('$_base/trading/$ownerEmail/ltp')
        .replace(queryParameters: {'symbol': symbol, 'exchange': exchange});
    final res = await http.get(uri);
    final body = _decodeObj(res);
    return double.tryParse('${body['ltp'] ?? 0}') ?? 0;
  }

  static Future<Map<String, dynamic>> getQuote(String ownerEmail, {required String symbol, String exchange = 'NSE'}) async {
    final uri = Uri.parse('$_base/trading/$ownerEmail/quote')
        .replace(queryParameters: {'symbol': symbol, 'exchange': exchange});
    final res = await http.get(uri);
    return _decodeObj(res);
  }

  static Future<Map<String, dynamic>> placeOrder(
    String ownerEmail, {
    required String tradingSymbol,
    required int quantity,
    required String transactionType, // BUY / SELL
    String orderType = 'MARKET', // MARKET / LIMIT / STOP_LOSS / STOP_LOSS_MARKET
    String productType = 'CNC', // CNC / INTRADAY / MARGIN
    String exchange = 'NSE',
    double price = 0,
    double triggerPrice = 0,
    String validity = 'DAY',
  }) async {
    final res = await http.post(
      Uri.parse('$_base/trading/$ownerEmail/order'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'trading_symbol': tradingSymbol,
        'quantity': quantity,
        'transaction_type': transactionType,
        'order_type': orderType,
        'product_type': productType,
        'exchange': exchange,
        'price': price,
        'trigger_price': triggerPrice,
        'validity': validity,
      }),
    );
    return _decodeObj(res);
  }

  static Future<Map<String, dynamic>> cancelOrder(String ownerEmail, {required String orderId}) async {
    final res = await http.post(
      Uri.parse('$_base/trading/$ownerEmail/order/cancel'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'order_id': orderId}),
    );
    return _decodeObj(res);
  }
}
