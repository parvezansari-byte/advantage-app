// lib/services/crm_api_service.dart
//
// Talks to the research-api backend's /crm/ endpoints. Ported from the
// standalone advantage_crm app so the client book lives inside the main
// Advantage app instead of a separate install.

import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/crm_client.dart';
import 'api_service.dart' show ApiService;

class CrmApiException implements Exception {
  final String message;
  CrmApiException(this.message);
  @override
  String toString() => message;
}

class CrmApiService {
  static String get _baseUrl => ApiService.baseUrl;

  static Map<String, dynamic> _decodeObj(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic>) return body;
      return {'data': body};
    }
    String msg = 'Request failed (${res.statusCode})';
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['detail'] != null) {
        msg = body['detail'].toString();
      }
    } catch (_) {}
    throw CrmApiException(msg);
  }

  static Future<List<CrmClient>> listClients(String ownerEmail,
      {String? search}) async {
    final uri = Uri.parse('$_baseUrl/crm/$ownerEmail/clients').replace(
      queryParameters:
          (search != null && search.isNotEmpty) ? {'search': search} : null,
    );
    final res = await http.get(uri);
    final body = _decodeObj(res);
    final list = (body['clients'] as List? ?? []);
    return list
        .map((e) => CrmClient.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<CrmClient> getClient(String ownerEmail, int clientId) async {
    final res =
        await http.get(Uri.parse('$_baseUrl/crm/$ownerEmail/clients/$clientId'));
    return CrmClient.fromJson(_decodeObj(res));
  }

  static Future<CrmClient> addClient(
      String ownerEmail, CrmClient client) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/crm/$ownerEmail/clients'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(client.toJson()),
    );
    return CrmClient.fromJson(_decodeObj(res));
  }

  static Future<CrmClient> updateClient(
      String ownerEmail, int clientId, CrmClient client) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/crm/$ownerEmail/clients/$clientId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(client.toJson()),
    );
    return CrmClient.fromJson(_decodeObj(res));
  }

  static Future<void> deleteClient(String ownerEmail, int clientId) async {
    final res = await http
        .delete(Uri.parse('$_baseUrl/crm/$ownerEmail/clients/$clientId'));
    _decodeObj(res);
  }

  static Future<List<CrmInteraction>> listInteractions(
      String ownerEmail, int clientId) async {
    final res = await http.get(
        Uri.parse('$_baseUrl/crm/$ownerEmail/clients/$clientId/interactions'));
    final body = _decodeObj(res);
    final list = (body['interactions'] as List? ?? []);
    return list
        .map((e) => CrmInteraction.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> addInteraction(
      String ownerEmail, int clientId, String note) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/crm/$ownerEmail/clients/$clientId/interactions'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'note': note}),
    );
    _decodeObj(res);
  }

  static Future<(List<CrmHolding>, double, String?)> getHoldings(
      String ownerEmail, int clientId) async {
    final res = await http
        .get(Uri.parse('$_baseUrl/crm/$ownerEmail/clients/$clientId/holdings'));
    final body = _decodeObj(res);
    final list = (body['holdings'] as List? ?? []);
    final holdings =
        list.map((e) => CrmHolding.fromJson(e as Map<String, dynamic>)).toList();
    final total = double.tryParse('${body['total_value'] ?? 0}') ?? 0;
    final lastFetched = body['last_fetched']?.toString();
    return (holdings, total, lastFetched);
  }
}
