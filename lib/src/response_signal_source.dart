/// @docImport 'widgets/update_gate.dart';
library;

import 'package:flutter/foundation.dart';

import 'app_version.dart';
import 'sources.dart';
import 'update_policy.dart';

/// A source fed by your app's own HTTP layer: a `426 Upgrade Required`
/// status, or a minimum-version response header.
///
/// Call [observe] (or [observeHeaders]) from an `http.Client` wrapper, a dio
/// interceptor or any other place that sees responses. The source keeps the
/// strongest signal seen so far and notifies its listeners when it gets
/// stronger, so an [UpdateGate] using it checks again in the middle of the
/// session.
///
/// - A 426 status: forced, whatever the running version
///   ([UpdatePolicy.forceUpdate]).
/// - A header that parses as a version: it becomes the minimum required
///   version, so it forces only when it is above the running version.
/// - A missing or unparseable header, or any other status: ignored.
///
/// Without any signal, [fetch] returns the [base] policy (or null), so the
/// gate shows nothing: it fails open.
class ResponseSignalSource extends ChangeNotifier
    implements UpdatePolicySource {
  /// Creates a source.
  ///
  /// [base] is another source whose policy the signals are laid over, such
  /// as a [JsonUrlSource] that also drives optional updates. [template]
  /// supplies the store URL, titles and messages when there is no base
  /// policy. [headerName] is read by [observeHeaders], case-insensitively.
  ResponseSignalSource({
    this.base,
    this.template,
    this.headerName = defaultHeaderName,
  });

  /// The header [observeHeaders] reads by default.
  static const String defaultHeaderName = 'X-Min-App-Version';

  /// The status that forces an update: `426 Upgrade Required`.
  static const int upgradeRequired = 426;

  /// Another source the signals are laid over, or null.
  final UpdatePolicySource? base;

  /// Store URL, titles and messages used when there is no base policy.
  final UpdatePolicy? template;

  /// The minimum-version header read by [observeHeaders].
  final String headerName;

  bool _upgradeRequired = false;
  AppVersion? _minVersion;

  /// Whether a 426 status has been seen.
  bool get upgradeRequiredSeen => _upgradeRequired;

  /// The highest valid minimum version seen in a header, or null.
  AppVersion? get minVersionSeen => _minVersion;

  /// Whether any signal has been kept.
  bool get hasSignal => _upgradeRequired || _minVersion != null;

  /// Records one response. Never throws.
  ///
  /// [minVersion] is the raw header value; junk is ignored. Listeners are
  /// notified only when the kept signal gets stronger.
  void observe({required int statusCode, String? minVersion}) {
    var changed = false;
    if (statusCode == upgradeRequired && !_upgradeRequired) {
      _upgradeRequired = true;
      changed = true;
    }
    final version = AppVersion.tryParse(minVersion);
    if (version != null) {
      final kept = _minVersion;
      if (kept == null || version > kept) {
        _minVersion = version;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Records one response, reading [headerName] from [headers] in any case.
  ///
  /// Header values may be a `String` or a list of strings (dio); the first
  /// string is used.
  void observeHeaders(int statusCode, Map<String, Object?> headers) {
    final wanted = headerName.toLowerCase();
    String? value;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() != wanted) continue;
      final v = entry.value;
      value = switch (v) {
        final String s => s,
        final Iterable<Object?> list => list.whereType<String>().firstOrNull,
        _ => null,
      };
      break;
    }
    observe(statusCode: statusCode, minVersion: value);
  }

  /// Forgets every signal, for example after a sign-out. Does not notify.
  void clear() {
    _upgradeRequired = false;
    _minVersion = null;
  }

  @override
  Future<UpdatePolicy?> fetch() async {
    if (!hasSignal) return base?.fetch();
    UpdatePolicy? basePolicy;
    try {
      basePolicy = await base?.fetch();
    } catch (_) {
      // The signal alone is enough; a failing base must not hide it.
    }
    return _overlay(basePolicy ?? template ?? const UpdatePolicy());
  }

  UpdatePolicy _overlay(UpdatePolicy policy, {bool nested = false}) =>
      policy.copyWith(
        minRequiredVersion: _raise(policy.minRequiredVersion, nested: nested),
        forceUpdate: policy.forceUpdate || (!nested && _upgradeRequired),
        platforms: {
          for (final e in policy.platforms.entries)
            e.key: _overlay(e.value, nested: true),
        },
      );

  /// The higher of [existing] and the header's version. A platform override
  /// without its own minimum keeps inheriting the top-level one.
  String? _raise(String? existing, {required bool nested}) {
    final signal = _minVersion;
    if (signal == null) return existing;
    final raw = existing?.trim() ?? '';
    if (raw.isEmpty) return nested ? existing : signal.toString();
    final current = AppVersion.tryParse(raw);
    return current != null && current >= signal ? existing : signal.toString();
  }
}
