import 'package:flutter/foundation.dart';

import 'app_version.dart';
import 'update_policy.dart';

/// What the app should do about updates.
enum UpdateKind {
  /// Nothing: up to date, or the rules could not be evaluated.
  none,

  /// A newer version exists; the user may postpone it.
  optional,

  /// This version is below the minimum; the app is blocked until updated.
  forced,
}

/// The outcome of comparing the running version with an [UpdatePolicy].
@immutable
class UpdateDecision {
  /// Creates a decision. Usually obtained from [evaluate].
  const UpdateDecision({
    required this.kind,
    this.currentVersion,
    this.minRequiredVersion,
    this.latestVersion,
    this.storeUrl,
    this.policy,
  });

  /// A decision to do nothing, with no data.
  const UpdateDecision.none()
      : kind = UpdateKind.none,
        currentVersion = null,
        minRequiredVersion = null,
        latestVersion = null,
        storeUrl = null,
        policy = null;

  /// Decides what to do for [currentVersion] under [policy].
  ///
  /// Pure and total: it never throws. It **fails open**, returning
  /// [UpdateKind.none] when the policy is null, the current version is
  /// missing or junk, a configured rule version is junk, or no rule is set.
  /// An empty rule string counts as not set. [platform] picks the
  /// per-platform override and defaults to [UpdatePlatform.current].
  static UpdateDecision evaluate({
    required String? currentVersion,
    required UpdatePolicy? policy,
    UpdatePlatform? platform,
  }) {
    try {
      if (policy == null) return const UpdateDecision.none();
      final rules = policy.resolve(platform ?? UpdatePlatform.current);
      final current = AppVersion.tryParse(currentVersion);
      if (current == null) return const UpdateDecision.none();

      final minRaw = rules.minRequiredVersion?.trim() ?? '';
      final latestRaw = rules.latestVersion?.trim() ?? '';
      final min = minRaw.isEmpty ? null : AppVersion.tryParse(minRaw);
      final latest = latestRaw.isEmpty ? null : AppVersion.tryParse(latestRaw);
      if ((minRaw.isNotEmpty && min == null) ||
          (latestRaw.isNotEmpty && latest == null) ||
          (min == null && latest == null)) {
        return const UpdateDecision.none();
      }

      final kind = min != null && current < min
          ? UpdateKind.forced
          : latest != null && current < latest
              ? UpdateKind.optional
              : UpdateKind.none;
      return UpdateDecision(
        kind: kind,
        currentVersion: current,
        minRequiredVersion: min,
        latestVersion: latest,
        storeUrl: _parseUrl(rules.storeUrl),
        policy: rules,
      );
    } catch (_) {
      return const UpdateDecision.none();
    }
  }

  static Uri? _parseUrl(String? raw) {
    if (raw == null) return null;
    final uri = Uri.tryParse(raw.trim());
    return uri != null && uri.hasScheme ? uri : null;
  }

  /// What to do.
  final UpdateKind kind;

  /// The running version, if it parsed.
  final AppVersion? currentVersion;

  /// The minimum version from the policy, if set.
  final AppVersion? minRequiredVersion;

  /// The latest version from the policy, if set.
  final AppVersion? latestVersion;

  /// The store link, if the policy has a valid absolute URL.
  final Uri? storeUrl;

  /// The policy with the platform override applied.
  final UpdatePolicy? policy;

  /// Whether the app must be blocked.
  bool get isForced => kind == UpdateKind.forced;

  /// Whether an optional prompt is due (subject to "remind me later").
  bool get isOptional => kind == UpdateKind.optional;

  @override
  String toString() => 'UpdateDecision(${kind.name}, current: $currentVersion, '
      'min: $minRequiredVersion, latest: $latestVersion)';
}
