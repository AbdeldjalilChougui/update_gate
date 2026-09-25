import 'package:flutter_test/flutter_test.dart';
import 'package:update_gate/update_gate.dart';

UpdateKind decide(
  String? current, {
  String? min,
  String? latest,
  UpdatePlatform platform = UpdatePlatform.android,
  Map<UpdatePlatform, UpdatePolicy> platforms = const {},
}) =>
    UpdateDecision.evaluate(
      currentVersion: current,
      policy: UpdatePolicy(
        minRequiredVersion: min,
        latestVersion: latest,
        platforms: platforms,
      ),
      platform: platform,
    ).kind;

void main() {
  group('decision matrix', () {
    // (current, min, latest) -> expected
    const cases = <(String, String?, String?, UpdateKind)>[
      ('1.0.0', '1.2.0', '1.3.0', UpdateKind.forced),
      ('1.1.9', '1.2.0', '1.3.0', UpdateKind.forced),
      ('1.2.0', '1.2.0', '1.3.0', UpdateKind.optional),
      ('1.2.5', '1.2.0', '1.3.0', UpdateKind.optional),
      ('1.3.0', '1.2.0', '1.3.0', UpdateKind.none),
      ('2.0.0', '1.2.0', '1.3.0', UpdateKind.none),
      ('1.0.0', '0.0.0', '0.0.0', UpdateKind.none),
      // Build numbers participate.
      ('1.3.0+10', '1.3.0+11', '1.3.0+11', UpdateKind.forced),
      ('1.3.0+11', '1.3.0+11', '1.3.0+12', UpdateKind.optional),
      ('1.3.0+45', '1.3.0', '1.3.0', UpdateKind.none),
      // Only one of the two rules configured.
      ('1.0.0', null, '1.1.0', UpdateKind.optional),
      ('1.1.0', null, '1.1.0', UpdateKind.none),
      ('1.0.0', '1.1.0', null, UpdateKind.forced),
      ('1.1.0', '1.1.0', null, UpdateKind.none),
      ('1.0.0', '', '1.1.0', UpdateKind.optional),
      // Misconfigured: min above latest still forces below min.
      ('1.0.0', '2.0.0', '1.5.0', UpdateKind.forced),
      // Forms that parse leniently.
      ('v1.0', '1.0.1', '1.0.1', UpdateKind.forced),
      ('1.2+5', 'v1.2.0', '1.2.1', UpdateKind.optional),
    ];
    for (final (current, min, latest, expected) in cases) {
      test('current $current, min $min, latest $latest -> ${expected.name}',
          () {
        expect(decide(current, min: min, latest: latest), expected);
      });
    }
  });

  group('fails open', () {
    test('null policy', () {
      expect(
        UpdateDecision.evaluate(currentVersion: '1.0.0', policy: null).kind,
        UpdateKind.none,
      );
    });

    test('missing or junk current version', () {
      expect(decide(null, min: '9.0.0', latest: '9.0.0'), UpdateKind.none);
      expect(decide('', min: '9.0.0', latest: '9.0.0'), UpdateKind.none);
      expect(decide('dev', min: '9.0.0', latest: '9.0.0'), UpdateKind.none);
    });

    test('junk minimum disables everything, even a valid latest', () {
      expect(decide('1.0.0', min: 'abc', latest: '9.0.0'), UpdateKind.none);
    });

    test('junk latest disables everything, even a valid minimum', () {
      expect(decide('1.0.0', min: '9.0.0', latest: '9.x'), UpdateKind.none);
    });

    test('no rules at all', () {
      expect(decide('1.0.0'), UpdateKind.none);
    });

    test('UpdateDecision.none carries no data', () {
      const d = UpdateDecision.none();
      expect(d.kind, UpdateKind.none);
      expect(d.isForced, isFalse);
      expect(d.isOptional, isFalse);
      expect(d.storeUrl, isNull);
    });
  });

  group('platform overrides', () {
    final platforms = {
      UpdatePlatform.ios: const UpdatePolicy(
        minRequiredVersion: '2.0.0',
        storeUrl: 'https://apps.apple.com/app/id1',
      ),
    };

    test('override fields win on their platform', () {
      final d = UpdateDecision.evaluate(
        currentVersion: '1.5.0',
        policy: UpdatePolicy(
          minRequiredVersion: '1.0.0',
          latestVersion: '1.6.0',
          storeUrl: 'https://play.google.com/store/apps/details?id=x',
          platforms: platforms,
        ),
        platform: UpdatePlatform.ios,
      );
      expect(d.kind, UpdateKind.forced);
      expect(d.storeUrl, Uri.parse('https://apps.apple.com/app/id1'));
    });

    test('unset override fields fall back to the base policy', () {
      expect(
        decide('1.5.0',
            min: '1.0.0',
            latest: '1.6.0',
            platform: UpdatePlatform.android,
            platforms: platforms),
        UpdateKind.optional,
      );
    });
  });

  test('decision exposes the parsed versions and store URL', () {
    final d = UpdateDecision.evaluate(
      currentVersion: '1.0.0+3',
      policy: const UpdatePolicy(
        minRequiredVersion: '1.0.0',
        latestVersion: '1.1.0',
        storeUrl: 'https://example.com/app',
      ),
    );
    expect(d.isOptional, isTrue);
    expect(d.currentVersion, AppVersion.parse('1.0.0+3'));
    expect(d.latestVersion, AppVersion.parse('1.1.0'));
    expect(d.minRequiredVersion, AppVersion.parse('1.0.0'));
    expect(d.storeUrl, Uri.parse('https://example.com/app'));
  });

  test('a junk store URL does not block the decision', () {
    final d = UpdateDecision.evaluate(
      currentVersion: '1.0.0',
      policy: const UpdatePolicy(latestVersion: '2.0.0', storeUrl: '::::'),
    );
    expect(d.kind, UpdateKind.optional);
    expect(d.storeUrl, isNull);
  });
}
