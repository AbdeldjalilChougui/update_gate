import 'package:flutter_test/flutter_test.dart';
import 'package:update_gate/update_gate.dart';

void main() {
  final now = DateTime(2026, 5, 7, 12);
  const day = Duration(hours: 24);

  test('shows when nothing was recorded', () {
    expect(
        shouldRemindNow(null, latestVersion: '1.3.0', now: now, interval: day),
        isTrue);
  });

  test('hides inside the interval for the same version', () {
    final r = RemindLaterRecord(version: '1.3.0', at: now);
    expect(
      shouldRemindNow(r,
          latestVersion: '1.3.0',
          now: now.add(const Duration(hours: 11)),
          interval: day),
      isFalse,
    );
  });

  test('shows again once the interval has passed', () {
    final r = RemindLaterRecord(version: '1.3.0', at: now);
    expect(
      shouldRemindNow(r,
          latestVersion: '1.3.0', now: now.add(day), interval: day),
      isTrue,
    );
  });

  test('a newer latest version resets the interval', () {
    final r = RemindLaterRecord(version: '1.3.0', at: now);
    expect(
      shouldRemindNow(r,
          latestVersion: '1.4.0',
          now: now.add(const Duration(hours: 1)),
          interval: day),
      isTrue,
    );
  });

  test('a clock that went backwards does not hide the prompt forever', () {
    final r = RemindLaterRecord(version: '1.3.0', at: now);
    expect(
      shouldRemindNow(r,
          latestVersion: '1.3.0',
          now: now.subtract(const Duration(days: 30)),
          interval: day),
      isTrue,
    );
  });

  test('InMemoryRemindLaterStore round-trips', () async {
    final store = InMemoryRemindLaterStore();
    expect(await store.read(), isNull);
    await store.write(RemindLaterRecord(version: '2.0.0', at: now));
    final back = await store.read();
    expect(back!.version, '2.0.0');
    expect(back.at, now);
  });
}
