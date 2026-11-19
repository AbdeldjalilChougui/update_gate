## 0.2.0

- Add `ResponseSignalSource`: forces an update from your own HTTP
  responses (a `426 Upgrade Required` status or a minimum-version header),
  optionally over a base source. No new dependencies.
- `UpdateGate` checks again whenever a `Listenable` source notifies, so a
  forced update can appear mid-session. Other sources behave as before.
- Add `UpdatePolicy.forceUpdate` (`force_update` in JSON) and
  `UpdatePolicy.copyWith`.
- `onDecision` is called for every check, not only the first.

## 0.1.0

- Initial release.
