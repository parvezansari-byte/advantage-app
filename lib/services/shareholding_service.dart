import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

/// One quarter of the shareholding pattern. Percentages; null = not reported.
class ShareholdingQuarter {
  final String date;
  final double? promoter, public, fii, dii, mf, retail, other;
  final double? promoterChg, fiiChg, diiChg;
  const ShareholdingQuarter({
    required this.date,
    this.promoter,
    this.public,
    this.fii,
    this.dii,
    this.mf,
    this.retail,
    this.other,
    this.promoterChg,
    this.fiiChg,
    this.diiChg,
  });

  static double? _d(dynamic v) => v is num ? v.toDouble() : null;

  factory ShareholdingQuarter.fromJson(Map<String, dynamic> j) =>
      ShareholdingQuarter(
        date: (j['date'] ?? '').toString(),
        promoter: _d(j['promoter']),
        public: _d(j['public']),
        fii: _d(j['fii']),
        dii: _d(j['dii']),
        mf: _d(j['mf']),
        retail: _d(j['retail']),
        other: _d(j['other']),
        promoterChg: _d(j['promoter_chg']),
        fiiChg: _d(j['fii_chg']),
        diiChg: _d(j['dii_chg']),
      );

  /// Public holding that is not FII or DII (retail, companies, trusts ...).
  /// Public shareholding already includes the institutions, so they are
  /// taken out to keep the bar from counting them twice.
  double? get publicRest {
    if (public == null) return null;
    final rest = public! - (fii ?? 0) - (dii ?? 0);
    return rest < 0 ? 0 : rest;
  }
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
    // Render's free tier can take ~50 s to wake up, and the first lookup of a
    // stock reads several filings, so allow for that.
    final r = await http
        .get(Uri.parse(
            '${ApiService.baseUrl}/shareholding/${Uri.encodeComponent(symbol)}'))
        .timeout(const Duration(seconds: 90));
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
