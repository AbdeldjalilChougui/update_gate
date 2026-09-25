import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:update_gate/update_gate.dart';

const _forced = UpdatePolicy(
  minRequiredVersion: '2.0.0',
  latestVersion: '2.1.0',
  storeUrl: 'https://example.com/store',
);
const _optional = UpdatePolicy(
  minRequiredVersion: '1.0.0',
  latestVersion: '1.5.0',
  storeUrl: 'https://example.com/store',
);

class _ThrowingSource implements UpdatePolicySource {
  @override
  Future<UpdatePolicy?> fetch() async => throw StateError('offline');
}

class _HangingSource implements UpdatePolicySource {
  final completer = Completer<UpdatePolicy?>();
  @override
  Future<UpdatePolicy?> fetch() => completer.future;
}

void main() {
  late List<UpdateDecision> opened;
  late List<UpdateDecision> decided;
  late DateTime now;

  setUp(() {
    opened = [];
    decided = [];
    now = DateTime(2026, 5, 7, 12);
  });

  Future<void> pumpGate(
    WidgetTester tester, {
    required UpdatePolicySource source,
    FutureOr<String> Function()? currentVersion,
    RemindLaterStore? store,
    Locale locale = const Locale('en'),
    UpdateGateStrings? strings,
    UpdatePromptBuilder? forcedBuilder,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('fr'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: UpdateGate(
        source: source,
        currentVersion: currentVersion ?? () => '1.2.0',
        onOpenStore: opened.add,
        onDecision: decided.add,
        remindLaterStore: store,
        clock: () => now,
        platform: UpdatePlatform.android,
        strings: strings,
        forcedBuilder: forcedBuilder,
        timeout: timeout,
        child: const Scaffold(body: Text('HOME')),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('forced', () {
    testWidgets('shows a blocking page over the app', (tester) async {
      await pumpGate(tester, source: const StaticSource(_forced));
      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('HOME').hitTestable(), findsNothing);
      expect(decided.single.kind, UpdateKind.forced);
    });

    testWidgets('cannot be popped by the system back button', (tester) async {
      await pumpGate(tester, source: const StaticSource(_forced));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsOneWidget);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(await navigator.maybePop(), isTrue); // handled, not popped
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsOneWidget);
    });

    testWidgets('the update button calls onOpenStore with the store URL',
        (tester) async {
      await pumpGate(tester, source: const StaticSource(_forced));
      await tester.tap(find.widgetWithText(FilledButton, 'Update'));
      await tester.pumpAndSettle();
      expect(opened.single.storeUrl, Uri.parse('https://example.com/store'));
      // Still blocked afterwards.
      expect(find.text('Update required'), findsOneWidget);
    });

    testWidgets('shows the current and available versions', (tester) async {
      await pumpGate(tester, source: const StaticSource(_forced));
      expect(find.text('Current version: 1.2.0 · Available: 2.1.0'),
          findsOneWidget);
    });

    testWidgets('ignores the remind-later store', (tester) async {
      final store = InMemoryRemindLaterStore(
          RemindLaterRecord(version: '2.1.0', at: now));
      await pumpGate(tester, source: const StaticSource(_forced), store: store);
      expect(find.text('Update required'), findsOneWidget);
    });

    testWidgets('a custom builder replaces the page', (tester) async {
      await pumpGate(
        tester,
        source: const StaticSource(_forced),
        forcedBuilder: (context, prompt) => Scaffold(
          body: TextButton(
            onPressed: prompt.onUpdate,
            child: Text('custom ${prompt.decision.latestVersion}'),
          ),
        ),
      );
      await tester.tap(find.text('custom 2.1.0'));
      expect(opened, hasLength(1));
    });
  });

  group('optional', () {
    testWidgets('shows a dismissible dialog over the app', (tester) async {
      await pumpGate(tester, source: const StaticSource(_optional));
      expect(find.text('Update available'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('"Later" closes it and records the time', (tester) async {
      final store = InMemoryRemindLaterStore();
      await pumpGate(tester,
          source: const StaticSource(_optional), store: store);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final record = await store.read();
      expect(record!.version, '1.5.0');
      expect(record.at, now);
    });

    testWidgets('respects the remind interval', (tester) async {
      final store = InMemoryRemindLaterStore(
          RemindLaterRecord(version: '1.5.0', at: now));

      now = now.add(const Duration(hours: 23));
      await pumpGate(tester,
          source: const StaticSource(_optional), store: store);
      expect(find.byType(AlertDialog), findsNothing);
      expect(decided.last.kind, UpdateKind.optional);

      now = now.add(const Duration(hours: 1));
      await pumpGate(tester,
          source: const StaticSource(_optional), store: store);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('uses the interval from the policy', (tester) async {
      const weekly = UpdatePolicy(
        latestVersion: '1.5.0',
        remindAfter: Duration(days: 7),
      );
      final store = InMemoryRemindLaterStore(
          RemindLaterRecord(version: '1.5.0', at: now));
      now = now.add(const Duration(days: 6));
      await pumpGate(tester, source: const StaticSource(weekly), store: store);
      expect(find.byType(AlertDialog), findsNothing);
      now = now.add(const Duration(days: 1));
      await pumpGate(tester, source: const StaticSource(weekly), store: store);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('a newer latest version shows again inside the interval',
        (tester) async {
      final store = InMemoryRemindLaterStore(
          RemindLaterRecord(version: '1.4.0', at: now));
      await pumpGate(tester,
          source: const StaticSource(_optional), store: store);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('"Update" opens the store and does not snooze', (tester) async {
      final store = InMemoryRemindLaterStore();
      await pumpGate(tester,
          source: const StaticSource(_optional), store: store);
      await tester.tap(find.widgetWithText(FilledButton, 'Update'));
      await tester.pumpAndSettle();
      expect(opened.single.kind, UpdateKind.optional);
      expect(find.byType(AlertDialog), findsNothing);
      expect(await store.read(), isNull);
    });

    testWidgets('a failing store still shows the dialog', (tester) async {
      await pumpGate(tester,
          source: const StaticSource(_optional), store: _BrokenStore());
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('no prompt', () {
    testWidgets('when up to date', (tester) async {
      await pumpGate(tester,
          source: const StaticSource(_optional), currentVersion: () => '1.5.0');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('HOME').hitTestable(), findsOneWidget);
    });

    testWidgets('when the source throws', (tester) async {
      await pumpGate(tester, source: _ThrowingSource());
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Update required'), findsNothing);
      expect(find.text('HOME').hitTestable(), findsOneWidget);
      expect(decided.single.kind, UpdateKind.none);
    });

    testWidgets('when the source returns null', (tester) async {
      await pumpGate(tester, source: const StaticSource(null));
      expect(decided.single.kind, UpdateKind.none);
      expect(find.text('HOME').hitTestable(), findsOneWidget);
    });

    testWidgets('when the source times out', (tester) async {
      final source = _HangingSource();
      await pumpGate(tester,
          source: source, timeout: const Duration(seconds: 2));
      expect(decided, isEmpty);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(decided.single.kind, UpdateKind.none);
      // A late answer is ignored.
      source.completer.complete(_forced);
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsNothing);
    });

    testWidgets('when the current version callback throws', (tester) async {
      await pumpGate(tester,
          source: const StaticSource(_forced),
          currentVersion: () => throw StateError('no info'));
      expect(find.text('Update required'), findsNothing);
      expect(decided.single.kind, UpdateKind.none);
    });

    testWidgets('when the current version is junk', (tester) async {
      await pumpGate(tester,
          source: const StaticSource(_forced), currentVersion: () => 'dev');
      expect(find.text('Update required'), findsNothing);
    });

    testWidgets('the child is shown while the check runs', (tester) async {
      final source = _HangingSource();
      await pumpGate(tester, source: source);
      expect(find.text('HOME').hitTestable(), findsOneWidget);
      source.completer.complete(null);
      await tester.pumpAndSettle();
    });
  });

  group('localisation', () {
    testWidgets('French defaults', (tester) async {
      await pumpGate(tester,
          source: const StaticSource(_forced), locale: const Locale('fr'));
      expect(find.text('Mise à jour requise'), findsOneWidget);
      expect(find.text('Mettre à jour'), findsOneWidget);
      expect(find.text('Version actuelle : 1.2.0 · Disponible : 2.1.0'),
          findsOneWidget);
    });

    testWidgets('Arabic defaults, laid out right to left', (tester) async {
      await pumpGate(tester,
          source: const StaticSource(_optional), locale: const Locale('ar'));
      expect(find.text('تحديث متوفر'), findsOneWidget);
      expect(find.text('لاحقًا'), findsOneWidget);
      final title = tester.element(find.text('تحديث متوفر'));
      expect(Directionality.of(title), TextDirection.rtl);
      // In RTL the primary action sits to the left of "later".
      final later = tester.getCenter(find.text('لاحقًا'));
      final update = tester.getCenter(find.text('تحديث'));
      expect(update.dx, lessThan(later.dx));
    });

    testWidgets('an unsupported locale falls back to English', (tester) async {
      expect(UpdateGateStrings.of(const Locale('de')), UpdateGateStrings.en);
      expect(
          UpdateGateStrings.of(const Locale('fr', 'CA')), UpdateGateStrings.fr);
    });

    testWidgets('policy messages win over the default text', (tester) async {
      const policy = UpdatePolicy(
        minRequiredVersion: '9.0.0',
        titles: {'fr': 'Nouvelle version obligatoire'},
        messages: {'en': 'Security fix', 'fr': 'Correctif de sécurité'},
      );
      await pumpGate(tester,
          source: const StaticSource(policy), locale: const Locale('fr'));
      expect(find.text('Nouvelle version obligatoire'), findsOneWidget);
      expect(find.text('Correctif de sécurité'), findsOneWidget);
    });

    testWidgets('strings can be overridden', (tester) async {
      await pumpGate(
        tester,
        source: const StaticSource(_optional),
        strings: UpdateGateStrings.en.copyWith(later: 'Not now'),
      );
      expect(find.text('Not now'), findsOneWidget);
    });
  });
}

class _BrokenStore implements RemindLaterStore {
  @override
  Future<RemindLaterRecord?> read() async => throw StateError('disk');
  @override
  Future<void> write(RemindLaterRecord record) async =>
      throw StateError('disk');
}
