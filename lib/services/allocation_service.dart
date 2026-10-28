import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'api_service.dart';

double? _d(dynamic v) => v is num ? v.toDouble() : null;

/// A fund, either in a dropdown list or as a row of a plan.
class AllocFund {
  final String name, category;
  final double? aum, expenseRatio, r1y, r3y, r5y, sharpe;
  final bool hasHistory;
  // Plan rows only:
  final double weight, share, expected;
  final double? historical;
  final int amount;
  final String basis;
  final bool hypothetical;

  const AllocFund({
    required this.name,
    required this.category,
    this.aum,
    this.expenseRatio,
    this.r1y,
    this.r3y,
    this.r5y,
    this.sharpe,
    this.hasHistory = true,
    this.weight = 0,
    this.share = 0,
    this.expected = 0,
    this.historical,
    this.amount = 0,
    this.basis = '',
    this.hypothetical = false,
  });

  factory AllocFund.fromJson(Map<String, dynamic> j) => AllocFund(
        name: '${j['name'] ?? ''}',
        category: '${j['category'] ?? ''}',
        aum: _d(j['aum']),
        expenseRatio: _d(j['expense_ratio']),
        r1y: _d(j['r_1y']),
        r3y: _d(j['r_3y']),
        r5y: _d(j['r_5y']),
        sharpe: _d(j['sharpe']),
        hasHistory: j['has_history'] != false,
        weight: _d(j['weight']) ?? 0,
        share: _d(j['share']) ?? 0,
        expected: _d(j['expected']) ?? 0,
        historical: _d(j['historical']),
        amount: (j['amount'] is num) ? (j['amount'] as num).round() : 0,
        basis: '${j['basis'] ?? ''}',
        hypothetical: j['hypothetical'] == true,
      );

  /// Drops the plan suffix the snapshot puts on every name.
  String get shortName => name
      .replaceAll(
          RegExp(r'\s*-\s*Regular Plan\s*-\s*Growth', caseSensitive: false), '')
      .replaceAll(RegExp(r'-Reg\(G\)|\(G\)|-Reg', caseSensitive: false), '')
      .trim();
}

class AllocClass {
  final String key, label;
  final double pct;
  final int amount;
  final double? expected, volatility;
  final List<AllocFund> funds;
  const AllocClass({
    required this.key,
    required this.label,
    required this.pct,
    required this.amount,
    required this.funds,
    this.expected,
    this.volatility,
  });

  factory AllocClass.fromJson(Map<String, dynamic> j) => AllocClass(
        key: '${j['key']}',
        label: '${j['label']}',
        pct: _d(j['pct']) ?? 0,
        amount: (j['amount'] as num).round(),
        expected: _d(j['expected']),
        volatility: _d(j['volatility']),
        funds: ((j['funds'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => AllocFund.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class AllocCategory {
  final String cls, category;
  final double share;
  final int amount;
  const AllocCategory(this.cls, this.category, this.share, this.amount);
}

class AllocPoint {
  final int year;
  final double invested, low, base, high;
  const AllocPoint(this.year, this.invested, this.low, this.base, this.high);
}

class AllocPlan {
  final String mode, risk, how;
  final int years;
  final bool auto, normalized, hypothetical;
  final List<AllocClass> classes;
  final List<AllocCategory> byCategory;
  final double portBase, portLow, portHigh;
  final List<AllocPoint> points;
  final double invested, low, base, high;
  final List<String> notes;
  final List<AllocMilestone> milestones;
  final AllocLook? look;
  const AllocPlan({
    required this.mode,
    required this.risk,
    required this.how,
    required this.years,
    required this.auto,
    required this.normalized,
    required this.hypothetical,
    required this.classes,
    required this.byCategory,
    required this.portBase,
    required this.portLow,
    required this.portHigh,
    required this.points,
    required this.invested,
    required this.low,
    required this.base,
    required this.high,
    required this.notes,
    this.milestones = const [],
    this.look,
  });

  AllocClass? classOf(String key) {
    for (final c in classes) {
      if (c.key == key) return c;
    }
    return null;
  }

  factory AllocPlan.fromJson(Map<String, dynamic> j) {
    final port = Map<String, dynamic>.from(
        (j['returns'] as Map)['portfolio'] as Map);
    final sum = Map<String, dynamic>.from(j['summary'] as Map);
    return AllocPlan(
      mode: '${j['mode']}',
      risk: '${j['risk']}',
      how: '${j['how'] ?? ''}',
      years: (j['years'] as num).toInt(),
      auto: j['auto'] == true,
      normalized: j['normalized'] == true,
      hypothetical: j['hypothetical'] == true,
      classes: ((j['classes'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => AllocClass.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      byCategory: ((j['by_category'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => AllocCategory(
                '${e['class']}',
                '${e['category']}',
                _d(e['share']) ?? 0,
                (e['amount'] as num).round(),
              ))
          .toList(),
      portBase: _d(port['base']) ?? 0,
      portLow: _d(port['low']) ?? 0,
      portHigh: _d(port['high']) ?? 0,
      points: ((j['projection'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => AllocPoint(
                (e['year'] as num).toInt(),
                (e['invested'] as num).toDouble(),
                (e['low'] as num).toDouble(),
                (e['base'] as num).toDouble(),
                (e['high'] as num).toDouble(),
              ))
          .toList(),
      invested: _d(sum['invested']) ?? 0,
      low: _d(sum['low']) ?? 0,
      base: _d(sum['base']) ?? 0,
      high: _d(sum['high']) ?? 0,
      notes: ((j['notes'] as List?) ?? []).map((e) => '$e').toList(),
      milestones: ((j['milestones'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => AllocMilestone(
                (e['year'] as num).toInt(),
                (e['invested'] as num).toDouble(),
                (e['low'] as num).toDouble(),
                (e['base'] as num).toDouble(),
                (e['high'] as num).toDouble(),
                (e['gain'] as num).toDouble(),
              ))
          .toList(),
      look: j['look_through'] is Map
          ? AllocLook.fromJson(Map<String, dynamic>.from(j['look_through'] as Map))
          : null,
    );
  }
}

/// Value of the plan at a milestone year (5, 10, 15, 20).
class AllocMilestone {
  final int year;
  final double invested, low, base, high, gain;
  const AllocMilestone(this.year, this.invested, this.low, this.base, this.high, this.gain);
}

/// One stock or bond issuer inside the chosen funds. [sub] is the sector or the rating.
class AllocHolding {
  final String name, sub;
  final double pct;
  final int amount;
  const AllocHolding(this.name, this.sub, this.pct, this.amount);
}

/// What the chosen funds hold underneath: stocks, bond issuers and sectors.
class AllocLook {
  final List<AllocHolding> stocks, bonds;
  final List<MapEntry<String, double>> sectors;
  final double stocksTotal, bondsTotal, coveredPct;
  final List<String> without;
  final String asOn;
  const AllocLook({
    required this.stocks,
    required this.bonds,
    required this.sectors,
    required this.stocksTotal,
    required this.bondsTotal,
    required this.coveredPct,
    required this.without,
    required this.asOn,
  });

  bool get isEmpty => stocks.isEmpty && bonds.isEmpty;

  static List<AllocHolding> _list(dynamic v, String subKey) => ((v as List?) ?? [])
      .whereType<Map>()
      .map((e) => AllocHolding('${e['name']}', '${e[subKey] ?? ''}', _d(e['pct']) ?? 0,
          ((e['amount'] as num?) ?? 0).round()))
      .toList();

  factory AllocLook.fromJson(Map<String, dynamic> j) => AllocLook(
        stocks: _list(j['stocks'], 'sector'),
        bonds: _list(j['bonds'], 'rating'),
        sectors: ((j['sectors'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => MapEntry('${e['sector']}', _d(e['pct']) ?? 0))
            .toList(),
        stocksTotal: _d(j['stocks_total']) ?? 0,
        bondsTotal: _d(j['bonds_total']) ?? 0,
        coveredPct: _d(j['covered_pct']) ?? 0,
        without: ((j['without'] as List?) ?? []).map((e) => '$e').toList(),
        asOn: '${j['as_on'] ?? ''}',
      );
}

/// class key -> category -> funds
class AllocOptions {
  final Map<String, Map<String, List<AllocFund>>> byClass;
  const AllocOptions(this.byClass);

  List<String> categories(String cls) =>
      (byClass[cls] ?? const <String, List<AllocFund>>{}).keys.toList();

  List<AllocFund> funds(String cls, String category) =>
      (byClass[cls] ?? const <String, List<AllocFund>>{})[category] ??
      const <AllocFund>[];
}

/// What the user asked for. [classes] and [picks] stay null in Auto mode.
class AllocRequest {
  final String mode, risk;
  final double amount;
  final int years;
  final Map<String, double>? classes;
  final Map<String, List<MapEntry<String, double>>>? picks; // name -> weight

  const AllocRequest({
    required this.mode,
    required this.amount,
    required this.years,
    required this.risk,
    this.classes,
    this.picks,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'mode': mode,
      'amount': amount,
      'years': years,
      'risk': risk,
    };
    if (classes != null) m['classes'] = classes;
    if (picks != null) {
      m['picks'] = {
        for (final e in picks!.entries)
          e.key: [
            for (final p in e.value) {'name': p.key, 'weight': p.value}
          ],
      };
    }
    return m;
  }
}

class AllocationService {
  static const _json = {'Content-Type': 'application/json'};

  static String _error(http.Response r, String fallback) {
    try {
      final d = (jsonDecode(r.body) as Map<String, dynamic>)['detail'];
      if (d is String) return d;
    } catch (_) {}
    return fallback;
  }

  static Future<AllocOptions> options() async {
    final r = await http
        .get(Uri.parse('${ApiService.baseUrl}/allocation/options'))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) {
      throw Exception('Could not load the fund list');
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final out = <String, Map<String, List<AllocFund>>>{};
    for (final cls in j.keys) {
      final cats = Map<String, dynamic>.from(j[cls] as Map);
      out[cls] = {
        for (final c in cats.entries)
          c.key: ((c.value as List?) ?? [])
              .whereType<Map>()
              .map((e) => AllocFund.fromJson(Map<String, dynamic>.from(e)))
              .toList(),
      };
    }
    return AllocOptions(out);
  }

  static Future<AllocPlan> plan(AllocRequest req) async {
    final r = await http
        .post(Uri.parse('${ApiService.baseUrl}/allocation/plan'),
            headers: _json, body: jsonEncode(req.toJson()))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode == 200) {
      return AllocPlan.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    }
    throw Exception(_error(r, 'Could not build the allocation'));
  }

  static Future<Uint8List> pdf(AllocRequest req) async {
    final r = await http
        .post(Uri.parse('${ApiService.baseUrl}/allocation/pdf'),
            headers: _json, body: jsonEncode(req.toJson()))
        .timeout(const Duration(seconds: 90));
    if (r.statusCode == 200) return r.bodyBytes;
    throw Exception(_error(r, 'Could not create the PDF'));
  }
}
