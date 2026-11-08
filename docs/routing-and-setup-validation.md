# Per-app routing and native browser setup validation

Date: 2026-11-08. Candidate: WinMix 0.8.0 (11), macOS 27.2 / 26B123, Apple Silicon.

## Implemented behavior

Ceramic and Retro expose the same per-app output picker. Saved device UIDs survive
disconnects; the mixer falls back to the current system output and automatically returns.
Explicit destinations keep a tap at unity gain, while default/unmuted/unity returns to direct
output. The picker distinguishes a selected device, pending connection and failed move.

A replacement route must deliver IO before the previous route is released or the effective
UID/diagnostics change. A five-second readiness timeout retains the working route. New helper
processes update both active and pending routes; a failed update/replacement keeps the active
tap and retries on health events. Canceling or superseding a destination invalidates delayed
handoff work.

Chrome Setup installs the existing one-origin native host manifest directly in Swift. It
prefills a valid saved ID, requires explicit replacement for another connection, handles
literal paths and rejects unrelated registrations and leaf/dangling symlinks. Registration
success is separate from actual browser connection. Python remains a development fallback.

## Evidence

- Initial Swift build failed because the existing module cache referred to the old absolute
  `mac-volume` directory. `swift package clean` fixed the environment; no source workaround.
- `swift test`: 55 tests passed after routing fixes, including 15 model routing tests, ten
  deterministic readiness-handoff tests and nine disposable native-installer tests.
- Node extension tests: 23 passed. Python installer compatibility tests: two passed.
- Release candidate built at `build/validation-0.8.0/WinMix-routing.app`; strict deep signing
  verification passed.
- Selected and disconnected output states rendered in both Ceramic and Retro, alongside
  existing browser/control states; images under `build/validation-0.8.0/previews/`.
- Isolated real extension/native host integration with mock app passed: discovery, independent
  gains, playback/transport/shuffle, navigation, reconnect and shutdown.
- Native Core Audio integration results and final UI setup checks are recorded with the
  combined release in [menu-bar-validation.md](menu-bar-validation.md).

Logs: `build/validation-0.8.0/swift-routing-setup.log`, `build-routing.log`,
`routing-renders.log`, `browser-integration.log`, and `native-integration.log`.

## Independent review

The initial routing and setup reviews used separate agent threads. Setup had no blocking
finding. Routing identified stale errors after reverting/exiting and a readiness-timeout gap.
A setup reviewer cross-fixed model-state failures; the routing reviewer verified them and
implemented a tested readiness boundary. A fresh integrated reviewer identified the helper
update failure path; its regression test failed before the fix and passed afterward. That
reviewer also verified the final membership/cancellation fix and reported no remaining blocker.

## Preservation and limits

Previous local app preserved at `build/validation-0.8.0/MacVolume-before-0.8.0.app`, with
preferences and host registration snapshots in the same validation directory. Tests use
disposable registration directories, preview state, private Chrome profiles and explicit
virtual outputs. No change to system default output or personal browser registration is
part of the test workflow.

Real physical unplug/replug, Bluetooth call-mode changes and physical sleep/wake require
hardware checks; injected tests cover resolution/failure paths. Minimum macOS 14.4 is the
deployment target; this session runs macOS 27.2. A `coreaudiod` restart still requires relaunch.
Atomic manifest writes prevent partial JSON; simultaneous external installer processes are
not serialized by a cross-process lock.
