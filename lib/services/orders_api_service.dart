// lib/services/orders_api_service.dart
//
// Talks to the research-api backend's mutual fund order endpoints
// (/crm/{owner}/clients/{id}/orders etc.). The server decides whether orders
// are simulated (NSE_MODE=stub) or real (NSE_MODE=live) and reports which in
// every order it returns, so the app can show a clear TEST / LIVE banner.

import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'api_service.dart' show ApiService;
import 'crm_api_service.dart' show CrmApiException;

class CrmOrder {
  final int id;
  final String schemeCode;
  final String schemeName;
  final String orderType; // PURCHASE | SIP | REDEEM
  final double? amount;
  final double? units;
  final int? sipDay;
  final int? sipInstallments;
  final String status;
  final String mode; // STUB | LIVE
  final String? nseOrderRef;
  final String? failureReason;
  final String? createdAt;
  final bool duplicate; // server returned an order already placed with this key

  const CrmOrder({
    required this.id,
    required this.schemeCode,
    required this.schemeName,
    required this.orderType,
    this.amount,
    this.units,
    this.sipDay,
    this.sipInstallments,
    required this.status,
    required this.mode,
    this.nseOrderRef,
    this.failureReason,
    this.createdAt,
    this.duplicate = false,
  });

  bool get isFinal =>
      status == 'ALLOTTED' || status == 'FAILED' || status == 'CANCELLED';

  factory CrmOrder.fromJson(Map<String, dynamic> j) => CrmOrder(
        id: (j['id'] as num).toInt(),
        schemeCode: (j['scheme_code'] ?? '').toString(),
        schemeName: (j['scheme_name'] ?? '').toString(),
        orderType: (j['order_type'] ?? '').toString(),
        amount: j['amount'] == null ? null : double.tryParse('${j['amount']}'),
        units: j['units'] == null ? null : double.tryParse('${j['units']}'),
        sipDay: j['sip_day'] == null ? null : (j['sip_day'] as num).toInt(),
        sipInstallments: j['sip_installments'] == null
            ? null
            : (j['sip_installments'] as num).toInt(),
        status: (j['status'] ?? 'CREATED').toString(),
        mode: (j['mode'] ?? 'STUB').toString(),
        nseOrderRef: j['nse_order_ref']?.toString(),
        failureReason: j['failure_reason']?.toString(),
        createdAt: j['created_at']?.toString(),
        duplicate: j['duplicate'] == true,
      );
}

class OrdersApiService {
  static String get _baseUrl => ApiService.baseUrl;

  // Render's free tier can take ~30s to wake up, so be patient.
  static const _timeout = Duration(seconds: 45);

  /// One key per intended order. The server returns the existing order if it
  /// sees the same key twice, so a retry after a dropped connection can never
  /// place the order twice.
  static String newIdempotencyKey() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic>) return body;
      return {'data': body};
    }
    String msg = 'Request failed (${res.statusCode})';
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['detail'] != null) {
        final d = body['detail'];
        if (d is List && d.isNotEmpty && d.first is Map) {
          msg = (d.first as Map)['msg']?.toString() ?? msg;
        } else {
          msg = d.toString();
        }
      }
    } catch (_) {}
    throw CrmApiException(msg);
  }

  static Future<CrmOrder> placeOrder(
    String ownerEmail,
    int clientId, {
    required String schemeCode,
    required String schemeName,
    required String orderType,
    double? amount,
    double? units,
    int? sipDay,
    int? sipInstallments,
    required String idempotencyKey,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_baseUrl/crm/$ownerEmail/clients/$clientId/orders'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'scheme_code': schemeCode,
            'scheme_name': schemeName,
            'order_type': orderType,
            'amount': amount,
            'units': units,
            'sip_day': sipDay,
            'sip_installments': sipInstallments,
            'idempotency_key': idempotencyKey,
            'confirmed': true, // only ever sent after the user taps Confirm
          }),
        )
        .timeout(_timeout);
    return CrmOrder.fromJson(_decode(res));
  }

  static Future<(List<CrmOrder>, String)> listOrders(
      String ownerEmail, int clientId) async {
    final res = await http
        .get(Uri.parse('$_baseUrl/crm/$ownerEmail/clients/$clientId/orders'))
        .timeout(_timeout);
    final body = _decode(res);
    final list = (body['orders'] as List? ?? []);
    final orders = list
        .map((e) => CrmOrder.fromJson(e as Map<String, dynamic>))
        .toList();
    return (orders, (body['mode'] ?? 'STUB').toString());
  }

  static Future<CrmOrder> cancelOrder(String ownerEmail, int orderId) async {
    final res = await http
        .post(Uri.parse('$_baseUrl/crm/$ownerEmail/orders/$orderId/cancel'))
        .timeout(_timeout);
    return CrmOrder.fromJson(_decode(res));
  }
}
