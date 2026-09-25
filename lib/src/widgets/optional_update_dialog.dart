import 'package:flutter/material.dart';

import 'update_prompt.dart';

/// The default dialog for an optional update.
class OptionalUpdateDialog extends StatelessWidget {
  /// Creates the dialog.
  const OptionalUpdateDialog({super.key, required this.prompt});

  /// Texts and callbacks.
  final UpdatePrompt prompt;

  @override
  Widget build(BuildContext context) {
    final later = prompt.onLater;
    return AlertDialog(
      icon: const Icon(Icons.system_update_alt),
      title: Text(prompt.title),
      content: Text(prompt.message),
      actions: [
        if (later != null)
          TextButton(onPressed: later, child: Text(prompt.strings.later)),
        FilledButton(
          onPressed: prompt.onUpdate,
          child: Text(prompt.strings.update),
        ),
      ],
    );
  }
}
