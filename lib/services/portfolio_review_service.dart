import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'api_service.dart';

/// One holding the user typed in or uploaded.
class PfRow {
  String name;
  double invested, current;
  String? date; // yyyy-mm-dd
  PfRow({required this.name, required this.invested, required this.current, this.date});

  factory PfRow.fromJson(Map<String, dynamic> j) => PfRow(
        name: '${j['name'] ?? ''}',
        invested: (j['invested'] as num?)?.toDouble() ?? 0,
        current: (j['current'] as num?)?.toDouble() ?? 0,
        date: j['date'] as String?,
      );

  Map<String, dynamic> toJson() =>
      {'name': name, 'invested': invested, 'current': current, 'date': date};
}

class PortfolioReviewService {
  static const _json = {'Content-Type': 'application/json'};

  static String _err(http.Response r) {
    try {
      final d = (jsonDecode(r.body) as Map<String, dynamic>)['detail'];
      if (d is String) return d;
    } catch (_) {}
    return 'Server answered ${r.statusCode}';
  }

  static Future<List<String>> searchFunds(String q) async {
    final r = await http
        .get(Uri.parse('${ApiService.baseUrl}/portfolio/funds?q=${Uri.encodeQueryComponent(q)}'))
        .timeout(const Duration(seconds: 40));
    if (r.statusCode != 200) return [];
    final l = (jsonDecode(r.body) as Map<String, dynamic>)['funds'] as List;
    return l.map((e) => '$e').toList();
  }

  /// Sends an .xlsx / .csv file; returns {rows, skipped, warnings}.
  static Future<Map<String, dynamic>> parse(String filename, Uint8List bytes) async {
    final r = await http
        .post(Uri.parse('${ApiService.baseUrl}/portfolio/parse'),
            headers: _json,
            body: jsonEncode({'filename': filename, 'data_base64': base64Encode(bytes)}))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw Exception(_err(r));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> review(List<PfRow> rows) async {
    final r = await http
        .post(Uri.parse('${ApiService.baseUrl}/portfolio/review'),
            headers: _json, body: jsonEncode({'holdings': rows.map((e) => e.toJson()).toList()}))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw Exception(_err(r));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}
