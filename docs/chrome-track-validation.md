# Previous, next and shuffle — 0.7.0

Validated on 2026-11-06. App and extension 0.7.0. Both appearances share capability-gated controls and confirmed state. The app's original LED-case icon is retained.

## Automated evidence

- Swift: 21 tests passed. New cases cover strict track actions, rejection of volume/mute writes on transport commands, required known shuffle state, capability gating, pending requests and acknowledged shuffle updates.
- JavaScript: 23 tests passed. Added coverage for next/previous confirmation, previous restarting a track, explicit shuffle idempotence, semantic and shared-store shuffle state, hidden/disabled/unsupported/frame isolation, unreadable shuffle state and failure without duplicate clicks.
- Python installer: 2 tests passed.
- Real-extension integration with a disposable Chrome for Testing profile and native bridge passed. The application side was simulated; no user's browser profile or Core Audio route was used by this test. Fixtures cover legacy and Wiz-style player containers, next/previous, repeated shuffle-on producing one click, confirmed shuffle-off, unchanged 30%/70% gains and another tab's independent playback. Existing navigation, reload, unsupported-source, pause/resume and shutdown checks also passed.
- Release build and strict bundle signature verification passed. App/extension versions match; transport-controller.js is included and extension permissions are unchanged.

Logs: build/transport-validation/swift-tests.log, node-tests.log and integration.log. Rendered connected tabs were inspected in Ceramic and Retro under build/transport-validation/previews/.

## Local activation and real player

Installed the verified app at build/MacVolume.app, preserving 0.6.1 at build/MacVolume.backup-0.6.1-before-track-controls.app. Retained the user's Retro appearance, volumes and Boost preference.

Reloaded the existing MacVolume Tabs extension from its original Extensions/Chrome folder, preserving ID bfoeboblehgalbghdlgnccefiekbmcoa. Chrome showed version 0.7.0 and Reloaded. Reloaded the existing YouTube Music window so its older page controller received the new transport module.

The music page required starting a track after reload. Started a track briefly and verified all three controls in the native MacVolume UI. Next changed the real track title. Previous responded according to the player's restart/previous behavior. Shuffle was confirmed On, then confirmed Off. Verified the source player showed Tocar (paused) at the end; the app displayed the confirmed shuffle-off state. No volume or mute change was sent during this verification.

## Boundaries

Transport uses site player buttons rather than a universal media API. YouTube Music exposes all three when available; YouTube may expose previous/next only. Other sites retain volume/mute/playback. Shuffle is unavailable when the page cannot report its state, and unavailable controls cannot be invoked. Previous can restart the current track. Old pages may need one reload after an extension update.

The first new JS test run exposed a VM fixture export issue; the fixture now imports the classic controller just like the existing media tests. A separate compatibility test caught an overly broad global reload notice; the notice is now confined to legacy music rows, preserving the existing playback compatibility contract. Existing assertions were retained.
