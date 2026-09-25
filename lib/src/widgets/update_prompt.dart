import 'package:flutter/widgets.dart';

import '../strings.dart';
import '../update_decision.dart';

/// Everything a prompt needs to render: texts already localised, and the
/// callbacks to wire to its buttons.
@immutable
class UpdatePrompt {
  /// Creates a prompt.
  const UpdatePrompt({
    required this.decision,
    required this.strings,
    required this.title,
    required this.message,
    required this.onUpdate,
    this.onLater,
  });

  /// The decision that triggered the prompt.
  final UpdateDecision decision;

  /// The strings in use, for button labels.
  final UpdateGateStrings strings;

  /// The resolved title: the policy's, or the default.
  final String title;

  /// The resolved message: the policy's, or the default.
  final String message;

  /// Opens the store.
  final VoidCallback onUpdate;

  /// Postpones the prompt. Null on the forced page.
  final VoidCallback? onLater;

  /// The "current · available" line, or null when a version is unknown.
  String? get versionLine {
    final current = decision.currentVersion;
    final latest = decision.latestVersion ?? decision.minRequiredVersion;
    if (current == null || latest == null) return null;
    return strings.versionLine('$current', '$latest');
  }
}

/// Builds a custom forced page or optional dialog.
typedef UpdatePromptBuilder = Widget Function(
  BuildContext context,
  UpdatePrompt prompt,
);
