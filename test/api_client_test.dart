import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:screenguard/api_client.dart';

Future<void> withServer(
  Future<http.Response> Function(http.Request) handler,
  Future<void> Function() body,
) =>
    http.runWithClient(body, () => MockClient(handler));

void main() {
  final client = ApiClient(baseUrl: 'http://sg');
  final unreachable = throwsA(isA<NetworkException>()
      .having((e) => e.maybeApplied, 'maybeApplied', false));

  test('a refused connection surfaces as a NetworkException', () async {
    // what IOClient reports on Android when nothing answers
    await withServer((_) => throw http.ClientException('Connection refused'),
        () => expectLater(client.post('/profiles/p/adjustments', {}), unreachable));
    await withServer((_) => throw const SocketException('unreachable'),
        () => expectLater(client.get('/profiles/p'), unreachable));
  });

  test('a server error stays an ApiException with its status and message', () async {
    await withServer(
      (_) async => http.Response('{"error":"not found"}', 404),
      () => expectLater(
        client.get('/profiles/p'),
        throwsA(isA<ApiException>()
            .having((e) => e is NetworkException, 'network', false)
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.message, 'message', 'not found')),
      ),
    );
  });

  test('the probe does not take an unreachable /version for an old server', () async {
    await withServer(
      (req) async => req.url.path.endsWith('/version')
          ? throw const SocketException('unreachable')
          : http.Response('{"setup_needed":false}', 200),
      () => expectLater(probeScreenGuardServer('http://sg'), throwsA(isA<NetworkException>())),
    );
  });

  test('the probe does not guess the flavour when /auth/status is unreachable', () async {
    await withServer(
      (req) async => req.url.path.endsWith('/version')
          ? http.Response('{"version":"0.10.20"}', 200)
          : throw const SocketException('unreachable'),
      () => expectLater(probeScreenGuardServer('http://sg'), throwsA(isA<NetworkException>())),
    );
  });
}
