import 'package:flutter_test/flutter_test.dart';
import 'package:update_gate/update_gate.dart';

void main() {
  group('AppVersion.tryParse', () {
    test('full version', () {
      final v = AppVersion.tryParse('1.2.3')!;
      expect([v.major, v.minor, v.patch], [1, 2, 3]);
      expect(v.build, isNull);
      expect(v.preRelease, isNull);
    });

    test('1.2 fills patch with 0', () {
      expect(AppVersion.tryParse('1.2'), AppVersion(1, 2, 0));
    });

    test('a single number fills minor and patch', () {
      expect(AppVersion.tryParse('5'), AppVersion(5, 0, 0));
    });

    test('1.2.3+45 keeps the build number', () {
      final v = AppVersion.tryParse('1.2.3+45')!;
      expect([v.major, v.minor, v.patch], [1, 2, 3]);
      expect(v.build, '45');
      expect(v.buildNumber, 45);
    });

    test('v1.2.3 and V1.2.3 accept a leading v', () {
      expect(AppVersion.tryParse('v1.2.3'), AppVersion(1, 2, 3));
      expect(AppVersion.tryParse('V1.2.3'), AppVersion(1, 2, 3));
    });

    test('surrounding whitespace is ignored', () {
      expect(AppVersion.tryParse('  2.0.1\n'), AppVersion(2, 0, 1));
    });

    test('pre-release and build together', () {
      final v = AppVersion.tryParse('1.0.0-beta.2+7')!;
      expect(v.preRelease, 'beta.2');
      expect(v.build, '7');
    });

    test('non-numeric build metadata is kept but has no build number', () {
      final v = AppVersion.tryParse('1.0.0+exp.sha.5114f85')!;
      expect(v.build, 'exp.sha.5114f85');
      expect(v.buildNumber, isNull);
    });

    for (final junk in <String?>[
      null,
      '',
      '   ',
      'abc',
      '1.x.3',
      '1.2.3.4',
      '1..2',
      '.1.2',
      '1.2.',
      '-1.2.3',
      '1.2.3+',
      '1.2.3-',
      'v',
      'version 1.2',
      '1.2.3 beta',
      '١.٢.٣',
    ]) {
      test('junk ${junk == null ? 'null' : '"$junk"'} is null', () {
        expect(AppVersion.tryParse(junk), isNull);
      });
    }

    test('parse throws FormatException on junk', () {
      expect(() => AppVersion.parse('junk'), throwsFormatException);
    });

    test('toString round-trips', () {
      for (final s in ['1.2.3', '1.2.3+45', '1.0.0-rc.1', '1.0.0-rc.1+2']) {
        expect(AppVersion.parse(s).toString(), s);
      }
      expect(AppVersion.parse('v1.2').toString(), '1.2.0');
    });
  });

  group('AppVersion comparison', () {
    AppVersion v(String s) => AppVersion.parse(s);

    test('major, then minor, then patch', () {
      expect(v('2.0.0') > v('1.9.9'), isTrue);
      expect(v('1.2.0') > v('1.1.9'), isTrue);
      expect(v('1.2.4') > v('1.2.3'), isTrue);
      expect(v('1.10.0') > v('1.9.0'), isTrue);
    });

    test('equal versions', () {
      expect(v('1.2.3').compareTo(v('1.2.3')), 0);
      expect(v('1.2') == v('1.2.0'), isTrue);
      expect(v('1.2').hashCode, v('1.2.0').hashCode);
    });

    test('numeric build numbers break ties', () {
      expect(v('1.2.3+46') > v('1.2.3+45'), isTrue);
      expect(v('1.2.3+9') < v('1.2.3+10'), isTrue);
    });

    test('a missing build number counts as 0', () {
      expect(v('1.2.3+1') > v('1.2.3'), isTrue);
      expect(v('1.2.3+0') == v('1.2.3'), isTrue);
    });

    test('non-numeric build metadata is ignored', () {
      expect(v('1.2.3+abc').compareTo(v('1.2.3')), 0);
    });

    test('a pre-release is lower than its release', () {
      expect(v('1.0.0-alpha') < v('1.0.0'), isTrue);
      expect(v('1.0.0-rc.1') < v('1.0.0+1'), isTrue);
    });

    test('pre-release identifiers follow semver precedence', () {
      final ordered = [
        '1.0.0-alpha',
        '1.0.0-alpha.1',
        '1.0.0-alpha.beta',
        '1.0.0-beta',
        '1.0.0-beta.2',
        '1.0.0-beta.11',
        '1.0.0-rc.1',
        '1.0.0',
      ].map(v).toList();
      for (var i = 0; i < ordered.length - 1; i++) {
        expect(ordered[i] < ordered[i + 1], isTrue,
            reason: '${ordered[i]} < ${ordered[i + 1]}');
      }
    });

    test('operators', () {
      expect(v('1.2.3') <= v('1.2.3'), isTrue);
      expect(v('1.2.3') >= v('1.2.3'), isTrue);
      expect(v('1.2.3') < v('1.2.3'), isFalse);
    });
  });
}
