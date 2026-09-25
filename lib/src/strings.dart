import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';

/// The default texts of the update prompts.
///
/// Built in: [en], [fr] and [ar]. Pick one with [of], adjust it with
/// [copyWith], or build your own for other languages.
@immutable
class UpdateGateStrings {
  /// Creates a set of strings.
  ///
  /// [versions] may contain `{current}` and `{latest}` placeholders.
  const UpdateGateStrings({
    required this.forcedTitle,
    required this.forcedMessage,
    required this.optionalTitle,
    required this.optionalMessage,
    required this.update,
    required this.later,
    required this.versions,
  });

  /// English.
  static const UpdateGateStrings en = UpdateGateStrings(
    forcedTitle: 'Update required',
    forcedMessage:
        'This version is no longer supported. Please update to continue.',
    optionalTitle: 'Update available',
    optionalMessage: 'A new version is available with improvements and fixes.',
    update: 'Update',
    later: 'Later',
    versions: 'Current version: {current} · Available: {latest}',
  );

  /// French.
  static const UpdateGateStrings fr = UpdateGateStrings(
    forcedTitle: 'Mise à jour requise',
    forcedMessage: "Cette version n'est plus prise en charge. "
        'Veuillez mettre à jour pour continuer.',
    optionalTitle: 'Mise à jour disponible',
    optionalMessage: 'Une nouvelle version est disponible avec des '
        'améliorations et des corrections.',
    update: 'Mettre à jour',
    later: 'Plus tard',
    versions: 'Version actuelle : {current} · Disponible : {latest}',
  );

  /// Arabic.
  static const UpdateGateStrings ar = UpdateGateStrings(
    forcedTitle: 'تحديث مطلوب',
    forcedMessage: 'هذا الإصدار لم يعد مدعومًا. يرجى التحديث للمتابعة.',
    optionalTitle: 'تحديث متوفر',
    optionalMessage: 'يتوفر إصدار جديد يتضمن تحسينات وإصلاحات.',
    update: 'تحديث',
    later: 'لاحقًا',
    versions: 'الإصدار الحالي: {current} · المتوفر: {latest}',
  );

  /// The built-in strings for [locale]'s language, English otherwise.
  static UpdateGateStrings of(Locale locale) =>
      switch (locale.languageCode.toLowerCase()) {
        'fr' => fr,
        'ar' => ar,
        _ => en,
      };

  /// Title of the forced page.
  final String forcedTitle;

  /// Message of the forced page when the policy has none.
  final String forcedMessage;

  /// Title of the optional dialog.
  final String optionalTitle;

  /// Message of the optional dialog when the policy has none.
  final String optionalMessage;

  /// The update button.
  final String update;

  /// The "remind me later" button.
  final String later;

  /// The version line template, with `{current}` and `{latest}`.
  final String versions;

  /// [versions] with the placeholders filled in.
  String versionLine(String current, String latest) =>
      versions.replaceAll('{current}', current).replaceAll('{latest}', latest);

  /// A copy with the given fields replaced.
  UpdateGateStrings copyWith({
    String? forcedTitle,
    String? forcedMessage,
    String? optionalTitle,
    String? optionalMessage,
    String? update,
    String? later,
    String? versions,
  }) =>
      UpdateGateStrings(
        forcedTitle: forcedTitle ?? this.forcedTitle,
        forcedMessage: forcedMessage ?? this.forcedMessage,
        optionalTitle: optionalTitle ?? this.optionalTitle,
        optionalMessage: optionalMessage ?? this.optionalMessage,
        update: update ?? this.update,
        later: later ?? this.later,
        versions: versions ?? this.versions,
      );

  @override
  bool operator ==(Object other) =>
      other is UpdateGateStrings &&
      forcedTitle == other.forcedTitle &&
      forcedMessage == other.forcedMessage &&
      optionalTitle == other.optionalTitle &&
      optionalMessage == other.optionalMessage &&
      update == other.update &&
      later == other.later &&
      versions == other.versions;

  @override
  int get hashCode => Object.hash(forcedTitle, forcedMessage, optionalTitle,
      optionalMessage, update, later, versions);
}
