import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'l10n.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

/// The request got no answer: no connection, a TLS failure, or a timeout.
/// Screens already report [ApiException]s, so this reaches them the same way.
class NetworkException extends ApiException {
  /// A write that got no answer: a timeout, or a connection dropped after the
  /// request went out, may follow a server that applied it all the same, and
  /// the client cannot tell those from a request never sent. So the message
  /// asks for a refresh rather than a blind retry.
  final bool maybeApplied;

  const NetworkException({this.maybeApplied = false}) : super(0, '');

  @override
  String get message => maybeApplied
      ? AppLocalizations.current.noAnswerMaybeSaved
      : AppLocalizations.current.connectionError;
}

class ApiClient {
  final String baseUrl;
  final String? token;

  ApiClient({required this.baseUrl, this.token});

  String get _base {
    final url = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$url/api/v1';
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<dynamic> get(String path) => _send(write: false,
      () => http.get(Uri.parse('$_base$path'), headers: _headers));

  Future<dynamic> post(String path, [Object? body]) => _send(() => http.post(
      Uri.parse('$_base$path'),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null));

  Future<dynamic> put(String path, Object body) => _send(() => http.put(
      Uri.parse('$_base$path'), headers: _headers, body: jsonEncode(body)));

  Future<dynamic> patch(String path, Object body) => _send(() => http.patch(
      Uri.parse('$_base$path'), headers: _headers, body: jsonEncode(body)));

  Future<dynamic> delete(String path) => _send(
      () => http.delete(Uri.parse('$_base$path'), headers: _headers));

  Future<dynamic> _send(Future<http.Response> Function() request,
      {bool write = true}) async {
    final http.Response res;
    try {
      res = await request().timeout(const Duration(seconds: 10));
    } on Exception catch (e) {
      if (e is TimeoutException || e is IOException || e is http.ClientException) {
        throw NetworkException(maybeApplied: write);
      }
      rethrow;
    }
    return _handle(res);
  }

  dynamic _handle(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      return jsonDecode(res.body);
    }
    String message = 'Request failed (${res.statusCode})';
    try {
      final body = jsonDecode(res.body) as Map;
      message = (body['error'] as String?) ?? message;
    } catch (_) {}
    if (res.statusCode == 401) throw const UnauthorizedException();
    throw ApiException(res.statusCode, message);
  }
}

class UnauthorizedException extends ApiException {
  const UnauthorizedException() : super(401, 'Session expired. Please sign in again.');
}

/// Which flavour of ScreenGuard server an address points at.
///
/// Not a version split: cloud and community version on separate axes, so the
/// number tells you nothing. Which endpoints answer is the structural fact.
enum ServerKind { community, cloud }

/// Hosted ScreenGuard Cloud. Fixed, so the cloud path needs no typed address.
const cloudServerUrl = 'https://api.screenguard.cc';

/// Confirms [baseUrl] speaks the ScreenGuard API, and reports which flavour.
///
/// `/version` is asked first: both modern servers answer it (community since
/// v0.10.2, cloud since its first release). `/auth/status` is the fallback for
/// community servers older than that — a shrinking set — and doubles as the
/// classifier, since it is community-only by construction: it reads the public
/// admin table, which multi-tenant cloud does not have and never will.
///
/// Pass [assume] when the flavour is known up front (the cloud button), which
/// also skips the classifying request. Unknown or ambiguous means community —
/// the safe default, since only community can be set up from the app — but a
/// transport failure propagates rather than persisting a guess.
Future<ServerKind> probeScreenGuardServer(String baseUrl, {ServerKind? assume}) async {
  final client = ApiClient(baseUrl: baseUrl);
  try {
    await client.get('/version');
  } on NetworkException {
    rethrow;
  } on ApiException {
    await client.get('/auth/status');
    return ServerKind.community;
  }
  if (assume != null) return assume;
  try {
    await client.get('/auth/status');
  } on NetworkException {
    rethrow;
  } on ApiException catch (e) {
    if (e.statusCode == 404) return ServerKind.cloud;
  }
  return ServerKind.community;
}
