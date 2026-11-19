# update_gate

Forced and optional app-update prompts for Flutter that work with any source
of version rules: your own JSON endpoint, Remote Config or a database. It
fails open, so a broken rule never locks users out.

[![pub package](https://img.shields.io/pub/v/update_gate.svg)](https://pub.dev/packages/update_gate)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Features

- `AppVersion`: semver-like parsing (`1.2`, `5`, `v1.2.3`, `1.2.3+45`,
  `1.0.0-beta.2+7`) and ordering that includes numeric build numbers.
- `UpdatePolicy`: minimum required version, latest version, store URL,
  "remind me later" interval, title and message per locale, and
  per-platform overrides. Reads a simple JSON format.
- `UpdateDecision.evaluate`: a pure function returning `none`, `optional`
  or `forced`. It **fails open**: missing data, junk versions or any error
  give `none`.
- `UpdatePolicySource` interface with `JsonUrlSource` (package:http,
  injectable client) and `StaticSource`.
- `ResponseSignalSource`: drives the forced page from your normal API
  responses (`426 Upgrade Required` or a minimum-version header), fed by
  your own HTTP layer. No dio or interceptor dependency.
- Sources that are also a `Listenable` make the gate check again when they
  notify, so a forced update can appear in the middle of a session.
- `UpdateGate` widget:
  - **forced**: a full-screen page that back navigation cannot pop
    (`PopScope`);
  - **optional**: a dismissible dialog, shown again only after the remind
    interval, with a pluggable `RemindLaterStore`;
  - opens the store through **your callback**, so there is no url_launcher
    dependency;
  - reads the running version through **your callback**, so there is no
    package_info_plus dependency.
- Default texts in **English, French and Arabic**; RTL layouts follow the
  ambient `Directionality`.
- Custom builders for the forced page and the dialog.

## Install

```yaml
dependencies:
  update_gate: ^0.2.0
```

## Usage

### Wiring package_info_plus and url_launcher

Both are your app's dependencies, not this package's:

```dart
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:update_gate/update_gate.dart';
import 'package:url_launcher/url_launcher.dart';

MaterialApp(
  home: UpdateGate(
    source: JsonUrlSource(Uri.parse('https://example.com/app/update.json')),
    currentVersion: () async {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    },
    onOpenStore: (decision) async {
      final url = decision.storeUrl;
      if (url != null) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    },
    child: const HomePage(),
  ),
);
```

The gate needs a `Navigator`. As `home` it finds it by itself. If you put it
in `MaterialApp.builder` (above the navigator), pass the same
`navigatorKey` to both.

### The JSON format

```json
{
  "min_required_version": "1.2.0",
  "latest_version": "1.4.0+52",
  "store_url": "https://play.google.com/store/apps/details?id=my.app",
  "remind_after_hours": 24,
  "force_update": false,
  "title": {"en": "New version", "fr": "Nouvelle version"},
  "message": {
    "en": "Faster sync and bug fixes.",
    "fr": "Synchronisation plus rapide et corrections.",
    "ar": "مزامنة أسرع وإصلاحات."
  },
  "platforms": {
    "ios": {
      "min_required_version": "1.3.0",
      "store_url": "https://apps.apple.com/app/id000000000"
    }
  }
}
```

Every field is optional. `title` and `message` may be plain strings. Locale
keys are matched exactly (`fr_CA` or `fr-CA`), then by language, then
`default`, then `en`; without a match the built-in text is used. Platform
keys: `android`, `ios`, `macos`, `windows`, `linux`, `fuchsia`, `web`.
`force_update: true` blocks every version (a kill switch); only the JSON
value `true` turns it on.

### Deciding without the widget

```dart
final decision = UpdateDecision.evaluate(
  currentVersion: '1.2.0+12',
  policy: const UpdatePolicy(minRequiredVersion: '1.3.0'),
  platform: UpdatePlatform.android,
);
if (decision.isForced) {
  // Block the app your own way.
}
```

The rules:

| Situation | Result |
| --- | --- |
| `forceUpdate` set (for example after a 426) | `forced`, whatever the versions |
| current < min | `forced` |
| min <= current < latest | `optional` |
| current >= latest, or only min set and current >= min | `none` |
| no policy, junk or empty current version | `none` |
| a configured min or latest that is junk | `none` (for both rules) |
| neither min nor latest set | `none` |

### Forcing from API responses (426 or a header)

If your API already says when a build is too old, let your HTTP layer feed
a `ResponseSignalSource`. It keeps the strongest signal seen:

| Response | Result |
| --- | --- |
| status `426 Upgrade Required` | `forced` |
| `X-Min-App-Version` header above the running version | `forced` |
| header equal to or below the running version | nothing |
| header missing or not a version | ignored |
| no response observed | nothing (fails open) |

The source is a `ChangeNotifier`: the gate listens to it and checks again
as soon as a stronger signal arrives, mid-session. Pass `base` to keep your
usual rules (optional updates, store URL, texts) and lay the signals over
them, or `template` for just the store URL and texts. Rename the header
with `headerName`.

```dart
final signals = ResponseSignalSource(
  base: JsonUrlSource(Uri.parse('https://example.com/app/update.json')),
  template: const UpdatePolicy(
    storeUrl: 'https://play.google.com/store/apps/details?id=my.app',
  ),
);

UpdateGate(source: signals, /* ... */ child: const HomePage());
```

**With package:http** (sketch): wrap the client your app already uses.

```dart
class SignalClient extends http.BaseClient {
  SignalClient(this._inner, this._signals);
  final http.Client _inner;
  final ResponseSignalSource _signals;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    _signals.observeHeaders(response.statusCode, response.headers);
    return response;
  }
}
```

**With dio** (sketch, dio is your app's dependency): an interceptor. A 426
arrives as an error by default, so look at both paths.

```dart
class SignalInterceptor extends Interceptor {
  SignalInterceptor(this._signals);
  final ResponseSignalSource _signals;

  void _observe(Response<dynamic>? r) {
    if (r != null) _signals.observeHeaders(r.statusCode ?? 0, r.headers.map);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler h) {
    _observe(response);
    h.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler h) {
    _observe(err.response);
    h.next(err);
  }
}

dio.interceptors.add(SignalInterceptor(signals));
```

Any other source can do the same: implement `UpdatePolicySource` on a
`ChangeNotifier` and call `notifyListeners()` when the rules change.

### Remembering "Later"

The default store forgets on restart. Persist it with any key-value store.
**Sketch, not compiled in this package** (shared_preferences):

```dart
class PrefsRemindLaterStore implements RemindLaterStore {
  static const _key = 'update_gate.remind_later';

  @override
  Future<RemindLaterRecord?> read() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return null;
    return RemindLaterRecord.fromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  @override
  Future<void> write(RemindLaterRecord record) async {
    await (await SharedPreferences.getInstance())
        .setString(_key, jsonEncode(record.toJson()));
  }
}
```

### Adapter: Firebase Remote Config

**Sketch, not compiled in this package.** It needs `firebase_remote_config`
in your app.

```dart
class RemoteConfigSource implements UpdatePolicySource {
  @override
  Future<UpdatePolicy?> fetch() async {
    final rc = FirebaseRemoteConfig.instance;
    await rc.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 8),
      minimumFetchInterval: const Duration(hours: 12),
    ));
    await rc.fetchAndActivate();
    // Keep the whole policy in one JSON parameter...
    final json = rc.getString('update_policy');
    if (json.isEmpty) return null;
    return UpdatePolicy.fromJson(jsonDecode(json) as Map<String, Object?>);
    // ...or map individual parameters:
    // return UpdatePolicy(
    //   minRequiredVersion: rc.getString('min_required_version'),
    //   latestVersion: rc.getString('latest_version'),
    //   storeUrl: rc.getString('store_url_android'),
    // );
  }
}
```

### Adapter: Supabase

**Sketch, not compiled in this package.** It needs `supabase_flutter` and a
table whose columns use the JSON field names above.

```dart
class SupabaseSource implements UpdatePolicySource {
  SupabaseSource(this.appId);
  final String appId;

  @override
  Future<UpdatePolicy?> fetch() async {
    final row = await Supabase.instance.client
        .from('app_update_policy')
        .select()
        .eq('app_id', appId)
        .maybeSingle();
    return row == null ? null : UpdatePolicy.fromJson(row);
  }
}
```

### Texts and custom UI

```dart
UpdateGate(
  // ...
  strings: UpdateGateStrings.fr.copyWith(later: 'Pas maintenant'),
  forcedBuilder: (context, prompt) => MyForcedPage(
    title: prompt.title,
    message: prompt.message,
    onUpdate: prompt.onUpdate,
  ),
  optionalBuilder: (context, prompt) => AlertDialog(
    title: Text(prompt.title),
    actions: [
      TextButton(onPressed: prompt.onLater, child: Text(prompt.strings.later)),
      TextButton(onPressed: prompt.onUpdate, child: Text(prompt.strings.update)),
    ],
  ),
  child: const HomePage(),
);
```

The forced route is wrapped in `PopScope(canPop: false)` whatever the
builder returns.

## Limitations

- The gate checks once, when it is first built, unless its source is a
  `Listenable` (such as `ResponseSignalSource`) that notifies. It does not
  re-check on app resume by itself.
- `ResponseSignalSource` keeps signals in memory for the session; they are
  not persisted, so a restart starts clean until the next response.
- A forced page is a pushed route: code that later calls `Navigator.pop`
  directly (not `maybePop`) can still remove it.
- Only one "remind me later" interval per policy (default 24 hours); a newer
  latest version always resets it.
- Build metadata that is not a number (`+exp.sha.5114f85`) is kept but
  ignored when comparing.
- Arabic and French default texts are hand-written; review them with a
  native speaker for your audience.

## License

MIT, see [LICENSE](LICENSE).

Made by [Abdeldjalil Chougui](https://abdeldjalilchougui.biz/).
