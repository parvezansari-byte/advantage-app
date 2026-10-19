// lib/services/authed_http.dart
//
// Drop-in replacement for `package:http/http.dart` in the API service files.
// Same get/post/put/patch/delete/head functions, but each request carries the
// signed login token (Authorization: Bearer ...) so the server knows who is
// asking. Everything else from package:http (Response, etc.) is re-exported.

import 'dart:convert';
import 'package:http/http.dart' as h;
import 'auth_service.dart';

export 'package:http/http.dart' hide get, post, put, patch, delete, head;

Map<String, String>? _auth(Map<String, String>? headers) {
  final t = AuthService.token;
  if (t == null || t.isEmpty) return headers;
  return {...?headers, 'Authorization': 'Bearer $t'};
}

Future<h.Response> get(Uri url, {Map<String, String>? headers}) =>
    h.get(url, headers: _auth(headers));

Future<h.Response> head(Uri url, {Map<String, String>? headers}) =>
    h.head(url, headers: _auth(headers));

Future<h.Response> post(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    h.post(url, headers: _auth(headers), body: body, encoding: encoding);

Future<h.Response> put(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    h.put(url, headers: _auth(headers), body: body, encoding: encoding);

Future<h.Response> patch(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    h.patch(url, headers: _auth(headers), body: body, encoding: encoding);

Future<h.Response> delete(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    h.delete(url, headers: _auth(headers), body: body, encoding: encoding);
