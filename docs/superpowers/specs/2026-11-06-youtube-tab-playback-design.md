# Independent YouTube tab volume and playback

Date: 2026-11-06

## Approved direction

The user wants independent volume, mute, and play/pause controls in MacVolume for
YouTube and YouTube Music only. The user approved extending the existing page
controller rather than clicking site-specific player buttons.

The alternative depends on YouTube's changing DOM and selectors. Reusing native
media methods fits the existing controller and keeps playback and volume state
on the same local bridge.

## Scope and visible behavior

- Keep exactly the existing four HTTPS origins: `youtube.com`, `www.youtube.com`,
  `m.youtube.com`, and `music.youtube.com`. Do not expand host permissions.
- Keep one MacVolume row per discovered media tab, with independent volume from
  0–100%, tab mute, and one play/pause button beside the existing controls.
- Retain paused tabs so they can be resumed without visiting the page or popup.
  Discover tabs when compatible media starts playing or Chrome reports them
  audible; include muted playback by using playback state separately.
- Keep Chrome's app volume as the master. Tab gain still multiplies the player's
  own volume; playback commands never change gain or mute.
- Decide play/pause from actual playback state, independently of audibility.
  A muted or zero-volume player can still be playing and must offer Pause.
- Disable unavailable playback controls and explain the limitation. Keep volume
  or mute usable when their capabilities remain available.
- Show pending commands and update confirmed state after the player responds.
  Reflect changes made directly on the website as well.

No audio capture, additional sites, tab boost above 100%, persistent tab IDs,
arbitrary Web Audio control, or new external services are included.

## Playback targeting

Pause stops the currently playing compatible audio/video players in the selected
tab's authorized frames. Each document remembers which players MacVolume paused.
Play resumes that remembered set, excluding detached, ended, or source-less
players. This avoids starting every idle or preloaded player in a document.

If there is no resumable remembered set, Play targets the most recently active
eligible player in the main document. If no such player exists, report playback
unavailable rather than start an arbitrary media element. This fallback supports
resuming a player the user paused on the website. A subsequent Pause replaces the
remembered set only if players are currently playing. Pausing an already paused
tab preserves that set so a repeated command does not lose its resume targets.

Document navigation discards element references. Newly discovered players inherit
the existing tab gain but never inherit an instruction to start playback.
Repeated Play or Pause commands are safe and do not toggle playback accidentally.

## Components and data flow

1. `media-controller.js` owns media references, playback targeting, separate
   playing/audible counts, and playback eligibility. Its dependencies are injected
   native media accessors/methods so behavior can be tested without a browser.
2. `page-controller.js` observes media events and invokes native `play()` and
   `pause()` methods. It waits for Play promises and reports actual state or a
   bounded error. It preserves the existing site-volume interception.
3. `content-bridge.js` validates and forwards explicit playback commands and
   capability/state updates through the existing per-document runtime ports.
   Page messages cannot invoke privileged browser or native operations directly.
4. `background.js` aggregates the selected tab's authorized frame state and
   dispatches explicit Play or Pause commands only to eligible targets. Volume,
   mute, and playback use the existing command queue and session/request IDs.
5. The JavaScript and Swift protocol adds optional playback capabilities and
   confirmed playing state, plus an explicit playback command. Existing volume
   commands and state remain compatible. Missing playback fields mean playback
   unavailable; an older extension must not acquire an apparently active button.
6. `ChromeTabModel` sends playback commands and tracks acknowledgements/timeouts.
   `ChromeTabView` adds the accessible play/pause button in the current visual
   style, using confirmed playback state and per-capability availability.

Playback commands do not include a volume or mute write. The native bridge remains
a local transport and validates the new protocol fields before forwarding them.

## Failure and lifecycle behavior

- Chrome may reject Play because of autoplay restrictions or unavailable media.
  Show the reason and, where applicable, ask the user to start playback on the
  website once. Do not report successful playback until confirmed.
- On partial frame failure, publish observed state and a visible error; do not
  claim that every target completed the command.
- Keep bounded command timeouts. Disconnection or navigation clears pending
  commands and disables controls until the relevant capability is available.
- Closing a tab removes its settings and playback references. Reconnection
  refreshes state and does not replay old Play/Pause commands.
- App shutdown retains the existing restoration of volume and owned mute. It
  does not automatically restart paused media or pause playing media.
- Updating the unpacked extension may require one reload in
  `chrome://extensions`; there is no recurring per-tab activation step.

## Validation and delivery

- Unit tests cover independent controllers, pause/resume target selection,
  muted and zero-volume playback, ignored stale players, repeated commands,
  navigation cleanup, blocked Play, and unchanged volume/mute during playback.
- Protocol and model tests cover new command validation, optional legacy state,
  confirmed playback state, timeout, disconnect, and unavailable capabilities.
- Isolated Chrome integration uses controlled pages on the approved hosts and
  the existing local native bridge. Verify two tabs at different volumes;
  pause/resume one without altering the other's playback or gain; direct website
  changes; paused-row retention; background tabs; and out-of-scope exclusion.
- Run the existing Swift, Node, and Python suites, build the app, and inspect a
  rendered preview of the added controls. Run browser integration when its
  existing dependencies are available.
- Update the setup/behavior guide and report reproducible fixture results
  separately from any checks on the real YouTube and YouTube Music services.

## Acceptance

Two supported tabs appear automatically once media plays. Each can independently
increase/decrease its gain, mute/unmute, pause, and resume. Pausing one preserves
its row and both tabs' gains. The other tab continues unchanged. The interface
reports confirmed state and clearly explains unsupported or blocked operations.
