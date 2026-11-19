/// @docImport '../response_signal_source.dart';
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../remind_later.dart';
import '../sources.dart';
import '../strings.dart';
import '../update_decision.dart';
import '../update_policy.dart';
import 'forced_update_page.dart';
import 'optional_update_dialog.dart';
import 'update_prompt.dart';

/// Checks for updates when first built, then prompts.
///
/// When [source] is also a [Listenable] (such as [ResponseSignalSource]),
/// the gate checks again each time it notifies, so a forced update can
/// appear in the middle of a session. Other sources are checked once.
///
/// - Forced: pushes a full-screen page that back navigation cannot pop.
/// - Optional: shows a dismissible dialog, at most once per
///   [UpdatePolicy.remindAfter] after the user taps "Later".
/// - Anything else, including every error: shows [child] untouched.
///
/// [child] is always shown while the check runs, so startup is never
/// blocked. The gate needs a [Navigator]: place it below one (for example
/// as `MaterialApp.home`), or pass the app's [navigatorKey] when placing it
/// in `MaterialApp.builder`.
class UpdateGate extends StatefulWidget {
  /// Creates a gate.
  const UpdateGate({
    super.key,
    required this.source,
    required this.currentVersion,
    required this.onOpenStore,
    required this.child,
    this.remindLaterStore,
    this.onDecision,
    this.platform,
    this.clock,
    this.strings,
    this.locale,
    this.forcedBuilder,
    this.optionalBuilder,
    this.navigatorKey,
    this.timeout = const Duration(seconds: 8),
  });

  /// Where the rules come from.
  final UpdatePolicySource source;

  /// Returns the running version, for example from `package_info_plus`
  /// as `'${info.version}+${info.buildNumber}'`.
  final FutureOr<String> Function() currentVersion;

  /// Opens the store, for example with `url_launcher`. Receives the whole
  /// decision so it can fall back when [UpdateDecision.storeUrl] is null.
  final FutureOr<void> Function(UpdateDecision decision) onOpenStore;

  /// The app.
  final Widget child;

  /// Where "Later" is remembered. Defaults to memory only.
  final RemindLaterStore? remindLaterStore;

  /// Called with the decision of every check, including [UpdateKind.none]
  /// on errors.
  final ValueChanged<UpdateDecision>? onDecision;

  /// Which per-platform override to use. Defaults to the running platform.
  final UpdatePlatform? platform;

  /// The current time, injectable for tests.
  final DateTime Function()? clock;

  /// Texts. Defaults to the built-in strings of the current locale.
  final UpdateGateStrings? strings;

  /// Locale for texts. Defaults to the ambient [Localizations] locale.
  final Locale? locale;

  /// Replaces the default [ForcedUpdatePage].
  final UpdatePromptBuilder? forcedBuilder;

  /// Replaces the default [OptionalUpdateDialog].
  final UpdatePromptBuilder? optionalBuilder;

  /// The app's navigator, when the gate is not below it.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// How long the source and [currentVersion] may take before the gate
  /// gives up and shows nothing.
  final Duration timeout;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  late final RemindLaterStore _store =
      widget.remindLaterStore ?? InMemoryRemindLaterStore();

  bool _checking = false;
  bool _checkAgain = false;
  bool _forcedShown = false;
  bool _optionalShowing = false;

  @override
  void initState() {
    super.initState();
    _listen(widget.source);
    unawaited(_check());
  }

  @override
  void didUpdateWidget(UpdateGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      _unlisten(oldWidget.source);
      _listen(widget.source);
    }
  }

  @override
  void dispose() {
    _unlisten(widget.source);
    super.dispose();
  }

  void _listen(UpdatePolicySource source) {
    if (source is Listenable) (source as Listenable).addListener(_onSource);
  }

  void _unlisten(UpdatePolicySource source) {
    if (source is Listenable) {
      (source as Listenable).removeListener(_onSource);
    }
  }

  void _onSource() {
    if (mounted) unawaited(_check());
  }

  /// Runs one check at a time; a signal during a check queues one more.
  Future<void> _check() async {
    if (_checking) {
      _checkAgain = true;
      return;
    }
    _checking = true;
    try {
      do {
        _checkAgain = false;
        await _run();
      } while (_checkAgain && mounted);
    } finally {
      _checking = false;
    }
  }

  Future<void> _run() async {
    final decision = await _decide();
    if (!mounted) return;
    widget.onDecision?.call(decision);
    switch (decision.kind) {
      case UpdateKind.forced:
        if (!_forcedShown) _showForced(decision);
      case UpdateKind.optional:
        if (!_forcedShown && !_optionalShowing) {
          unawaited(_maybeShowOptional(decision));
        }
      case UpdateKind.none:
        break;
    }
  }

  Future<UpdateDecision> _decide() async {
    try {
      final policy = await widget.source.fetch().timeout(widget.timeout);
      final current =
          await Future.sync(widget.currentVersion).timeout(widget.timeout);
      return UpdateDecision.evaluate(
        currentVersion: current,
        policy: policy,
        platform: widget.platform,
      );
    } catch (error) {
      _debug('check failed, showing no prompt: $error');
      return const UpdateDecision.none();
    }
  }

  NavigatorState? get _navigator =>
      widget.navigatorKey?.currentState ??
      Navigator.maybeOf(context, rootNavigator: true);

  UpdatePrompt _prompt(
    BuildContext context,
    UpdateDecision decision, {
    required VoidCallback onUpdate,
    VoidCallback? onLater,
  }) {
    final locale = widget.locale ??
        Localizations.maybeLocaleOf(context) ??
        const Locale('en');
    final strings = widget.strings ?? UpdateGateStrings.of(locale);
    final forced = decision.isForced;
    return UpdatePrompt(
      decision: decision,
      strings: strings,
      title: decision.policy?.titleFor(locale) ??
          (forced ? strings.forcedTitle : strings.optionalTitle),
      message: decision.policy?.messageFor(locale) ??
          (forced ? strings.forcedMessage : strings.optionalMessage),
      onUpdate: onUpdate,
      onLater: onLater,
    );
  }

  void _openStore(UpdateDecision decision) {
    Future.sync(() => widget.onOpenStore(decision)).catchError((Object e) {
      _debug('onOpenStore failed: $e');
    });
  }

  void _showForced(UpdateDecision decision) {
    final navigator = _navigator;
    if (navigator == null) {
      _debug('no Navigator found; pass navigatorKey. No prompt shown.');
      return;
    }
    _forcedShown = true;
    final builder = widget.forcedBuilder ??
        (context, prompt) => ForcedUpdatePage(prompt: prompt);
    unawaited(navigator
        .push(MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'update_gate/forced'),
          builder: (context) => PopScope(
            canPop: false,
            child: builder(
              context,
              _prompt(context, decision, onUpdate: () => _openStore(decision)),
            ),
          ),
        ))
        .whenComplete(() => _forcedShown = false));
  }

  Future<void> _maybeShowOptional(UpdateDecision decision) async {
    _optionalShowing = true;
    try {
      await _showOptional(decision);
    } finally {
      _optionalShowing = false;
    }
  }

  Future<void> _showOptional(UpdateDecision decision) async {
    final version = '${decision.latestVersion}';
    final interval =
        decision.policy?.remindAfter ?? UpdatePolicy.defaultRemindAfter;
    RemindLaterRecord? record;
    try {
      record = await _store.read();
    } catch (error) {
      _debug('remind-later store read failed: $error');
    }
    final now = (widget.clock ?? DateTime.now)();
    if (!shouldRemindNow(record,
        latestVersion: version, now: now, interval: interval)) {
      return;
    }
    if (!mounted) return;
    final navigator = _navigator;
    if (navigator == null) {
      _debug('no Navigator found; pass navigatorKey. No prompt shown.');
      return;
    }

    final builder = widget.optionalBuilder ??
        (context, prompt) => OptionalUpdateDialog(prompt: prompt);
    final updated = await showDialog<bool>(
      context: navigator.context,
      builder: (dialogContext) => builder(
        dialogContext,
        _prompt(
          dialogContext,
          decision,
          onUpdate: () {
            _openStore(decision);
            Navigator.of(dialogContext).pop(true);
          },
          onLater: () => Navigator.of(dialogContext).pop(false),
        ),
      ),
    );
    if (updated ?? false) return;
    try {
      await _store.write(RemindLaterRecord(
        version: version,
        at: (widget.clock ?? DateTime.now)(),
      ));
    } catch (error) {
      _debug('remind-later store write failed: $error');
    }
  }

  void _debug(String message) {
    assert(() {
      debugPrint('UpdateGate: $message');
      return true;
    }());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
