# Chrome Tab Volume Completion Implementation Plan

> **For agentic workers:** Execute sequentially in this session; the user authorized planning and implementation. Preserve all pre-existing changes from the initial implementation.

**Goal:** Close the native-audio integration gap, cover interrupted captures, and complete installation where browser policy permits.

**Architecture:** Preserve the approved extension/native bridge design. Isolate diagnostic sockets from the running app, drive the real ChromeTabModel and MixerModel through a headless probe, and measure the existing tap before and after its gain. Extend capture lifecycle reporting so interruptions are visible and recoverable without discarding per-tab gains.

**Tech Stack:** Swift/SwiftUI/Core Audio; Native Messaging; plain JavaScript and Node tests; Python installer.

**Spec:** `docs/chrome-tab-volume.md`; open checks in `docs/chrome-tab-validation.md`.

## Constraints and boundaries

- macOS 14.4+, Chrome 116+, one connected normal profile; no Web Store publication.
- Diagnostic probes never load/save user volumes, change the system default output, or tap personal Chrome.
- Native integration targets only `com.google.chrome.for.testing` and requires explicit output UIDs.
- Retain the current socket as default; an opt-in `MACVOLUME_CHROME_SOCKET` environment variable isolates test app and host.
- No automated real sleep, call joining, protected-content access, or claims about unavailable OS/browser versions.
- The browser tool rejected `chrome://extensions` and forbids alternate routes. The user must load the unpacked extension and supply its ID; then the existing installer can register the bridge. This is an installation dependency, not an implementation gate.

## Task 1 — Native integration diagnostics

Files: `Sources/ChromeSupport/LocalSocket.swift`, `Sources/MacVolume/{Probe,ChromeIntegrationProbe}.swift`, `scripts/test-chrome-integration.mjs`, `scripts/build-app.sh`.

Interfaces: `MACVOLUME_CHROME_SOCKET` chooses a private diagnostic endpoint. `MacVolume --probe --chrome-integration --output UID` reads one JSON command per stdin line and returns one JSON response with the same `requestID`. Actions: `status`, `tab`, `master`, `meters`, `route`, `stall`, `sleep`, `wake`, `stop`. Probe status includes confirmed tabs, pending count, mixer error and actual tap meters. `--devices` lists UIDs without changing devices.

- [x] Test the baseline; add a private endpoint override and verify separate listeners cannot collide.
- [x] Implement `ChromeIntegrationProbe.run(outputUID:)`: create `MixerModel(defaults:nil,pinnedOutputUID:)` and `ChromeTabModel`; restrict master commands to the test browser group.
- [x] Implement asynchronous short-window meter responses with nonzero input and `outputPeak/inputPeak` checks; never block the main actor waiting for IO.
- [x] Extend the existing disposable browser test with native mode and temporary host shim. Commands drive the real native models; first use a virtual output, then move to a second explicit output, simulate sleep/wake and IO stall recovery.
- [x] Allow the build script to emit `build/validation/MacVolume.app` while the user's current app remains untouched.

## Task 2 — Capture interruption and failure coverage

Files: `Extensions/Chrome/{audio-engine,offscreen,protocol,popup}.js`, `Sources/ChromeSupport/Protocol.swift`, `Sources/MacVolume/ChromeTabView.swift`, tests.

Interfaces: optional per-tab `issue` carries an actionable interruption message while `controlled`, `volume` and `muted` retain the last applied values. The audio engine retries resume once at a time and never resets gain to recover a context.

- [x] Reproduce resume failure and unexpected context closure in injectable audio-engine tests before changing behavior.
- [x] On suspended/interrupted context, mark activity false and retry resume; on rejected resume, retain capture/gain and publish an issue. Unexpected closure releases capture resources.
- [x] Display per-tab issue in popup and app; do not silently claim playback is working.
- [x] Add tests for failure cleanup after stream acquisition, already-ended tracks, interrupted resume, retry, permanent closure and independent unaffected tabs.

## Task 3 — Evidence, installation and build

Files: README, `docs/chrome-tab-{volume,validation}.md`, version manifests if behavior changes require it.

- [x] Run Swift, Node and Python tests, release packaging and signature/syntax checks.
- [x] Record measured native master gain, output routing and simulated recovery outcomes, including inconclusive measurements.
- [x] Register the user's exact extension ID once provided; verify the registration points to the stable app path.
- [x] Keep actual sleep/wake, AirPods call mode, protected content and unsupported environment checks explicitly pending if unavailable. Give a reproducible manual checklist with expected outcomes rather than marking them passed.

## Review

The tasks cover existing product requirements; no unrelated redesign or release is included. Installation needs only the ID from the user because the tool policy blocks the Chrome settings page. Simulated events remain distinguished from real hardware events.


## Execution evidence — 2026-11-05

- Code and automated validation are complete. The user-supplied ID was registered on 2026-11-05 and the native app visibly confirmed the Chrome connection.
- The native test ran concurrently with the existing app using a separate socket and app bundle.
- A real ownership bug was fixed in `AppGroup.swift` and `ProcessIdentity.swift`: enclosing bundles take precedence over an editor/terminal's responsibility identity. Four focused tests cover bundled helpers, shared services and CLI. The native browser then appeared under its own group without a diagnostic ownership override.
- The real mixer applied 0.500 gain with two independently controlled tabs; routing passed on Teams Audio, Background Music, MacBook speakers and connected AirPods. A route-generation check proved rebuild after simulated wake and stopped IO.
- A real offscreen AudioContext suspension recovered with the original gains. Failure/closed-context tests passed and the optional diagnostic issue is backward compatible with protocol 1.
- Final unit checks: Swift 12, Node 10, Python 2, all passing. Browser/native evidence and manual boundaries are recorded in `docs/chrome-tab-validation.md`.
- App/extension package version: 0.2.1. No release publication or remote changes are included.

The Chrome extension now uses the existing MacVolume logo via generated PNGs at 16/32/48/128 pixels. Reloading its manifest remains a user action on the browser settings page blocked by the tool.
