/// @docImport 'widgets/update_gate.dart';
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'update_policy.dart';

/// Where update rules come from: your server, Remote Config, a database.
///
/// Implementations may throw; [UpdateGate] treats any error as "no prompt".
abstract interface class UpdatePolicySource {
  /// Fetches the current policy, or null when there is none.
  Future<UpdatePolicy?> fetch();
}

/// Thrown by [JsonUrlSource] when the response is not a usable policy.
class UpdatePolicyException implements Exception {
  /// Creates the exception.
  const UpdatePolicyException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'UpdatePolicyException: $message';
}

/// A fixed policy, for tests, previews or policies bundled with the app.
class StaticSource implements UpdatePolicySource {
  /// Always returns [policy].
  const StaticSource(this.policy);

  /// The policy returned by [fetch].
  final UpdatePolicy? policy;

  @override
  Future<UpdatePolicy?> fetch() async => policy;
}

/// Fetches a JSON policy (see [UpdatePolicy.fromJson]) with a GET request.
class JsonUrlSource implements UpdatePolicySource {
  /// Creates a source for [url].
  ///
  /// Pass a [client] to reuse connections or to test with
  /// `package:http/testing.dart`. A client passed in is not closed.
  JsonUrlSource(this.url, {http.Client? client, this.headers = const {}})
      : _client = client;

  /// The JSON document's address.
  final Uri url;

  /// Extra request headers, such as an API key.
  final Map<String, String> headers;

  final http.Client? _client;

  @override
  Future<UpdatePolicy?> fetch() async {
    final client = _client ?? http.Client();
    try {
      final response = await client.get(
        url,
        headers: {'Accept': 'application/json', ...headers},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw UpdatePolicyException('HTTP ${response.statusCode} from $url');
      }
      final Object? body;
      try {
        body = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException catch (e) {
        throw UpdatePolicyException('Invalid JSON from $url: ${e.message}');
      }
      if (body is! Map<String, Object?>) {
        throw UpdatePolicyException('Expected a JSON object from $url');
      }
      return UpdatePolicy.fromJson(body);
    } finally {
      if (_client == null) client.close();
    }
  }
}
