import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

double? _d(dynamic v) => v is num ? v.toDouble() : null;

class AllocFund {
  final String name, category;
  final double? aum, expenseRatio, r1y, r3y, r5y, sharpe;
  const AllocFund({
    required this.name,
    required this.category,
    this.aum,
    this.expenseRatio,
    this.r1y,
    this.r3y,
    this.r5y,
    this.sharpe,
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
      );

  /// Drops the plan suffix the snapshot puts on every name.
  String get shortName => name
      .replaceAll(RegExp(r'\s*-\s*Regular Plan\s*-\s*Growth', caseSensitive: false), '')
      .replaceAll(RegExp(r'-Reg\(G\)|\(G\)|-Reg', caseSensitive: false), '')
      .trim();
}

class AllocReturn {
  final double cagr;
  final double? historical;
  final String basis;
  final bool hypothetical;
  const AllocReturn(this.cagr, this.historical, this.basis, this.hypothetical);

  factory AllocReturn.fromJson(Map<String, dynamic> j) => AllocReturn(
        _d(j['cagr']) ?? 0,
        _d(j['historical']),
        '${j['basis'] ?? ''}',
        j['hypothetical'] == true,
      );
}

class AllocBucket {
  final int pct;
  final double amount;
  final AllocFund? fund;
  final AllocReturn ret;
  const AllocBucket(this.pct, this.amount, this.fund, this.ret);
}

class AllocPoint {
  final int year;
  final double invested, low, base, high;
  const AllocPoint(this.year, this.invested, this.low, this.base, this.high);
}

class AllocPlan {
  final String mode, how;
  final int years, equityPct, debtPct;
  final bool autoSplit, hypothetical;
  final AllocBucket equity, debt;
  final double portBase, portLow, portHigh;
  final List<AllocPoint> points;
  final double invested, low, base, high;
  final List<String> notes;
  const AllocPlan({
    required this.mode,
    required this.how,
    required this.years,
    required this.equityPct,
    required this.debtPct,
    required this.autoSplit,
    required this.hypothetical,
    required this.equity,
    required this.debt,
    required this.portBase,
    required this.portLow,
    required this.portHigh,
    required this.points,
    required this.invested,
    required this.low,
    required this.base,
    required this.high,
    required this.notes,
  });

  factory AllocPlan.fromJson(Map<String, dynamic> j) {
    final split = Map<String, dynamic>.from(j['split'] as Map);
    final rets = Map<String, dynamic>.from(j['returns'] as Map);
    AllocBucket bucket(String key) {
      final b = Map<String, dynamic>.from(split[key] as Map);
      final f = b['fund'];
      return AllocBucket(
        (b['pct'] as num).toInt(),
        (b['amount'] as num).toDouble(),
        f is Map ? AllocFund.fromJson(Map<String, dynamic>.from(f)) : null,
        AllocReturn.fromJson(Map<String, dynamic>.from(rets[key] as Map)),
      );
    }

    final port = Map<String, dynamic>.from(rets['portfolio'] as Map);
    final sum = Map<String, dynamic>.from(j['summary'] as Map);
    final pts = ((j['projection'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => AllocPoint(
              (e['year'] as num).toInt(),
              (e['invested'] as num).toDouble(),
              (e['low'] as num).toDouble(),
              (e['base'] as num).toDouble(),
              (e['high'] as num).toDouble(),
            ))
        .toList();
    return AllocPlan(
      mode: '${j['mode']}',
      how: '${j['how'] ?? ''}',
      years: (j['years'] as num).toInt(),
      equityPct: (j['equity_pct'] as num).toInt(),
      debtPct: (j['debt_pct'] as num).toInt(),
      autoSplit: j['auto_split'] == true,
      hypothetical: j['hypothetical'] == true,
      equity: bucket('equity'),
      debt: bucket('debt'),
      portBase: _d(port['base']) ?? 0,
      portLow: _d(port['low']) ?? 0,
      portHigh: _d(port['high']) ?? 0,
      points: pts,
      invested: _d(sum['invested']) ?? 0,
      low: _d(sum['low']) ?? 0,
      base: _d(sum['base']) ?? 0,
      high: _d(sum['high']) ?? 0,
      notes: ((j['notes'] as List?) ?? []).map((e) => '$e').toList(),
    );
  }
}

class AllocOptions {
  final List<AllocFund> equity, debt;
  const AllocOptions(this.equity, this.debt);
}

class AllocationService {
  static List<AllocFund> _funds(dynamic v) => ((v as List?) ?? [])
      .whereType<Map>()
      .map((e) => AllocFund.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  static Future<AllocOptions> options() async {
    final r = await http
        .get(Uri.parse('${ApiService.baseUrl}/allocation/options'))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) {
      throw Exception('Could not load the fund list');
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return AllocOptions(_funds(j['equity']), _funds(j['debt']));
  }

  static Future<AllocPlan> plan({
    required String mode,
    required double amount,
    required int years,
    required String risk,
    int? equityPct,
    String? equityFund,
    String? debtFund,
  }) async {
    final q = <String, String>{
      'mode': mode,
      'amount': amount.toStringAsFixed(0),
      'years': '$years',
      'risk': risk,
    };
    if (equityPct != null) q['equity_pct'] = '$equityPct';
    if (equityFund != null) q['equity_fund'] = equityFund;
    if (debtFund != null) q['debt_fund'] = debtFund;
    final uri = Uri.parse('${ApiService.baseUrl}/allocation/plan')
        .replace(queryParameters: q);
    final r = await http.get(uri).timeout(const Duration(seconds: 60));
    if (r.statusCode == 200) {
      return AllocPlan.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    }
    String msg = 'Could not build the allocation';
    try {
      final d = (jsonDecode(r.body) as Map<String, dynamic>)['detail'];
      if (d is String) msg = d;
    } catch (_) {}
    throw Exception(msg);
  }
}
