import 'package:flutter/foundation.dart';

final RegExp _pattern = RegExp(
  r'^[vV]?([0-9]+)(?:\.([0-9]+))?(?:\.([0-9]+))?'
  r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
  r'(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
);

/// A semver-like app version: `major.minor.patch[-preRelease][+build]`.
///
/// Parsing is lenient where apps are: `1.2` and `5` fill the missing parts
/// with zero, a leading `v` is allowed, and the `+45` build number that
/// `package_info_plus` style strings carry is kept.
///
/// Ordering follows semver for the first three parts and the pre-release,
/// then compares numeric build numbers (a missing or non-numeric build
/// counts as 0), so `1.2.3+46` is newer than `1.2.3+45`.
@immutable
class AppVersion implements Comparable<AppVersion> {
  /// Creates a version from its parts.
  const AppVersion(
    this.major,
    this.minor,
    this.patch, {
    this.preRelease,
    this.build,
  });

  /// Parses [source], or returns null if it is not a version.
  static AppVersion? tryParse(String? source) {
    if (source == null) return null;
    final match = _pattern.firstMatch(source.trim());
    if (match == null) return null;
    int? part(int group) {
      final text = match.group(group);
      return text == null ? 0 : int.tryParse(text);
    }

    final major = part(1);
    final minor = part(2);
    final patch = part(3);
    if (major == null || minor == null || patch == null) return null;
    return AppVersion(
      major,
      minor,
      patch,
      preRelease: match.group(4),
      build: match.group(5),
    );
  }

  /// Parses [source]. Throws a [FormatException] if it is not a version.
  static AppVersion parse(String source) {
    final version = tryParse(source);
    if (version == null) {
      throw FormatException('Not a version', source);
    }
    return version;
  }

  /// Incompatible changes.
  final int major;

  /// Backwards-compatible features.
  final int minor;

  /// Backwards-compatible fixes.
  final int patch;

  /// The part after `-`, such as `beta.2`, or null.
  final String? preRelease;

  /// The part after `+`, such as `45`, or null.
  final String? build;

  /// [build] as an integer when it is purely numeric, otherwise null.
  int? get buildNumber {
    final b = build;
    if (b == null || !RegExp(r'^[0-9]+$').hasMatch(b)) return null;
    return int.tryParse(b);
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    final pre = _comparePreRelease(preRelease, other.preRelease);
    if (pre != 0) return pre;
    return (buildNumber ?? 0).compareTo(other.buildNumber ?? 0);
  }

  static int _comparePreRelease(String? a, String? b) {
    if (a == b) return 0;
    if (a == null) return 1; // a release is higher than any pre-release
    if (b == null) return -1;
    final left = a.split('.');
    final right = b.split('.');
    for (var i = 0; i < left.length && i < right.length; i++) {
      final l = int.tryParse(left[i]);
      final r = int.tryParse(right[i]);
      final int c;
      if (l != null && r != null) {
        c = l.compareTo(r);
      } else if (l != null) {
        c = -1; // numeric identifiers are lower than alphanumeric ones
      } else if (r != null) {
        c = 1;
      } else {
        c = left[i].compareTo(right[i]);
      }
      if (c != 0) return c;
    }
    return left.length.compareTo(right.length);
  }

  /// Whether this version is older than [other].
  bool operator <(AppVersion other) => compareTo(other) < 0;

  /// Whether this version is older than or equal to [other].
  bool operator <=(AppVersion other) => compareTo(other) <= 0;

  /// Whether this version is newer than [other].
  bool operator >(AppVersion other) => compareTo(other) > 0;

  /// Whether this version is newer than or equal to [other].
  bool operator >=(AppVersion other) => compareTo(other) >= 0;

  /// Equal when [compareTo] returns 0, so `1.2` equals `1.2.0+0`.
  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(
        major,
        minor,
        patch,
        preRelease == null
            ? null
            : Object.hashAll(
                preRelease!.split('.').map((p) => int.tryParse(p) ?? p)),
        buildNumber ?? 0,
      );

  @override
  String toString() {
    final buffer = StringBuffer('$major.$minor.$patch');
    if (preRelease != null) buffer.write('-$preRelease');
    if (build != null) buffer.write('+$build');
    return buffer.toString();
  }
}
