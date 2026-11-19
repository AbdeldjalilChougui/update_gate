import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:update_gate/update_gate.dart';

UpdateKind decide(UpdatePolicy? policy, {String current = '1.2.0'}) =>
    UpdateDecision.evaluate(
      currentVersion: current,
      policy: policy,
      platform: UpdatePlatform.android,
    ).kind;

class _ThrowingSource implements UpdatePolicySource {
  @override
  Future<UpdatePolicy?> fetch() async => throw StateError('offline');
}

void main() {
  group('ResponseSignalSource', () {
    test('no signal gives no policy', () async {
      final source = ResponseSignalSource();
      expect(await source.fetch(), isNull);
      expect(decide(await source.fetch()), UpdateKind.none);
    });

    test('426 forces, whatever the running version', () async {
      final source = ResponseSignalSource()..observe(statusCode: 426);
      final policy = await source.fetch();
      expect(policy!.forceUpdate, isTrue);
      expect(decide(policy), UpdateKind.forced);
      expect(decide(policy, current: '99.0.0'), UpdateKind.forced);
      expect(decide(policy, current: 'dev'), UpdateKind.forced);
    });

    test('a header above the running version forces', () async {
      final source = ResponseSignalSource()
        ..observe(statusCode: 200, minVersion: '1.3.0');
      expect(decide(await source.fetch()), UpdateKind.forced);
    });

    test('a header equal to or below the running version does nothing',
        () async {
      final equal = ResponseSignalSource()
        ..observe(statusCode: 200, minVersion: '1.2.0');
      expect(decide(await equal.fetch()), UpdateKind.none);
      final below = ResponseSignalSource()
        ..observe(statusCode: 200, minVersion: '1.1.9+400');
      expect(decide(await below.fetch()), UpdateKind.none);
    });

    test('a junk or empty header is ignored', () async {
      final source = ResponseSignalSource();
      var notified = 0;
      source.addListener(() => notified++);
      for (final junk in ['soon', '', '1.x', 'latest', ' ']) {
        source.observe(statusCode: 200, minVersion: junk);
      }
      source.observe(statusCode: 500);
      expect(source.hasSignal, isFalse);
      expect(notified, 0);
      expect(await source.fetch(), isNull);
    });

    test('keeps the strongest signal and notifies only when it grows', () {
      final source = ResponseSignalSource();
      var notified = 0;
      source.addListener(() => notified++);
      source.observe(statusCode: 200, minVersion: '1.3.0');
      source.observe(statusCode: 200, minVersion: '1.1.0');
      source.observe(statusCode: 200, minVersion: '1.3.0');
      expect(source.minVersionSeen.toString(), '1.3.0');
      expect(notified, 1);
      source.observe(statusCode: 200, minVersion: '1.4.0');
      source.observe(statusCode: 426);
      source.observe(statusCode: 426);
      expect(source.upgradeRequiredSeen, isTrue);
      expect(notified, 3);
    });

    test('observeHeaders reads the header in any case, String or list', () {
      final source = ResponseSignalSource(headerName: 'X-Min-Version');
      source.observeHeaders(200, {'x-min-version': '1.3.0'});
      expect(source.minVersionSeen.toString(), '1.3.0');
      source.observeHeaders(200, {
        'X-MIN-VERSION': ['2.0.0', '0.1.0'],
      });
      expect(source.minVersionSeen.toString(), '2.0.0');
      source.observeHeaders(200, {'other': '9.0.0'});
      expect(source.minVersionSeen.toString(), '2.0.0');
    });

    test('the template supplies store URL and messages', () async {
      final source = ResponseSignalSource(
        template: const UpdatePolicy(
          storeUrl: 'https://example.com/store',
          messages: {'en': 'Please update'},
        ),
      )..observe(statusCode: 426);
      final decision = UpdateDecision.evaluate(
          currentVersion: '1.0.0', policy: await source.fetch());
      expect(decision.storeUrl, Uri.parse('https://example.com/store'));
      expect(decision.policy!.messageFor(const Locale('en')), 'Please update');
    });

    test('clear forgets the signals', () async {
      final source = ResponseSignalSource()..observe(statusCode: 426);
      source.clear();
      expect(await source.fetch(), isNull);
    });

    group('over a base source', () {
      const base = UpdatePolicy(
        minRequiredVersion: '1.0.0',
        latestVersion: '1.5.0',
        storeUrl: 'https://example.com/store',
        platforms: {
          UpdatePlatform.ios: UpdatePolicy(minRequiredVersion: '1.1.0'),
        },
      );

      test('without a signal the base policy passes through', () async {
        final source = ResponseSignalSource(base: const StaticSource(base));
        expect(decide(await source.fetch()), UpdateKind.optional);
      });

      test('a higher header raises the minimum, platforms included', () async {
        final source = ResponseSignalSource(base: const StaticSource(base))
          ..observe(statusCode: 200, minVersion: '1.3.0');
        final policy = await source.fetch();
        expect(decide(policy), UpdateKind.forced);
        expect(
            UpdateDecision.evaluate(
                    currentVersion: '1.2.0',
                    policy: policy,
                    platform: UpdatePlatform.ios)
                .kind,
            UpdateKind.forced);
        expect(policy!.latestVersion, '1.5.0');
        expect(policy.storeUrl, 'https://example.com/store');
      });

      test('a lower header keeps the base rules', () async {
        final source = ResponseSignalSource(base: const StaticSource(base))
          ..observe(statusCode: 200, minVersion: '0.9.0');
        final policy = await source.fetch();
        expect(policy!.minRequiredVersion, '1.0.0');
        expect(decide(policy), UpdateKind.optional);
      });

      test('a failing base does not hide a signal', () async {
        final source = ResponseSignalSource(base: _ThrowingSource())
          ..observe(statusCode: 426);
        expect(decide(await source.fetch()), UpdateKind.forced);
      });

      test('a failing base without a signal still throws (gate fails open)',
          () {
        final source = ResponseSignalSource(base: _ThrowingSource());
        expect(source.fetch(), throwsStateError);
      });

      test('works with JsonUrlSource', () async {
        final client = MockClient((_) async =>
            http.Response(jsonEncode({'min_required_version': '1.0.0'}), 200));
        final source = ResponseSignalSource(
          base: JsonUrlSource(Uri.parse('https://example.com/u.json'),
              client: client),
        );
        expect(decide(await source.fetch()), UpdateKind.none);
        source.observe(statusCode: 200, minVersion: '1.2.1');
        expect(decide(await source.fetch()), UpdateKind.forced);
      });
    });
  });

  test('force_update in JSON and platform overrides', () {
    final policy = UpdatePolicy.fromJson({
      'platforms': {
        'ios': {'force_update': true},
      },
    });
    expect(policy.forceUpdate, isFalse);
    expect(decide(policy), UpdateKind.none);
    expect(
        UpdateDecision.evaluate(
                currentVersion: '1.0.0',
                policy: policy,
                platform: UpdatePlatform.ios)
            .kind,
        UpdateKind.forced);
    expect(UpdatePolicy.fromJson({'force_update': 'yes'}).forceUpdate, isFalse);
  });

  group('UpdateGate with a ResponseSignalSource', () {
    late List<UpdateDecision> decided;
    setUp(() => decided = []);

    Future<void> pumpGate(WidgetTester tester, UpdatePolicySource source,
        {String current = '1.2.0'}) async {
      await tester.pumpWidget(MaterialApp(
        home: UpdateGate(
          source: source,
          currentVersion: () => current,
          onOpenStore: (_) {},
          onDecision: decided.add,
          platform: UpdatePlatform.android,
          child: const Scaffold(body: Text('HOME')),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('a 426 mid-session shows the forced page', (tester) async {
      final source = ResponseSignalSource();
      await pumpGate(tester, source);
      expect(find.text('HOME').hitTestable(), findsOneWidget);
      expect(decided.single.kind, UpdateKind.none);

      source.observe(statusCode: 426);
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('HOME').hitTestable(), findsNothing);

      // Further signals do not stack a second page.
      source.observe(statusCode: 200, minVersion: '5.0.0');
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsOneWidget);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('HOME').hitTestable(), findsOneWidget);
    });

    testWidgets('a header above the version mid-session forces',
        (tester) async {
      final source = ResponseSignalSource();
      await pumpGate(tester, source);
      source.observe(statusCode: 200, minVersion: '1.3.0');
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsOneWidget);
    });

    testWidgets('a header equal or below shows nothing', (tester) async {
      final source = ResponseSignalSource();
      await pumpGate(tester, source);
      source.observe(statusCode: 200, minVersion: '1.0.0');
      await tester.pumpAndSettle();
      source.observe(statusCode: 200, minVersion: '1.2.0');
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsNothing);
      expect(find.text('HOME').hitTestable(), findsOneWidget);
      expect(decided.map((d) => d.kind), everyElement(UpdateKind.none));
    });

    testWidgets('a junk header shows nothing and does not re-check',
        (tester) async {
      final source = ResponseSignalSource();
      await pumpGate(tester, source);
      source.observe(statusCode: 200, minVersion: 'not-a-version');
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsNothing);
      expect(decided, hasLength(1));
    });

    testWidgets('optional updates from the base still work, then a 426 forces',
        (tester) async {
      final source = ResponseSignalSource(
        base: const StaticSource(
            UpdatePolicy(minRequiredVersion: '1.0.0', latestVersion: '1.5.0')),
      );
      await pumpGate(tester, source);
      expect(find.text('Update available'), findsOneWidget);

      source.observe(statusCode: 426);
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsOneWidget);
    });

    testWidgets('signals during a check are not lost', (tester) async {
      final base = _SlowSource();
      final source = ResponseSignalSource(base: base);
      await tester.pumpWidget(MaterialApp(
        home: UpdateGate(
          source: source,
          currentVersion: () => '1.2.0',
          onOpenStore: (_) {},
          onDecision: decided.add,
          child: const Text('HOME'),
        ),
      ));
      source.observe(statusCode: 426); // while the first fetch hangs
      base.completer.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsOneWidget);
      expect(decided.map((d) => d.kind), [UpdateKind.none, UpdateKind.forced]);
    });

    testWidgets('stops listening when disposed', (tester) async {
      final source = ResponseSignalSource();
      await pumpGate(tester, source);
      await tester.pumpWidget(const SizedBox());
      source.observe(statusCode: 426);
      await tester.pumpAndSettle();
      expect(decided, hasLength(1));
    });
  });
}

class _SlowSource implements UpdatePolicySource {
  final completer = Completer<UpdatePolicy?>();
  var calls = 0;
  @override
  Future<UpdatePolicy?> fetch() {
    calls++;
    return calls == 1 ? completer.future : Future.value(null);
  }
}
