# WinMix 0.8.0 menu-bar and combined-release evidence

Date: 2026-11-08. Version 0.8.0, build 11. Platform: Apple Silicon, macOS 27.2 (26B123).
Deployment target: macOS 14.4. Implementation source checkpoint: `cfeb7b8`.

## Delivery and availability

All three requested features are implemented: per-app output routing, native Chrome setup,
and the menu-bar mini mixer. The combined, ad-hoc signed local candidate is
`build/WinMix.app`. It has not been published, pushed, installed in `/Applications`, or
substituted for the owner's running MacVolume instance. Source and validation documents are
committed separately. Remaining manual checks below are not marked passed.

Routing/setup implementation checkpoint: `e339733`. Navigation: `6216037`. Native panel:
`63bc24f`. Scene integration and isolated UI diagnostics: `cfeb7b8`.

## Automated and integration evidence

- Full Swift suite: **57 tests passed**, including 15 routing tests, ten route-handoff tests,
  nine native-installer filesystem tests, two one-shot navigation tests and existing browser
  model/protocol/ownership tests. Log: `build/validation-0.8.0/swift-final.log`.
- Extension unit tests: **23 passed**. Python installer compatibility: **two passed**.
  These source files are unchanged by menu-bar work.
- Production build and `codesign --verify --deep --strict build/WinMix.app` passed. Build
  log: `build/validation-0.8.0/build-final.log`.
- Real extension/bridge in a disposable Chrome for Testing profile passed the HTTP/HTTPS,
  playback, gain, mute, previous/next/shuffle, reconnect, navigation and shutdown integration.
  No personal browser profile was used. Mock-app log: `browser-integration.log`.
- Native integration passed with explicit virtual destinations `BGMDevice` and
  `MSLoopbackDriverDevice_UID`. Measured output/input ratio was 0.500 at 50% and 1.000 at
  unity on each explicit app route. Explicit unity retained its tap; selecting default at
  unity released it; restoring 50% recreated a route on the private default. Log:
  `build/validation-0.8.0/native-final.log`.
- The test harness now waits for a successfully created tap before requesting meter samples;
  a transient tap-creation retry after releasing a route is not treated as an immediate
  missing-meter failure. Timeouts still fail with full model state.
- 31 PNGs cover both main-window skins plus mini-panel light/dark states: normal/muted,
  Boost, empty, denied permission, disconnected destination, error, and many long names.
  Outputs: `build/validation-0.8.0/previews/final-*.png`; log: `final-renders.log`.

## Native UI evidence

The UI test copy at `build/validation-0.8.0/WinMix-UI.app` uses bundle ID
`com.rogerleite.WinMix.Validation` and the separate `--preview-ui` entry point. Its models
observe no processes, create no audio taps/sockets, and write no personal audio/appearance
settings. Setup writes only to `build/validation-0.8.0/ui-hosts`. Login changes are disabled.

The following were observed through native accessibility/UI interaction:

| Behavior | Result |
|---|---|
| Connect browser with a valid test ID | Button enabled and native manifest saved without Terminal |
| Saved vs live connection | `Browser registration saved` while `Chrome is not connected yet` remained visible |
| Replace an existing ID | Connect disabled until `Replace this saved registration` was selected; replacement succeeded |
| Reopen setup | Saved test ID prefilled correctly |
| Compact-panel volume/mute | Chrome changed to 65% and muted; main window showed the same values |
| Compact-panel output picker | USB Headphones selection appeared in the main Chrome output selector |
| Boost off | Range changed to 0–100% and the 160% fixture clamped to 100% in both surfaces |
| Settings shortcut | Opened the existing Settings scene; test login toggle stayed disabled |
| Chrome Setup shortcut | Revealed the main window and opened the existing setup sheet |
| Close and reopen mixer via Open Mixer | State preserved; consumed setup request did not reopen the sheet |
| Quit WinMix | Diagnostic process exited; owner's original MacVolume process stayed running |

The compact-panel interactions above used **Preview → Open Mini Mixer Preview**, a regular
diagnostic window hosting the exact `MenuBarSceneContent` and shared models. This is an
explicit fallback because the computer-use tool did not expose macOS status-item controls.
It does not establish real popover tracking/dismissal.

## Independent review

Separate routing and setup review threads inspected the first two items. A cross-fix and a
fresh integrated reviewer closed working-route retention, helper membership, canceled
handoffs and stale-error defects. A fresh menu reviewer inspected model ownership,
navigation, permissions and preview isolation, and rechecked the final separate preview
entry point. A fresh finalizer independently reran 36 focused routing/handoff/navigation/
installer tests with zero failures (`build/validation-0.8.0/finalizer-tests.log`), checked
metadata and reviewed the evidence. No blocking source finding remained. Reviews did not
substitute for UI tests.

Packaged executable SHA-256:
`460be335dd0323df9741eb188ffcc17e6114b47edb0dfc86f72bee941d5a0e6a`.

## Preservation

- Previous local app backup: `build/validation-0.8.0/MacVolume-before-0.8.0.app`.
- Preferences snapshots: `preferences-before.plist` and `preferences-after.plist` in that
  directory. `volumeSettings`, `boostEnabled` and `mixerAppearance` compare equal.
- Personal Chrome host manifest compares byte-for-byte equal to `host-before.json`.
- System default output remained `BuiltInSpeakerDevice`. Tests selected only explicit
  virtual outputs on the disposable test browser, never on the owner's playing apps.
- Personal Chrome extension ID, profile and host path were not replaced. If the app's path
  changed since its previous registration, the owner can review and replace the registration
  through Chrome Setup when switching to the new app.

## Manual checks still outstanding

- Clicking the actual macOS menu-bar icon, native popover Escape/outside-click dismissal,
  dragging while the popover is open, and nested picker tracking inside that popover.
- Literal Dock-click reopening, minimized-window behavior from the status item, and
  SettingsLink activation when another application is frontmost.
- VoiceOver navigation, physical device unplug/replug, real sleep/wake, Bluetooth call mode,
  and execution on the minimum supported macOS 14.4.

The candidate contains the implementation and passed the recorded checks; these outstanding
checks prevent claiming complete native/hardware validation. A `coreaudiod` restart still
requires relaunch, and installer writes do not serialize unrelated concurrent installer
processes. Full routing/setup details: [routing-and-setup-validation.md](routing-and-setup-validation.md).
