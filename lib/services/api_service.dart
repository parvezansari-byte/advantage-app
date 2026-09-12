// lib/services/api_service.dart
//
// Talks to your Python FastAPI backend (api.py).
//
// IMPORTANT — the base URL depends on where you run the app:
//
//   Android emulator : http://10.0.2.2:8000   <-- 10.0.2.2 is the emulator's
//                                                 alias for your PC's localhost.
//                                                 "localhost" would mean the
//                                                 emulator itself, which has no
//                                                 server running.
//   Real phone (USB) : http://<YOUR-PC-IP>:8000   e.g. http://192.168.1.5:8000
//                      (find it with `ipconfig` in PowerShell)
//   Deployed backend : https://your-api.onrender.com

import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // The deployed backend on Render.
  static const String baseUrl = 'https://research-api-8a34.onrender.com';

  static const Duration _timeout = Duration(seconds: 30);

  /// Health check — call this first to prove the phone can reach the API.
  static Future<bool> ping() async {
    try {
      final r = await http.get(Uri.parse(baseUrl)).timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Live market indices (NIFTY, SENSEX, Bank NIFTY, sectors).
  static Future<List<dynamic>> getIndices() async {
    final r = await http.get(Uri.parse('$baseUrl/indices')).timeout(_timeout);
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return (data['indices'] as List<dynamic>?) ?? [];
    }
    throw ApiException('Could not load market indices');
  }

  /// The full searchable stock universe (~500 NIFTY names).
  static Future<List<String>> getStockList() async {
    final r =
        await http.get(Uri.parse('$baseUrl/stocks/list')).timeout(_timeout);
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return ((data['symbols'] as List<dynamic>?) ?? [])
          .map((e) => e.toString())
          .toList();
    }
    throw ApiException('Could not load stock list');
  }

  /// Same universe, but with sector + market-cap category attached to
  /// each stock, and the full sector list - powers the search filters.
  static Future<Map<String, dynamic>> getStockListDetailed() async {
    final r = await http
        .get(Uri.parse('$baseUrl/stocks/list/detailed'))
        .timeout(_timeout);
    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    throw ApiException('Could not load detailed stock list');
  }

  /// Fundamentals + technicals for one stock, e.g. "RELIANCE".
  static Future<Map<String, dynamic>> getStock(String symbol) async {
    final r = await http
        .get(Uri.parse('$baseUrl/stock/$symbol'))
        .timeout(_timeout);

    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    if (r.statusCode == 404) {
      throw ApiException("No data found for '$symbol'. Check the symbol.");
    }
    throw ApiException('Server error (${r.statusCode}). Is the API running?');
  }

  /// Price history for charting.
  static Future<List<dynamic>> getHistory(String symbol,
      {String period = '1y'}) async {
    final r = await http
        .get(Uri.parse('$baseUrl/stock/$symbol/history?period=$period'))
        .timeout(_timeout);

    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return (data['candles'] as List<dynamic>?) ?? [];
    }
    throw ApiException('Could not load history for $symbol');
  }

  /// Annual financial statements (income, balance sheet, cash flow) in ₹ crore.
  static Future<Map<String, dynamic>> getStatements(String symbol) async {
    final r = await http
        .get(Uri.parse('$baseUrl/stock/$symbol/statements'))
        .timeout(_timeout);

    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    throw ApiException('Could not load statements for $symbol');
  }

  /// Search Indian mutual funds by name.
  static Future<List<dynamic>> searchFunds(String query) async {
    final r = await http
        .get(Uri.parse('$baseUrl/funds/search?q=$query'))
        .timeout(_timeout);

    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return (data['results'] as List<dynamic>?) ?? [];
    }
    throw ApiException('Fund search failed');
  }

  /// NAV history + metadata for one scheme.
  static Future<Map<String, dynamic>> getFund(String schemeCode) async {
    final r = await http
        .get(Uri.parse('$baseUrl/funds/$schemeCode'))
        .timeout(_timeout);

    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    throw ApiException('Could not load fund $schemeCode');
  }

  // =========================================================================
  // MUTUAL FUNDS — category browsing, analysis and SIP backtests
  // =========================================================================

  /// The fund categories available to browse.
  static Future<List<String>> getFundCategories() async {
    final r = await http
        .get(Uri.parse('$baseUrl/funds/categories'))
        .timeout(_timeout);
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return ((data['categories'] as List<dynamic>?) ?? [])
          .map((e) => e.toString())
          .toList();
    }
    throw ApiException('Could not load fund categories');
  }

  /// Every fund in one category, with live returns, ranked by [sort].
  ///
  /// Each scheme is a separate upstream lookup, so this can take a few
  /// seconds on a cold start.
  static Future<List<dynamic>> getFundsByCategory(String category,
      {String sort = 'return_3y'}) async {
    final encoded = Uri.encodeComponent(category);
    final r = await http
        .get(Uri.parse('$baseUrl/funds/category/$encoded?sort=$sort'))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return (data['funds'] as List<dynamic>?) ?? [];
    }
    if (r.statusCode == 404) {
      throw ApiException('Unknown category: $category');
    }
    throw ApiException('Could not load $category funds');
  }

  /// Returns, risk figures and a NAV series for one scheme.
  static Future<Map<String, dynamic>> getFundAnalysis(String schemeCode) async {
    final r = await http
        .get(Uri.parse('$baseUrl/funds/$schemeCode/analysis'))
        .timeout(const Duration(seconds: 45));
    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    if (r.statusCode == 422) {
      throw ApiException('Not enough NAV history to analyse this scheme');
    }
    throw ApiException('Could not analyse fund $schemeCode');
  }

  /// What a monthly SIP into this scheme would actually have been worth.
  static Future<Map<String, dynamic>> getSipBacktest(String schemeCode,
      {double monthly = 10000, int years = 5}) async {
    final r = await http
        .get(Uri.parse(
            '$baseUrl/funds/$schemeCode/sip-backtest?monthly=$monthly&years=$years'))
        .timeout(const Duration(seconds: 45));
    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    if (r.statusCode == 422) {
      throw ApiException(
          'This scheme has less than $years years of history. Try a shorter '
          'period.');
    }
    throw ApiException('Backtest failed for $schemeCode');
  }

  // =========================================================================
  // MARKET NEWS & INSTITUTIONAL FLOWS
  // =========================================================================

  /// Live market news from Indian financial RSS feeds, newest first.
  ///
  /// Optionally filter by [sentiment] ("Positive"/"Negative"/"Neutral") or
  /// [impact] ("High"/"Medium"/"Low").
  static Future<Map<String, dynamic>> getNews({
    int limit = 60,
    String sentiment = '',
    String impact = '',
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if (sentiment.isNotEmpty) params['sentiment'] = sentiment;
    if (impact.isNotEmpty) params['impact'] = impact;

    final uri = Uri.parse('$baseUrl/news').replace(queryParameters: params);
    final r = await http.get(uri).timeout(const Duration(seconds: 45));

    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    if (r.statusCode == 503) {
      throw ApiException('News service is unavailable on the server');
    }
    throw ApiException('Could not load market news');
  }

  /// Daily FII/DII cash-market activity in Rs crore.
  static Future<Map<String, dynamic>> getFiiDii() async {
    final r = await http
        .get(Uri.parse('$baseUrl/fii-dii'))
        .timeout(const Duration(seconds: 45));

    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    if (r.statusCode == 503) {
      throw ApiException(
          "FII/DII data isn't reachable right now. NSE blocks cloud servers, "
          "and the backup sources didn't respond either.");
    }
    throw ApiException('Could not load FII/DII flows');
  }

  /// Daily FII/DII net flows for the last [days] sessions, oldest first.
  static Future<Map<String, dynamic>> getFiiDiiHistory({int days = 30}) async {
    final r = await http
        .get(Uri.parse('$baseUrl/fii-dii/history?days=$days'))
        .timeout(const Duration(seconds: 45));

    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    throw ApiException('Could not load FII/DII history');
  }

  /// NSE sector index performance, ranked by 1-month return.
  ///
  /// [compare] selects the long window shown alongside 1D and 1M:
  /// one of '1y', '2y', '3y', '5y'.
  static Future<Map<String, dynamic>> getSectors({String compare = '1y'}) async {
    final r = await http
        .get(Uri.parse('$baseUrl/sectors?compare=$compare'))
        .timeout(const Duration(seconds: 60));

    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    throw ApiException('Could not load sector performance');
  }

  /// Price series for the live chart.
  ///
  /// [timeframe] is one of 1D, 1W, 1M, 6M, 1Y, 5Y, ALL. On 1D the change is
  /// measured against the previous close; on longer views against the start
  /// of the window.
  static Future<Map<String, dynamic>> getChart(String symbol,
      {String timeframe = '1D'}) async {
    final encoded = Uri.encodeComponent(symbol);
    final r = await http
        .get(Uri.parse('$baseUrl/chart/$encoded?timeframe=$timeframe'))
        .timeout(const Duration(seconds: 45));

    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    if (r.statusCode == 404) {
      throw ApiException('No chart data for $symbol');
    }
    throw ApiException('Could not load chart for $symbol');
  }

  // =========================================================================
  // OPTION CHAIN
  // =========================================================================

  /// Expiry dates for an index, nearest first.
  static Future<List<String>> getOptionExpiries(String index) async {
    final r = await http
        .get(Uri.parse('$baseUrl/options/expiries')
            .replace(queryParameters: {'index': index}))
        .timeout(const Duration(seconds: 30));

    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return ((data['expiries'] as List?) ?? [])
          .map((e) => e.toString())
          .toList();
    }
    throw ApiException(_optionError(r));
  }

  /// Option chain plus PCR, max pain, support and resistance.
  static Future<Map<String, dynamic>> getOptionChain(
    String index, {
    String expiry = '',
    int strikes = 10,
  }) async {
    final params = {'index': index, 'strikes': '$strikes'};
    if (expiry.isNotEmpty) params['expiry'] = expiry;

    final r = await http
        .get(Uri.parse('$baseUrl/options/chain')
            .replace(queryParameters: params))
        .timeout(const Duration(seconds: 40));

    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    throw ApiException(_optionError(r));
  }

  /// Surfaces Dhan's own message where there is one — an expired token or a
  /// missing Data API subscription both need user action, not a retry.
  static String _optionError(http.Response r) {
    try {
      final body = jsonDecode(r.body);
      if (body is Map && body['detail'] != null) return '${body['detail']}';
    } catch (_) {}
    return 'Option chain request failed (HTTP ${r.statusCode})';
  }

  // =========================================================================
  // FUND DATABASE  (snapshot metrics + live NAV)
  // =========================================================================

  /// Categories grouped by asset class (Equity, Hybrid, Debt, FoFs, Metal).
  static Future<List<dynamic>> getFundDbCategories() async {
    final r = await http
        .get(Uri.parse('$baseUrl/funds/db/categories'))
        .timeout(_timeout);
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return (data['groups'] as List<dynamic>?) ?? [];
    }
    throw ApiException('Could not load fund categories');
  }

  /// Funds in one category with full metrics, ranked by [sort].
  static Future<Map<String, dynamic>> getFundDbList(
    String category, {
    String sort = 'aum',
    int limit = 60,
  }) async {
    final uri = Uri.parse('$baseUrl/funds/db/list').replace(queryParameters: {
      'category': category,
      'sort': sort,
      'limit': '$limit',
    });
    final r = await http.get(uri).timeout(const Duration(seconds: 45));
    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    throw ApiException('Could not load $category funds');
  }

  /// Search the fund database by name.
  static Future<List<dynamic>> searchFundDb(String query) async {
    final uri = Uri.parse('$baseUrl/funds/db/search')
        .replace(queryParameters: {'q': query});
    final r = await http.get(uri).timeout(const Duration(seconds: 30));
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return (data['funds'] as List<dynamic>?) ?? [];
    }
    throw ApiException('Fund search failed');
  }

  /// One fund in full, with category ranks and peer comparison.
  static Future<Map<String, dynamic>> getFundDbDetail(String name) async {
    final uri = Uri.parse('$baseUrl/funds/db/fund')
        .replace(queryParameters: {'name': name});
    final r = await http.get(uri).timeout(const Duration(seconds: 30));
    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    throw ApiException('Could not load fund details');
  }

  // =========================================================================
  // HOLDINGS EXPLORER  (AMC portfolio disclosures)
  // =========================================================================

  /// Coverage of the disclosure snapshot: funds, AMCs, and as-on date.
  static Future<Map<String, dynamic>> getHoldingsSummary() async {
    final r = await http
        .get(Uri.parse('$baseUrl/holdings/summary'))
        .timeout(_timeout);
    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    throw ApiException('Holdings data is unavailable');
  }

  /// Funds in the snapshot, optionally filtered to one AMC.
  static Future<List<dynamic>> getHoldingsFunds({String amc = ''}) async {
    final uri = Uri.parse('$baseUrl/holdings/funds')
        .replace(queryParameters: amc.isEmpty ? null : {'amc': amc});
    final r = await http.get(uri).timeout(_timeout);
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return (data['funds'] as List<dynamic>?) ?? [];
    }
    throw ApiException('Could not load fund list');
  }

  /// Which funds hold a given stock.
  static Future<Map<String, dynamic>> getStockHolders(String query) async {
    final uri = Uri.parse('$baseUrl/holdings/stock')
        .replace(queryParameters: {'q': query});
    final r = await http.get(uri).timeout(const Duration(seconds: 40));
    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    if (r.statusCode == 404) {
      throw ApiException('No security matching "$query"');
    }
    throw ApiException('Stock search failed');
  }

  /// One fund's full portfolio with sector allocation.
  static Future<Map<String, dynamic>> getFundHoldings(String key) async {
    final uri = Uri.parse('$baseUrl/holdings/fund')
        .replace(queryParameters: {'key': key});
    final r = await http.get(uri).timeout(const Duration(seconds: 40));
    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    throw ApiException('Could not load portfolio');
  }

  /// Portfolio overlap between two funds.
  static Future<Map<String, dynamic>> getFundOverlap(
      String keyA, String keyB) async {
    final uri = Uri.parse('$baseUrl/holdings/overlap')
        .replace(queryParameters: {'a': keyA, 'b': keyB});
    final r = await http.get(uri).timeout(const Duration(seconds: 40));
    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    throw ApiException('Overlap comparison failed');
  }

  // =========================================================================
  // STRATEGY BACKTEST
  // =========================================================================

  /// Strategies, their tunable parameters, and available periods.
  static Future<Map<String, dynamic>> getBacktestStrategies() async {
    final r = await http
        .get(Uri.parse('$baseUrl/backtest/strategies'))
        .timeout(_timeout);
    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    throw ApiException('Could not load strategies');
  }

  /// Run a backtest against real historical prices.
  ///
  /// Returns strategy metrics, the Buy & Hold benchmark on the same data,
  /// trade statistics and an equity curve.
  static Future<Map<String, dynamic>> runBacktest({
    required String symbol,
    required String strategy,
    required String period,
    required double capital,
    int fast = 20,
    int slow = 50,
    int rsiWindow = 14,
    double rsiBuy = 30,
    double rsiSell = 60,
    double stopLoss = 10,
    double takeProfit = 20,
    bool useSlTp = false,
  }) async {
    final uri = Uri.parse('$baseUrl/backtest/run').replace(queryParameters: {
      'symbol': symbol,
      'strategy': strategy,
      'period': period,
      'capital': '$capital',
      'fast': '$fast',
      'slow': '$slow',
      'rsi_window': '$rsiWindow',
      'rsi_buy': '$rsiBuy',
      'rsi_sell': '$rsiSell',
      'stop_loss': '$stopLoss',
      'take_profit': '$takeProfit',
      'use_sl_tp': '$useSlTp',
    });

    final r = await http.get(uri).timeout(const Duration(seconds: 60));
    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    // The API explains bad parameters and thin history precisely; pass those
    // through rather than replacing them with something generic.
    try {
      final body = jsonDecode(r.body);
      if (body is Map && body['detail'] != null) {
        throw ApiException('${body['detail']}');
      }
    } on ApiException {
      rethrow;
    } catch (_) {}
    throw ApiException('Backtest failed (HTTP ${r.statusCode})');
  }

  // =========================================================================
  // PORTFOLIO
  // =========================================================================

  /// Saved holdings valued at live prices, with per-position and total P&L.
  static Future<Map<String, dynamic>> getPortfolio(String email) async {
    final r = await http
        .get(Uri.parse('$baseUrl/portfolio/${Uri.encodeComponent(email)}'))
        .timeout(const Duration(seconds: 45));
    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    throw ApiException('Could not load portfolio');
  }

  /// Add to a position. The API merges with any existing holding in the same
  /// symbol at a weighted-average price rather than creating a duplicate.
  static Future<Map<String, dynamic>> addHolding(
    String email, {
    required String symbol,
    required double qty,
    required double avgPrice,
  }) async {
    final r = await http
        .post(
          Uri.parse('$baseUrl/holdings/${Uri.encodeComponent(email)}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'symbol': symbol,
            'qty': qty,
            'avg_price': avgPrice,
          }),
        )
        .timeout(_timeout);
    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    throw ApiException('Could not save holding');
  }

  /// Remove a position entirely.
  static Future<void> deleteHolding(String email, String symbol) async {
    final r = await http
        .delete(Uri.parse(
            '$baseUrl/holdings/${Uri.encodeComponent(email)}/$symbol'))
        .timeout(_timeout);
    if (r.statusCode != 200) {
      throw ApiException('Could not remove $symbol');
    }
  }

  /// Portfolio Doctor — real diagnostics on holdings.
  static Future<Map<String, dynamic>> diagnose(
      List<Map<String, dynamic>> holdings) async {
    final r = await http
        .post(
          Uri.parse('$baseUrl/doctor'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'holdings': holdings}),
        )
        .timeout(_timeout);

    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    throw ApiException('Diagnosis failed (${r.statusCode})');
  }

  /// Portfolio X-ray — look through mutual funds to the stocks inside them.
  ///
  /// funds: [{scheme_code, name, value}, ...]
  static Future<Map<String, dynamic>> xray(
      List<Map<String, dynamic>> funds) async {
    final r = await http
        .post(
          Uri.parse('$baseUrl/xray'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'funds': funds}),
        )
        .timeout(const Duration(seconds: 60)); // holdings lookups are slow

    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    if (r.statusCode == 422) {
      throw ApiException(
          "Couldn't get holdings data for these funds. Coverage isn't complete "
          "across all schemes — and we'd rather show nothing than guess.");
    }
    throw ApiException('X-ray failed (${r.statusCode})');
  }

  // =========================================================================
  // TAX CALCULATOR — transaction ledger + FIFO capital gains
  // =========================================================================

  /// This user's full buy/sell history, oldest first.
  static Future<List<dynamic>> getTransactions(String email) async {
    final r = await http
        .get(Uri.parse('$baseUrl/transactions/${Uri.encodeComponent(email)}'))
        .timeout(_timeout);
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return (data['transactions'] as List<dynamic>?) ?? [];
    }
    throw ApiException('Could not load transactions (${r.statusCode})');
  }

  /// Log a single buy or sell. Each transaction is its own row — not merged
  /// like holdings — since the tax calculator needs every lot's date.
  static Future<void> addTransaction(
    String email, {
    required String symbol,
    required String transactionType, // 'BUY' or 'SELL'
    required double quantity,
    required double price,
    required String tradeDate, // 'YYYY-MM-DD'
    String assetType = 'EQUITY',
  }) async {
    final r = await http
        .post(
          Uri.parse('$baseUrl/transactions/${Uri.encodeComponent(email)}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'symbol': symbol,
            'transaction_type': transactionType,
            'quantity': quantity,
            'price': price,
            'trade_date': tradeDate,
            'asset_type': assetType,
          }),
        )
        .timeout(_timeout);
    if (r.statusCode == 200) return;
    throw ApiException('Could not save transaction (${r.statusCode})');
  }

  /// Remove a single logged transaction.
  static Future<void> deleteTransaction(String email, int transactionId) async {
    final r = await http
        .delete(Uri.parse(
            '$baseUrl/transactions/${Uri.encodeComponent(email)}/$transactionId'))
        .timeout(_timeout);
    if (r.statusCode == 200) return;
    throw ApiException('Could not delete transaction (${r.statusCode})');
  }

  /// FIFO-matched STCG/LTCG report for a financial year, e.g. fy: '2025-26'.
  static Future<Map<String, dynamic>> getTaxReport(
    String email, {
    String fy = '2025-26',
  }) async {
    final r = await http
        .get(Uri.parse('$baseUrl/tax/${Uri.encodeComponent(email)}?fy=$fy'))
        .timeout(const Duration(seconds: 45));
    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    if (r.statusCode == 404) {
      throw ApiException('No transactions logged yet for this financial year');
    }
    throw ApiException('Could not compute tax report (${r.statusCode})');
  }

  // =========================================================================
  // FINANCE TRACKER — expenses, categories, loans, pending dues
  // =========================================================================

  /// All expenses, or pass [month] ('YYYY-MM') to filter to one month.
  static Future<List<dynamic>> getExpenses(String email, {String? month}) async {
    final params = <String, String>{};
    if (month != null) params['month'] = month;
    final uri = Uri.parse('$baseUrl/expenses/${Uri.encodeComponent(email)}')
        .replace(queryParameters: params.isEmpty ? null : params);
    final r = await http.get(uri).timeout(_timeout);
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return (data['expenses'] as List<dynamic>?) ?? [];
    }
    throw ApiException('Could not load expenses (${r.statusCode})');
  }

  static Future<void> addExpense(
    String email, {
    required double amount,
    required String category,
    String? description,
    required String expenseDate, // 'YYYY-MM-DD'
  }) async {
    final r = await http
        .post(
          Uri.parse('$baseUrl/expenses/${Uri.encodeComponent(email)}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'amount': amount,
            'category': category,
            'description': description,
            'expense_date': expenseDate,
          }),
        )
        .timeout(_timeout);
    if (r.statusCode == 200) return;
    throw ApiException('Could not save expense (${r.statusCode})');
  }

  static Future<void> deleteExpense(String email, int expenseId) async {
    final r = await http
        .delete(Uri.parse(
            '$baseUrl/expenses/${Uri.encodeComponent(email)}/$expenseId'))
        .timeout(_timeout);
    if (r.statusCode == 200) return;
    throw ApiException('Could not delete expense (${r.statusCode})');
  }

  /// Category + daily breakdown for a month, or all-time if [month] is null.
  static Future<Map<String, dynamic>> getExpenseSummary(
    String email, {
    String? month,
  }) async {
    final params = <String, String>{};
    if (month != null) params['month'] = month;
    final uri = Uri.parse('$baseUrl/expenses/${Uri.encodeComponent(email)}/summary')
        .replace(queryParameters: params.isEmpty ? null : params);
    final r = await http.get(uri).timeout(_timeout);
    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    throw ApiException('Could not load expense summary (${r.statusCode})');
  }

  /// Merged list: hardcoded defaults + this user's custom categories.
  static Future<List<String>> getCategories(String email) async {
    final r = await http
        .get(Uri.parse('$baseUrl/categories/${Uri.encodeComponent(email)}'))
        .timeout(_timeout);
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return ((data['categories'] as List<dynamic>?) ?? [])
          .map((e) => e.toString())
          .toList();
    }
    throw ApiException('Could not load categories (${r.statusCode})');
  }

  static Future<void> addCategory(String email, String categoryName) async {
    final r = await http
        .post(
          Uri.parse('$baseUrl/categories/${Uri.encodeComponent(email)}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'category_name': categoryName}),
        )
        .timeout(_timeout);
    if (r.statusCode == 200) return;
    throw ApiException('Could not save category (${r.statusCode})');
  }

  /// Returns {loans: [...], total_outstanding_debt, total_monthly_emi, ...}
  static Future<Map<String, dynamic>> getLoans(String email) async {
    final r = await http
        .get(Uri.parse('$baseUrl/loans/${Uri.encodeComponent(email)}'))
        .timeout(_timeout);
    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    throw ApiException('Could not load loans (${r.statusCode})');
  }

  static Future<void> addLoan(
    String email, {
    required String loanName,
    String loanType = 'PERSONAL',
    required double principal,
    required double annualInterestRate,
    required int tenureMonths,
    required String startDate, // 'YYYY-MM-DD'
  }) async {
    final r = await http
        .post(
          Uri.parse('$baseUrl/loans/${Uri.encodeComponent(email)}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'loan_name': loanName,
            'loan_type': loanType,
            'principal': principal,
            'annual_interest_rate': annualInterestRate,
            'tenure_months': tenureMonths,
            'start_date': startDate,
          }),
        )
        .timeout(_timeout);
    if (r.statusCode == 200) return;
    throw ApiException('Could not save loan (${r.statusCode})');
  }

  static Future<void> deleteLoan(String email, int loanId) async {
    final r = await http
        .delete(Uri.parse('$baseUrl/loans/${Uri.encodeComponent(email)}/$loanId'))
        .timeout(_timeout);
    if (r.statusCode == 200) return;
    throw ApiException('Could not delete loan (${r.statusCode})');
  }

  /// Pending dues, or pass status: 'PAID' to see settled ones instead.
  static Future<List<dynamic>> getPendingPayments(
    String email, {
    String status = 'PENDING',
  }) async {
    final uri = Uri.parse('$baseUrl/pending/${Uri.encodeComponent(email)}')
        .replace(queryParameters: {'status': status});
    final r = await http.get(uri).timeout(_timeout);
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return (data['pending'] as List<dynamic>?) ?? [];
    }
    throw ApiException('Could not load pending payments (${r.statusCode})');
  }

  static Future<void> addPendingPayment(
    String email, {
    required String description,
    required double amount,
    required String dueDate, // 'YYYY-MM-DD'
    String? category,
  }) async {
    final r = await http
        .post(
          Uri.parse('$baseUrl/pending/${Uri.encodeComponent(email)}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'description': description,
            'amount': amount,
            'due_date': dueDate,
            'category': category,
          }),
        )
        .timeout(_timeout);
    if (r.statusCode == 200) return;
    throw ApiException('Could not save pending payment (${r.statusCode})');
  }

  static Future<void> markPaymentPaid(String email, int paymentId) async {
    final r = await http
        .post(Uri.parse(
            '$baseUrl/pending/${Uri.encodeComponent(email)}/$paymentId/mark-paid'))
        .timeout(_timeout);
    if (r.statusCode == 200) return;
    throw ApiException('Could not update payment (${r.statusCode})');
  }

  static Future<void> deletePendingPayment(String email, int paymentId) async {
    final r = await http
        .delete(Uri.parse(
            '$baseUrl/pending/${Uri.encodeComponent(email)}/$paymentId'))
        .timeout(_timeout);
    if (r.statusCode == 200) return;
    throw ApiException('Could not delete pending payment (${r.statusCode})');
  }
}

/// A friendly error we can show the user, rather than a raw exception.
class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}
