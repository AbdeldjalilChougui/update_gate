/// @docImport 'update_decision.dart';
library;

import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';

/// A platform an [UpdatePolicy] can override rules for.
enum UpdatePlatform {
  /// Android.
  android,

  /// iOS and iPadOS.
  ios,

  /// macOS.
  macos,

  /// Windows.
  windows,

  /// Linux.
  linux,

  /// Fuchsia.
  fuchsia,

  /// The web.
  web;

  /// The platform the app is running on.
  static UpdatePlatform get current {
    if (kIsWeb) return UpdatePlatform.web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => UpdatePlatform.android,
      TargetPlatform.iOS => UpdatePlatform.ios,
      TargetPlatform.macOS => UpdatePlatform.macos,
      TargetPlatform.windows => UpdatePlatform.windows,
      TargetPlatform.linux => UpdatePlatform.linux,
      TargetPlatform.fuchsia => UpdatePlatform.fuchsia,
    };
  }

  /// The platform called [name] (case-insensitive), or null.
  static UpdatePlatform? fromName(String name) {
    final lower = name.toLowerCase();
    for (final platform in values) {
      if (platform.name == lower) return platform;
    }
    return null;
  }
}

/// The update rules, as delivered by an update policy source.
///
/// Versions are kept as the raw strings the source delivered. An
/// [UpdateDecision] parses them and fails open when they are junk.
@immutable
class UpdatePolicy {
  /// Creates a policy. Every field is optional.
  const UpdatePolicy({
    this.minRequiredVersion,
    this.latestVersion,
    this.storeUrl,
    this.forceUpdate = false,
    Duration? remindAfter,
    this.titles = const {},
    this.messages = const {},
    this.platforms = const {},
  }) : _remindAfter = remindAfter;

  /// Reads a policy from JSON. Fields of the wrong type are ignored.
  ///
  /// ```json
  /// {
  ///   "min_required_version": "1.2.0",
  ///   "latest_version": "1.4.0+52",
  ///   "store_url": "https://play.google.com/store/apps/details?id=my.app",
  ///   "remind_after_hours": 24,
  ///   "force_update": false,
  ///   "title": {"en": "New version", "fr": "Nouvelle version"},
  ///   "message": {"en": "Faster sync.", "ar": "مزامنة أسرع."},
  ///   "platforms": {"ios": {"store_url": "https://apps.apple.com/app/id1"}}
  /// }
  /// ```
  ///
  /// `title` and `message` may also be a plain string used for every locale.
  factory UpdatePolicy.fromJson(Map<String, Object?> json) =>
      _fromJson(json, nested: false);

  static UpdatePolicy _fromJson(Map<String, Object?> json,
      {required bool nested}) {
    String? version(Object? v) => switch (v) {
          final String s => s,
          final num n => n.toString(),
          _ => null,
        };
    Map<String, String> localized(Object? v) => switch (v) {
          final String s => {_defaultKey: s},
          final Map<Object?, Object?> m => {
              for (final e in m.entries)
                if (e.key is String && e.value is String)
                  e.key! as String: e.value! as String,
            },
          _ => const {},
        };
    final hours = json['remind_after_hours'];
    final platforms = <UpdatePlatform, UpdatePolicy>{};
    final rawPlatforms = json['platforms'];
    if (!nested && rawPlatforms is Map<Object?, Object?>) {
      for (final e in rawPlatforms.entries) {
        final key = e.key;
        final value = e.value;
        final platform = key is String ? UpdatePlatform.fromName(key) : null;
        if (platform != null && value is Map<String, Object?>) {
          platforms[platform] = _fromJson(value, nested: true);
        }
      }
    }
    return UpdatePolicy(
      minRequiredVersion: version(json['min_required_version']),
      latestVersion: version(json['latest_version']),
      storeUrl:
          json['store_url'] is String ? json['store_url']! as String : null,
      forceUpdate: json['force_update'] == true,
      remindAfter: hours is num && hours >= 0
          ? Duration(minutes: (hours * 60).round())
          : null,
      titles: localized(json['title']),
      messages: localized(json['message']),
      platforms: platforms,
    );
  }

  static const String _defaultKey = 'default';

  /// How long "Later" hides the optional prompt when a policy sets nothing.
  static const Duration defaultRemindAfter = Duration(hours: 24);

  /// Versions below this must update: the forced prompt.
  final String? minRequiredVersion;

  /// Versions below this may update: the optional prompt.
  final String? latestVersion;

  /// Where the update button leads.
  final String? storeUrl;

  /// Forces the update whatever the running version is, for example when
  /// the server answered `426 Upgrade Required`. A platform override can
  /// turn it on but not off.
  final bool forceUpdate;

  final Duration? _remindAfter;

  /// How long "Later" hides the optional prompt for the same latest version.
  Duration get remindAfter => _remindAfter ?? defaultRemindAfter;

  /// Prompt titles by locale (`en`, `fr`, `fr_CA`, `pt-BR`, or `default`).
  final Map<String, String> titles;

  /// Prompt messages by locale (`en`, `fr`, `fr_CA`, `pt-BR`, or `default`).
  final Map<String, String> messages;

  /// Per-platform overrides. Their unset fields fall back to this policy.
  final Map<UpdatePlatform, UpdatePolicy> platforms;

  /// A copy with the given fields replaced. A null argument keeps the field.
  UpdatePolicy copyWith({
    String? minRequiredVersion,
    String? latestVersion,
    String? storeUrl,
    bool? forceUpdate,
    Duration? remindAfter,
    Map<String, String>? titles,
    Map<String, String>? messages,
    Map<UpdatePlatform, UpdatePolicy>? platforms,
  }) =>
      UpdatePolicy(
        minRequiredVersion: minRequiredVersion ?? this.minRequiredVersion,
        latestVersion: latestVersion ?? this.latestVersion,
        storeUrl: storeUrl ?? this.storeUrl,
        forceUpdate: forceUpdate ?? this.forceUpdate,
        remindAfter: remindAfter ?? _remindAfter,
        titles: titles ?? this.titles,
        messages: messages ?? this.messages,
        platforms: platforms ?? this.platforms,
      );

  /// This policy with the override for [platform] applied.
  UpdatePolicy resolve(UpdatePlatform platform) {
    final o = platforms[platform];
    if (o == null) return this;
    return UpdatePolicy(
      minRequiredVersion: o.minRequiredVersion ?? minRequiredVersion,
      latestVersion: o.latestVersion ?? latestVersion,
      storeUrl: o.storeUrl ?? storeUrl,
      forceUpdate: o.forceUpdate || forceUpdate,
      remindAfter: o._remindAfter ?? _remindAfter,
      titles: {...titles, ...o.titles},
      messages: {...messages, ...o.messages},
    );
  }

  /// The message for [locale]: exact match, then language, then `default`,
  /// then English. Null when none fits.
  String? messageFor(Locale locale) => _lookup(messages, locale);

  /// The title for [locale], with the same fallbacks as [messageFor].
  String? titleFor(Locale locale) => _lookup(titles, locale);

  static String? _lookup(Map<String, String> map, Locale locale) {
    if (map.isEmpty) return null;
    final normalized = {
      for (final e in map.entries)
        e.key.replaceAll('-', '_').toLowerCase(): e.value,
    };
    final language = locale.languageCode.toLowerCase();
    final country = locale.countryCode?.toLowerCase();
    return (country != null ? normalized['${language}_$country'] : null) ??
        normalized[language] ??
        normalized[_defaultKey] ??
        normalized['en'];
  }
}
