import 'package:flutter/material.dart';

import 'update_prompt.dart';

/// The default full-screen page for a forced update.
///
/// [UpdateGate] shows it in a route that cannot be popped.
class ForcedUpdatePage extends StatelessWidget {
  /// Creates the page.
  const ForcedUpdatePage({super.key, required this.prompt});

  /// Texts and callbacks.
  final UpdatePrompt prompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final versions = prompt.versionLine;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.system_update_alt,
                      size: 96, color: theme.colorScheme.primary),
                  const SizedBox(height: 24),
                  Text(
                    prompt.title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    prompt.message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: prompt.onUpdate,
                    child: Text(prompt.strings.update),
                  ),
                  if (versions != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      versions,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
