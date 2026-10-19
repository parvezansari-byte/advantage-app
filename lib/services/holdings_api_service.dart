// lib/services/holdings_api_service.dart
//
// Talks to the research-api backend's manual-holdings endpoints
// (/crm/{owner}/clients/{id}/portfolio etc.). The server values each holding
// at the latest NAV, so the app just displays what it receives.

import 'dart:convert';

import 'authed_http.dart' as http;

import 'api_service.dart' show ApiService;
import 'crm_api_service.dart' show CrmApiException;

double? _num(dynamic v) => v == null ? null : double.tryParse('$v');

class ManualHolding {
  final int id;
  final String schemeCode;
  final String schemeName;
  final String folioNumber; // '' when not recorded
  final double units;
  final double avgNav;
  final double invested;
  final double? currentNav; // null when the NAV couldn't be fetched
  final String? navDate;
  final double? currentValue;
  final double? gain;
  final double? gainPct;

  const ManualHolding({
    required this.id,
    required this.schemeCode,
    required this.schemeName,
    required this.folioNumber,
    required this.units,
    required this.avgNav,
    required this.invested,
    this.currentNav,
    this.navDate,
    this.currentValue,
    this.gain,
    this.gainPct,
  });

  factory ManualHolding.fromJson(Map<String, dynamic> j) => ManualHolding(
        id: (j['id'] as num).toInt(),
        schemeCode: (j['scheme_code'] ?? '').toString(),
        schemeName: (j['scheme_name'] ?? '').toString(),
        folioNumber: (j['folio_number'] ?? '').toString(),
        units: _num(j['units']) ?? 0,
        avgNav: _num(j['avg_nav']) ?? 0,
        invested: _num(j['invested']) ?? 0,
        currentNav: _num(j['current_nav']),
        navDate: j['nav_date']?.toString(),
        currentValue: _num(j['current_value']),
        gain: _num(j['gain']),
        gainPct: _num(j['gain_pct']),
      );
}

class PortfolioTotals {
  final double invested;
  final double currentValue;
  final double gain;
  final double? gainPct;
  final int priced; // holdings that got a live NAV
  final int total;

  const PortfolioTotals({
    required this.invested,
    required this.currentValue,
    required this.gain,
    this.gainPct,
    required this.priced,
    required this.total,
  });

  factory PortfolioTotals.fromJson(Map<String, dynamic> j) => PortfolioTotals(
        invested: _num(j['invested']) ?? 0,
        currentValue: _num(j['current_value']) ?? 0,
        gain: _num(j['gain']) ?? 0,
        gainPct: _num(j['gain_pct']),
        priced: (j['priced'] as num? ?? 0).toInt(),
        total: (j['total'] as num? ?? 0).toInt(),
      );
}

class Portfolio {
  final List<ManualHolding> holdings;
  final PortfolioTotals totals;
  const Portfolio(this.holdings, this.totals);
}

class HoldingsApiService {
  static String get _baseUrl => ApiService.baseUrl;
  static const _timeout = Duration(seconds: 45);

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

  static Future<Portfolio> getPortfolio(String ownerEmail, int clientId) async {
    final res = await http
        .get(Uri.parse('$_baseUrl/crm/$ownerEmail/clients/$clientId/portfolio'))
        .timeout(_timeout);
    final body = _decode(res);
    final list = (body['holdings'] as List? ?? []);
    return Portfolio(
      list
          .map((e) => ManualHolding.fromJson(e as Map<String, dynamic>))
          .toList(),
      PortfolioTotals.fromJson(
          (body['totals'] as Map?)?.cast<String, dynamic>() ?? {}),
    );
  }

  /// Adds units. If the client already holds this fund (same folio), the
  /// server merges them in and recomputes the average NAV.
  static Future<void> addHolding(
    String ownerEmail,
    int clientId, {
    required String schemeCode,
    required String schemeName,
    required double units,
    required double avgNav,
    String? folioNumber,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_baseUrl/crm/$ownerEmail/clients/$clientId/portfolio'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'scheme_code': schemeCode,
            'scheme_name': schemeName,
            'units': units,
            'avg_nav': avgNav,
            'folio_number': folioNumber,
          }),
        )
        .timeout(_timeout);
    _decode(res);
  }

  static Future<void> updateHolding(
    String ownerEmail,
    int holdingId, {
    required double units,
    required double avgNav,
    String? folioNumber,
  }) async {
    final res = await http
        .put(
          Uri.parse('$_baseUrl/crm/$ownerEmail/portfolio/$holdingId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'units': units,
            'avg_nav': avgNav,
            'folio_number': folioNumber ?? '',
          }),
        )
        .timeout(_timeout);
    _decode(res);
  }

  static Future<void> deleteHolding(String ownerEmail, int holdingId) async {
    final res = await http
        .delete(Uri.parse('$_baseUrl/crm/$ownerEmail/portfolio/$holdingId'))
        .timeout(_timeout);
    _decode(res);
  }
}
