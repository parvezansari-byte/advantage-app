import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

/// One quarter of the shareholding pattern. Percentages; null = not reported.
class ShareholdingQuarter {
  final String date;
  final double? promoter, public, fii, dii, other, promoterChg;
  const ShareholdingQuarter(this.date, this.promoter, this.public, this.fii,
      this.dii, this.other, this.promoterChg);

  static double? _d(dynamic v) => v is num ? v.toDouble() : null;

  factory ShareholdingQuarter.fromJson(Map<String, dynamic> j) =>
      ShareholdingQuarter(
        (j['date'] ?? '').toString(),
        _d(j['promoter']),
        _d(j['public']),
        _d(j['fii']),
        _d(j['dii']),
        _d(j['other']),
        _d(j['promoter_chg']),
      );
}

class ShareholdingResult {
  final String symbol;
  final List<ShareholdingQuarter> quarters;
  final bool stale;
  const ShareholdingResult(this.symbol, this.quarters, this.stale);
  ShareholdingQuarter? get latest => quarters.isEmpty ? null : quarters.first;
}

class ShareholdingService {
  static Future<ShareholdingResult> fetch(String symbol) async {
    // Render's free tier can take ~50 s to wake up, so allow for that.
    final r = await http
        .get(Uri.parse(
            '${ApiService.baseUrl}/shareholding/${Uri.encodeComponent(symbol)}'))
        .timeout(const Duration(seconds: 70));
    if (r.statusCode != 200) {
      throw Exception('Shareholding is not available right now');
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final qs = ((j['quarters'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => ShareholdingQuarter.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return ShareholdingResult(symbol, qs, j['stale'] == true);
  }
}
