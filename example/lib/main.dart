import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:update_gate/update_gate.dart';

void main() => runApp(const ExampleApp());

/// The version this example pretends to be. A real app reads it from
/// package_info_plus; see the README.
const String runningVersion = '1.2.0+12';

/// Demo scenarios, each backed by a [StaticSource].
enum Scenario {
  /// Below the minimum version.
  forced(UpdatePolicy(
    minRequiredVersion: '1.3.0',
    latestVersion: '1.4.0',
    storeUrl: 'https://example.com/store',
  )),

  /// Above the minimum, below the latest.
  optional(UpdatePolicy(
    minRequiredVersion: '1.0.0',
    latestVersion: '1.4.0',
    storeUrl: 'https://example.com/store',
    remindAfter: Duration(minutes: 1),
    messages: {
      'en': 'Version 1.4 brings offline mode.',
      'fr': 'La version 1.4 apporte le mode hors ligne.',
      'ar': 'يضيف الإصدار 1.4 وضع عدم الاتصال.',
    },
  )),

  /// Up to date.
  upToDate(UpdatePolicy(minRequiredVersion: '1.0.0', latestVersion: '1.2.0')),

  /// Junk data: fails open.
  broken(UpdatePolicy(minRequiredVersion: 'not-a-version'));

  const Scenario(this.policy);

  /// The rules served for this scenario.
  final UpdatePolicy policy;
}

/// The example app.
class ExampleApp extends StatefulWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  Scenario _scenario = Scenario.optional;
  Locale _locale = const Locale('en');
  final _remindStore = InMemoryRemindLaterStore();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  void _openStore(UpdateDecision decision) {
    // A real app calls url_launcher here:
    //   launchUrl(decision.storeUrl!, mode: LaunchMode.externalApplication);
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text('Would open ${decision.storeUrl}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // A new key restarts the app, so the gate checks again.
      key: ValueKey((_scenario, _locale)),
      scaffoldMessengerKey: _messengerKey,
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      locale: _locale,
      supportedLocales: const [Locale('en'), Locale('fr'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: UpdateGate(
        source: StaticSource(_scenario.policy),
        currentVersion: () => runningVersion,
        onOpenStore: _openStore,
        remindLaterStore: _remindStore,
        forcedBuilder: (context, prompt) => Stack(
          children: [
            ForcedUpdatePage(prompt: prompt),
            // Only for the demo: a real forced page offers no way out.
            PositionedDirectional(
              top: 40,
              end: 8,
              child: TextButton(
                onPressed: () => setState(() => _scenario = Scenario.optional),
                child: const Text('Demo: leave'),
              ),
            ),
          ],
        ),
        child: DemoHome(
          scenario: _scenario,
          locale: _locale,
          onScenario: (s) => setState(() => _scenario = s),
          onLocale: (l) => setState(() => _locale = l),
        ),
      ),
    );
  }
}

/// Lets you switch scenario and language.
class DemoHome extends StatelessWidget {
  /// Creates the home page.
  const DemoHome({
    super.key,
    required this.scenario,
    required this.locale,
    required this.onScenario,
    required this.onLocale,
  });

  /// The active scenario.
  final Scenario scenario;

  /// The active locale.
  final Locale locale;

  /// Switches scenario.
  final ValueChanged<Scenario> onScenario;

  /// Switches language.
  final ValueChanged<Locale> onLocale;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('update_gate')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Running version $runningVersion'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final s in Scenario.values)
                ChoiceChip(
                  label: Text(s.name),
                  selected: s == scenario,
                  onSelected: (_) => onScenario(s),
                ),
            ],
          ),
          const Divider(),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'en', label: Text('English')),
              ButtonSegment(value: 'fr', label: Text('Français')),
              ButtonSegment(value: 'ar', label: Text('العربية')),
            ],
            selected: {locale.languageCode},
            onSelectionChanged: (s) => onLocale(Locale(s.first)),
          ),
        ],
      ),
    );
  }
}
