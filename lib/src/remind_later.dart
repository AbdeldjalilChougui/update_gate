import 'package:flutter/foundation.dart';

import 'app_version.dart';

/// When the user last chose "Later", and for which latest version.
@immutable
class RemindLaterRecord {
  /// Creates a record.
  const RemindLaterRecord({required this.version, required this.at});

  /// Reads a record written by [toJson]. Returns null on bad data.
  static RemindLaterRecord? fromJson(Map<String, Object?> json) {
    final version = json['version'];
    final at = json['at'];
    if (version is! String || at is! int) return null;
    return RemindLaterRecord(
      version: version,
      at: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }

  /// The latest version the user postponed.
  final String version;

  /// When they postponed it.
  final DateTime at;

  /// A JSON-friendly form for key-value stores.
  Map<String, Object?> toJson() =>
      {'version': version, 'at': at.millisecondsSinceEpoch};
}

/// Persists the "remind me later" choice. Plug in shared_preferences,
/// secure storage, a database, or keep the in-memory default.
abstract interface class RemindLaterStore {
  /// The saved record, or null.
  Future<RemindLaterRecord?> read();

  /// Saves [record], replacing any previous one.
  Future<void> write(RemindLaterRecord record);
}

/// A [RemindLaterStore] that forgets on restart.
class InMemoryRemindLaterStore implements RemindLaterStore {
  /// Creates a store, optionally with an initial [record].
  InMemoryRemindLaterStore([RemindLaterRecord? record]) : _record = record;

  RemindLaterRecord? _record;

  @override
  Future<RemindLaterRecord?> read() async => _record;

  @override
  Future<void> write(RemindLaterRecord record) async => _record = record;
}

/// Whether the optional prompt for [latestVersion] is due at [now].
///
/// Due when nothing was postponed, when a different version was postponed,
/// when [interval] has passed, or when the clock is behind the record.
bool shouldRemindNow(
  RemindLaterRecord? record, {
  required String latestVersion,
  required DateTime now,
  required Duration interval,
}) {
  if (record == null) return true;
  final a = AppVersion.tryParse(record.version);
  final b = AppVersion.tryParse(latestVersion);
  final same = a != null && b != null
      ? a == b
      : record.version.trim() == latestVersion.trim();
  if (!same) return true;
  if (now.isBefore(record.at)) return true;
  return now.difference(record.at) >= interval;
}
