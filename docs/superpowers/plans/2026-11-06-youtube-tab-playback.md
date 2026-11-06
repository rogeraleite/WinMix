# YouTube Tab Playback Implementation Plan

> **For agentic workers:** Execute sequentially in this session. The user approved
> the design and written spec. No additional execution-choice gate is needed.

**Goal:** Independent volume, mute, and confirmed play/pause for YouTube and
YouTube Music tabs in the existing MacVolume mixer.

**Architecture:** Extend the page controller and local protocol with explicit
playback commands and capability state. Track resume targets per document, keep
audibility separate from playback, and render confirmed controls in SwiftUI.

**Tech Stack:** SwiftUI, Swift Package Manager, Manifest V3, JavaScript, Node tests,
Playwright with isolated Chrome for Testing, Python installer tests.

**Spec:** `docs/superpowers/specs/2026-11-06-youtube-tab-playback-design.md`

## Global Constraints

- Keep exactly the existing four HTTPS origins: `youtube.com`, `www.youtube.com`,
  `m.youtube.com`, and `music.youtube.com`. Do not expand host permissions.
- Tab volume is 0–100%; Chrome app volume remains the master.
- Playback commands never change volume or mute, restart media on reconnect, or
  start an arbitrary idle/preloaded player.
- Preserve existing protocol-1 volume messages and decode absent playback fields
  as unavailable. Use bounded acknowledgements and visible errors.
- App shutdown restores volume/mute as before, without changing playback.

### Task 1: Media playback controller

**Files:** `Extensions/Chrome/media-controller.js`, `page-controller.js`,
`Tests/ChromeExtension/media-controller.test.mjs`.

**Interfaces:** Inject `isPlaying`, `isAudible`, `canPlay`, `play`, and `pause`.
Expose `notePlaying(element)`, `setPlayback(action, allowFallback = false)`,
and state fields `playingCount`, `audibleCount`, `canPlay`, `canPause`,
`resumeCount`, and `playbackIssue`. Retain the existing gain/mediaCount fields.

- [ ] Write failing tests proving independent tab playback with unchanged gains,
  repeat Pause preserving resume targets, muted playback, most-recently-active
  fallback, stale/ended/source-less exclusions, and rejected Play.

```js
await one.setPlayback("pause");
assert.equal(a.paused, true);
assert.equal(b.paused, false);
assert.equal(a.actual, 0.24);
await one.setPlayback("pause");
await one.setPlayback("play");
assert.equal(a.paused, false);
```

- [ ] Run `node --test Tests/ChromeExtension/media-controller.test.mjs` and
  confirm failure before implementation.
- [ ] Implement weak resume targets and a monotonic last-played sequence. Pause
  all playing eligible targets; Play resumes the remembered set, otherwise the
  most recently active eligible main-document target only. Await Play promises
  with a 1.5-second bound and expose errors together with observed state.
- [ ] Wire native play/pause and media events in `page-controller.js`; forward
  explicit `playback` messages with `action` and `allowFallback`, returning
  request-tagged state even on failure.
- [ ] Rerun controller tests and commit this self-contained unit.

### Task 2: Validated local transport and tab aggregation

**Files:** `Extensions/Chrome/{protocol,content-bridge,background}.js`,
`Sources/ChromeSupport/Protocol.swift`, `Tests/ChromeExtension/protocol.test.mjs`,
`Tests/ChromeSupportTests/TransportTests.swift`.

**Interfaces:** Native command is `{version:1,type:"playback",session,requestID,
tabID,action:"play"|"pause"}` without volume/muted. Tab state adds optional
`playing`, `canPlay`, `canPause`, and `playbackIssue` (maximum 512 characters).

- [ ] Write and run failing JS/Swift validation tests for Play/Pause, invalid
  actions/mixed commands, bounds, and absent legacy playback capabilities.

```js
assert.equal(validCommand({ version: 1, type: "playback", session: "s",
  requestID: "r", tabID: 1, action: "pause" }), true);
```

- [ ] Forward/validate frame counts, booleans, bounded playback errors and
  explicit commands in the content bridge. Preserve unsolicited state updates.
- [ ] Aggregate actual playing independently of audible; keep paused rows. For
  Play, prefer frames with resume targets; use the main frame fallback only if
  none exist. For Pause, target playing frames. Repeated commands are safe no-ops.
- [ ] Await all selected frames before publishing acknowledgement. On partial
  failure publish observed state first, then a request-tagged error. Never apply
  volume/mute writes or rollback playback after failure.
- [ ] Extend Swift/JS protocol validation and optional metadata while preserving
  old volume-only state. Run Node tests and `swift test --filter TransportTests`.
- [ ] Commit the transport deliverable.

### Task 3: Native controls and diagnostic coverage

**Files:** `Sources/MacVolume/{ChromeTabModel,ChromeTabView,ChromeIntegrationProbe,
Probe}.swift`, `Tests/MacVolumeTests/ChromeTabModelTests.swift`.

**Interfaces:** `setPlayback(_ action: String, for tab: ChromeTab)` sends a
capability-checked explicit command through the existing pending request path.

- [ ] Add a failing socket-backed model test: Pause transmits no volume/mute,
  does not optimistically change state, and only matching acknowledgements clear
  pending. Legacy/missing capability and disconnected controls send nothing.
- [ ] Share request preparation/timeout handling across volume and playback.
  Render a play/pause button with a tab-specific accessibility label, capability
  checks, pending state, help text and confirmed playing state. Display playback
  issues without disabling usable volume/mute.
- [ ] Extend the native diagnostic `tab` action with `playback: "play"|"pause"`.
  Add playing, paused and unavailable playback fields to preview fixtures.
- [ ] Run `swift test`, build a separate validation app, render preview PNGs and
  visually inspect the connected/disconnected tab rows. Commit native controls.

### Task 4: Integration, packaging, and delivery

**Files:** `scripts/test-chrome-integration.mjs`, `Extensions/Chrome/manifest.json`,
`Resources/Info.plist`, `README.md`, `docs/chrome-{tab-volume,tab-validation,
manual-validation}.md`.

- [ ] Extend isolated integration with explicit playback via mock and native
  paths; assert selected player paused/resumed, other player unchanged, gains
  unchanged, direct website pause reflected, mute/zero-volume still playing,
  multiple active media resume but idle preload does not start, blocked Play
  returns an error, and navigation clears stale resume references.
- [ ] Run `node --test Tests/ChromeExtension/*.test.mjs`, `swift test`,
  `python3 -m unittest discover -s Tests -p 'test_*.py'`, syntax/diff checks.
- [ ] Bump app/extension to 0.4.0 (bundle build 5), update guides and record
  evidence separately from real-service validation. Build/sign validation app
  using `./scripts/build-app.sh build/validation/MacVolume.app`.
- [ ] Locate existing Playwright and Chrome for Testing; run isolated browser
  integration, then native integration with an explicit diagnostic output UID.
- [ ] Stage and replace `build/MacVolume.app` only after checks pass, quitting
  the running app normally before replacement, and relaunch. Preserve extension
  folder/ID and native-host registration. Tell the user about any required
  one-time extension reload; do not claim live-site checks that were not run.
- [ ] Record final checks and commit implementation/documentation.

## Plan self-review

Spec covered: targeting/lifecycle in Task 1; routing/partial failure/compatibility
in Task 2; confirmed UI/capability behavior in Task 3; integration and delivery in
Task 4. Commands, state field names, and target eligibility agree across tasks.
