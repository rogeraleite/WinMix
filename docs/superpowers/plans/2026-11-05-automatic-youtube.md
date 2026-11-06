# Automatic YouTube Controls Implementation Plan

> **For agentic workers:** Execute sequentially in this session. The user approved automatic control restricted to YouTube and YouTube Music. Preserve existing unrelated changes; no additional execution-choice gate is needed.

**Goal:** Audible YouTube/YouTube Music tabs become controllable in MacVolume without opening the popup or enabling individual tabs.

**Architecture:** Replace tabCapture with scoped page controllers for HTML audio/video players. A MAIN-world controller composes the site's base volume with the tab gain; an isolated content script connects it to the service worker over per-document ports. The existing native bridge carries confirmed state and commands. Chrome's tab mute is available even while a player is unavailable.

**Tech Stack:** Manifest V3, classic content scripts, plain JavaScript/Node tests, SwiftUI/Core Audio and the existing local bridge.

**Spec:** `docs/automatic-chrome-tabs-proposal.md`, approved scope: YouTube and YouTube Music only.

## Global constraints

- Allow only HTTPS origins `youtube.com`, `www.youtube.com`, `m.youtube.com`, `music.youtube.com`; no wildcard access to unrelated sites.
- Remove tabCapture/offscreen/activeTab permissions and per-tab enable/release UI.
- Use HTMLMediaElement controls used by these sites. Arbitrary Web Audio graphs are outside this scoped implementation; report unavailable volume instead of a fake working slider.
- Keep site volume separate: `actual volume = site volume × tab volume`; never repeatedly multiply an already scaled value.
- Per-tab settings survive page navigation and worker restarts within the browser session; closing/leaving supported sites clears them. Do not retain tab IDs across browser restarts.
- No audio recording, extra network service, changes to system default output, or browser-setting policy workarounds.
- The browser tool blocks `chrome://extensions`. Updating that manifest in the user's browser requires one manual reload/permission confirmation; new supported tabs then work automatically.

## Task 1 — Page controller

Files: `Extensions/Chrome/media-controller.js`, `page-controller.js`, `content-bridge.js`, `Tests/ChromeExtension/media-controller.test.mjs`.

Interfaces: page bridge messages have `channel`, `bridgeID`, `requestID`, `type` (`init`, `set`, `reset`, `state`), and finite gain 0–1. State reports media count, playing count and applied gain. No page-origin message can invoke native functions or execute arbitrary code.

- [x] Implement an injectable controller around the native volume accessor and play method. Track media weakly, observe new players/open shadow roots and preserve original player volume.
- [x] Prove independent controllers, site volume changes, repeat commands, dynamic players, pause/mute state, reset and cleanup with Node tests.
- [x] Add MAIN-world bootstrap and isolated runtime port bridge with bounded acknowledgements, reconnection and replacement of stale bridge owners.

## Task 2 — Automatic discovery and commands

Files: `Extensions/Chrome/{background,protocol,popup}.js`, `popup.html`, `manifest.json`.

Interfaces: controller ports register by tab/frame/document; the worker distributes one tab gain to all current authorized frames, waits for acknowledgements and publishes protocol-1 state. Optional `canMute` and `controlMode: "page"` augment the native tab schema.

- [x] Limit host/content-script matches to the four approved origins and bootstrap already-open authorized pages on extension startup.
- [x] Restore session settings before applying page commands. Detect playing tabs automatically; retain controlled/paused/muted rows and remove closed/out-of-scope tabs.
- [x] Implement commands, exact mute ownership, native reconnection and normal shutdown restoration. Surface unavailable players; reject stale sessions and out-of-scope tabs.
- [x] Replace popup enable/release controls with automatic-site status; retain reconnect and extension ID.

## Task 3 — Native UI and protocol

Files: `Sources/ChromeSupport/Protocol.swift`, `Sources/MacVolume/{ChromeTabModel,ChromeTabView}.swift`, Swift tests.

- [x] Decode optional capabilities compatibly; allow mute-only commands without allowing unsupported volume changes.
- [x] Replace per-tab activation text with automatic mode/playing/paused/unavailable state. Disable only unsupported volume controls.
- [x] Test mute-only capability, backwards compatibility and confirmed-volume behavior.

## Task 4 — Evidence, packaging and update

Files: `scripts/test-chrome-integration.mjs`, documentation, Info.plist; remove obsolete capture runtime/tests after the automatic replacement passes.

- [x] Run an isolated browser/native integration on fulfilled HTTPS YouTube/Music fixture pages without opening the extension action. Verify scope exclusion, two tabs, native media volume, dynamic players, site volume changes, pause, mute, navigation, bridge reconnect and shutdown restoration.
- [x] Measure real Core Audio output with the native probe; keep fixture results distinct from a live-site check.
- [x] Run Swift/Node/Python tests, build/signature/icon/syntax checks, update docs and package 0.3.0.
- [x] Update the stable native app without overwriting its running binary. Keep the registered extension ID. Ask only for the one browser reload/permission step the tool cannot perform; do not ask to activate tabs.


## Closure — 2026-11-05

- Implemented the approved four-origin scope with no general tabs permission and no capture APIs.
- Removed the old capture runtime and per-tab enable UI. Native mute-only capability is acknowledged and tested.
- Final checks: Swift 13, Node 8, Python 2 passing. Both mock-app and real-native browser integrations passed without an extension action. Extension reload bootstrapped the already-open page automatically.
- Native measurements: HTML player gain 0.300, Core Audio master 0.500; explicit route to speakers retained the master gain. An AirPods UID became unavailable in an earlier run and is not marked passed for this version.
- Rendering verified automatic status, independent controls and honest volume-unavailable/mute-available state.
- Deployment boundary: the stable native app is updated by staged replacement; the browser tool cannot reload the user's extension or confirm its new permissions. This one-time user action remains pending, not a per-tab activation requirement.
- Evidence and known manual checks: `docs/chrome-tab-validation.md`, `docs/chrome-manual-validation.md`.
