import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:update_gate/update_gate.dart';

void main() {
  group('JsonUrlSource', () {
    final url = Uri.parse('https://example.com/update.json');

    test('fetches and parses the policy', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode(
              {'min_required_version': '1.0.0', 'latest_version': '1.1.0'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final source = JsonUrlSource(url,
          client: client, headers: {'Authorization': 'Bearer t'});
      final policy = await source.fetch();
      expect(seen.url, url);
      expect(seen.method, 'GET');
      expect(seen.headers['Authorization'], 'Bearer t');
      expect(policy!.latestVersion, '1.1.0');
    });

    test('non-2xx status throws UpdatePolicyException', () async {
      final client = MockClient((_) async => http.Response('nope', 503));
      expect(JsonUrlSource(url, client: client).fetch(),
          throwsA(isA<UpdatePolicyException>()));
    });

    test('invalid JSON throws UpdatePolicyException', () async {
      final client = MockClient((_) async => http.Response('{oops', 200));
      expect(JsonUrlSource(url, client: client).fetch(),
          throwsA(isA<UpdatePolicyException>()));
    });

    test('a JSON array throws UpdatePolicyException', () async {
      final client = MockClient((_) async => http.Response('[1]', 200));
      expect(JsonUrlSource(url, client: client).fetch(),
          throwsA(isA<UpdatePolicyException>()));
    });

    test('UTF-8 bodies without a charset decode correctly', () async {
      final client = MockClient((_) async => http.Response.bytes(
            utf8.encode(jsonEncode({
              'message': {'ar': 'حدّث التطبيق'}
            })),
            200,
          ));
      final policy = await JsonUrlSource(url, client: client).fetch();
      expect(policy!.messages['ar'], 'حدّث التطبيق');
    });
  });

  test('StaticSource returns its policy', () async {
    const policy = UpdatePolicy(latestVersion: '3.0.0');
    expect(await const StaticSource(policy).fetch(), same(policy));
    expect(await const StaticSource(null).fetch(), isNull);
  });
}
