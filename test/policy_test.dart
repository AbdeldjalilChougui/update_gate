import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:update_gate/update_gate.dart';

void main() {
  group('UpdatePolicy.fromJson', () {
    test('reads every field', () {
      final p = UpdatePolicy.fromJson({
        'min_required_version': '1.2.0',
        'latest_version': '1.4.0+52',
        'store_url': 'https://play.google.com/store/apps/details?id=a.b',
        'remind_after_hours': 48,
        'title': {'en': 'New!', 'fr': 'Nouveau !'},
        'message': {'en': 'Hello', 'ar': 'مرحبا'},
        'platforms': {
          'ios': {
            'min_required_version': '1.3.0',
            'store_url': 'https://apps.apple.com/app/id1',
          },
          'nonsense_platform': {'min_required_version': '9.9.9'},
        },
      });
      expect(p.minRequiredVersion, '1.2.0');
      expect(p.latestVersion, '1.4.0+52');
      expect(p.storeUrl, startsWith('https://play.google.com'));
      expect(p.remindAfter, const Duration(hours: 48));
      expect(p.titles, {'en': 'New!', 'fr': 'Nouveau !'});
      expect(p.messages['ar'], 'مرحبا');
      expect(p.platforms.keys, [UpdatePlatform.ios]);
      final ios = p.resolve(UpdatePlatform.ios);
      expect(ios.minRequiredVersion, '1.3.0');
      expect(ios.latestVersion, '1.4.0+52');
      expect(ios.storeUrl, 'https://apps.apple.com/app/id1');
      expect(ios.messages['en'], 'Hello');
    });

    test('a plain string message applies to every locale', () {
      final p = UpdatePolicy.fromJson({'message': 'Please update'});
      expect(p.messageFor(const Locale('fr')), 'Please update');
    });

    test('numbers are accepted as versions', () {
      final p = UpdatePolicy.fromJson({'latest_version': 2});
      expect(p.latestVersion, '2');
    });

    test('wrong types are ignored rather than thrown', () {
      final p = UpdatePolicy.fromJson({
        'min_required_version': ['1'],
        'remind_after_hours': 'soon',
        'message': 42,
        'platforms': 'ios',
      });
      expect(p.minRequiredVersion, isNull);
      expect(p.remindAfter, UpdatePolicy.defaultRemindAfter);
      expect(p.messages, isEmpty);
      expect(p.platforms, isEmpty);
    });
  });

  group('messageFor', () {
    const p = UpdatePolicy(messages: {
      'en': 'Update',
      'fr': 'Mettez à jour',
      'fr_CA': 'Mettez à jour (CA)',
    });

    test('exact locale, then language, then English', () {
      expect(p.messageFor(const Locale('fr', 'CA')), 'Mettez à jour (CA)');
      expect(p.messageFor(const Locale('fr', 'FR')), 'Mettez à jour');
      expect(p.messageFor(const Locale('de')), 'Update');
    });

    test('hyphenated keys also match', () {
      const q = UpdatePolicy(messages: {'pt-BR': 'Atualize'});
      expect(q.messageFor(const Locale('pt', 'BR')), 'Atualize');
    });

    test('null when nothing fits', () {
      const q = UpdatePolicy(messages: {'ar': 'حدث'});
      expect(q.messageFor(const Locale('de')), isNull);
      expect(const UpdatePolicy().messageFor(const Locale('en')), isNull);
    });
  });

  test('UpdatePlatform.fromName', () {
    expect(UpdatePlatform.fromName('Android'), UpdatePlatform.android);
    expect(UpdatePlatform.fromName('x'), isNull);
  });
}
