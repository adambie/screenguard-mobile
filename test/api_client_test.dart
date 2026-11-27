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
  NetworkException? networkError(Object e) => e is NetworkException ? e : null;

  test('a failed read surfaces as a NetworkException that changed nothing', () async {
    // ClientException is what IOClient reports on Android when nothing answers
    for (final error in [http.ClientException('Connection refused'), const SocketException('unreachable')]) {
      await withServer((_) => throw error, () async {
        final e = await client.get('/profiles/p').then((_) => null, onError: networkError);
        expect(e?.maybeApplied, false);
      });
    }
  });

  test('a write whose answer is lost may have been applied', () async {
    final received = <String>[];
    await withServer((req) async {
      received.add(req.url.path);
      throw http.ClientException('Connection reset by peer');
    }, () async {
      final e = await client
          .post('/profiles/p/app-group-adjustments', {'minutes': 15})
          .then((_) => null, onError: networkError);
      expect(e?.maybeApplied, true);
    });
    expect(received, ['/api/v1/profiles/p/app-group-adjustments']);
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
