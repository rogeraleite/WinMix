# Chrome Tab Volume Implementation Plan

> **For agentic workers:** Execute this plan task-by-task in the current session. The user requested implementation; no additional execution-choice gate is needed.

**Goal:** Control simultaneous Chrome tabs independently from MacVolume.

**Architecture:** A Manifest V3 extension owns one Web Audio gain path per captured tab in an offscreen document. A bundled Native Messaging host relays versioned JSON over a private Unix socket to the app. The app shows confirmed state and disables unenabled/disconnected controls.

**Tech Stack:** Swift 6 package in Swift 5 mode, SwiftUI, Darwin sockets, Chrome 116+ APIs, plain JavaScript, Node's built-in test runner.

**Spec:** `docs/chrome-tab-volume.md`

## Global Constraints

- macOS 14.4+; Google Chrome normal browsing, one connected profile.
- Local audio and metadata; no audio crosses the bridge.
- Individual tab gain 0–100%; native Chrome control remains master.
- Per-tab settings last only for the browser session and active capture.
- Existing Core Audio probes must not open the Chrome server or change user settings.
- User explicitly enables each capture; never claim automatic capture of new tabs.

### Task 1: Versioned transport and native host

Files: `Package.swift`, `Sources/ChromeSupport/{Protocol,LocalSocket}.swift`, `Sources/ChromeBridge/main.swift`, `Tests/ChromeSupportTests/TransportTests.swift`.

Interfaces: `BridgeMessage` carries `version`, `type`, `session`, `requestID`, `tabID`, `volume`, `muted`, `tabs`, `error`; `ChromeTab` carries confirmed playback/capture/gain state. `LocalSocket` provides connect/listen and bounded Native Messaging frames.

- [x] Add Codable messages and validation of versions, IDs, finite gains, duplicate IDs and message sizes.
- [x] Add 0700 per-user socket directory, peer UID checks, single app ownership and full read/write framing.
- [x] Relay Chrome stdin frames to the app and app frames to stdout. Reject malformed frames and invalid Chrome origin arguments.
- [x] Test partial/oversized frames, EOF, invalid state and a socket round trip with `swift test`.

### Task 2: Extension audio and lifecycle

Files: `Extensions/Chrome/{manifest.json,background.js,offscreen.html,offscreen.js,audio-engine.js,protocol.js,popup.html,popup.js,popup.css}`, `Tests/ChromeExtension/*.test.mjs`.

Interfaces: runtime messages target `worker` or `offscreen`; `enable`, `disable`, `set`, `state`, `stopAll` return confirmed state. Native messages use Task 1's schema; `requestID` is echoed on success/failure.

- [x] Implement an injectable audio engine with a separate MediaStream → source → gain → destination chain for each tab; smooth gain changes and stop tracks/close context on removal or failure.
- [x] Capture the active tab only after a popup button click. Use `getMediaStreamId({targetTabId})`; create the offscreen document with `USER_MEDIA` reason.
- [x] Discover audible tabs and merge with controlled tabs; use a session UUID, domain/title/ID, and confirmed gain. Bound and validate native input.
- [x] Reconnect Native Messaging with an alarm and popup retry. Keep capture gains while only the bridge is disconnected; stop captures on explicit app shutdown. Handle closed tabs and ended streams.
- [x] Test two independent gains, mute, cleanup, failed capture and protocol rejection with `node --test Tests/ChromeExtension/*.test.mjs`.

### Task 3: Native controls and setup

Files: `Sources/MacVolume/{ChromeTabModel,ChromeTabView}.swift`, `MixerView.swift`, `MacVolumeApp.swift`, `SettingsView.swift`.

Interfaces: `ChromeTabModel` publishes connection state, `[ChromeTab]`, pending commands and errors; `setVolume(_:for:)`, `toggleMute(_:)`, `disconnect()` send validated commands with timeout. Start this model only in normal app mode.

- [x] Add a background socket server; marshal messages to the main actor and serialize writes. Invalidate stale sessions/commands on disconnect.
- [x] Render Chrome child rows with title/domain/tab ID, volume and mute; disable unenabled, pending and disconnected controls. Show master-volume explanation and setup location.
- [x] Expose extension folder and guide from Settings. Send shutdown before app termination.
- [x] Build with `swift build`; render the existing mixer preview to check regressions. Add model tests for confirmed state and timeouts where practical.

### Task 4: Packaging, installation and acceptance

Files: `scripts/build-app.sh`, `scripts/{install,uninstall}-chrome-bridge.py`, README and spec.

Interfaces: `python3 scripts/install-chrome-bridge.py EXTENSION_ID --app /absolute/MacVolume.app` writes only the current user's host manifest, naming `com.rogerleite.macvolume.chrome`; removal deletes only that manifest.

- [x] Bundle bridge, extension and guide. Register an absolute executable path and exact extension origin; validate arguments and reject unexpected existing registrations.
- [x] Test installer in a temporary user-data directory and run the real bundled host against a mock app socket.
- [x] Replace planned instructions with executable setup/removal steps and state actual validation limits.
- [x] Run `swift test`, Node tests, release packaging, syntax checks and `git diff --check`. Browser capture, two-tab listening, master interaction, navigation and output changes require real Chrome verification; record outcomes without claiming unperformed checks.

## Closure

Implemented in the current session. The native model additionally has an integration test in
`Tests/MacVolumeTests/ChromeTabModelTests.swift`; the real browser/native-host test is in
`scripts/test-chrome-integration.mjs`. A pre-gain analyser supplies captured activity because
Chrome's audible flag can turn off during capture. Measured audio gain matches the requested
values, including after reconnect. See `docs/chrome-tab-validation.md` for evidence and the
remaining manual checks, particularly the interaction with the native master tap.
