# Ceramic 0.6.0 validation — 2026-11-06

## Automated checks

- `swift test`: 19 tests, zero failures. Includes existing app ownership, Chrome state/capability/queue/timeout tests and two browser setup tests.
- Setup command tests reject malformed extension IDs and execute a harmless shell printf to confirm paths containing spaces, apostrophes, dollar expressions and backticks remain literal arguments.
- `./scripts/build-app.sh build/ceramic-validation/MacVolume.app`: production build and ad-hoc signing passed.
- `codesign --verify --deep --strict`: passed for validation and installed bundles.
- Bundle inspection confirmed app version 0.6.0, extension version 0.5.0, the installation guide, both installer scripts and Chrome icon dimensions 16/32/48/128.

## Visual inspection

Rendered and inspected both Ceramic and Retro with normal gain, Boost, empty state, connected Chrome tabs and disconnected Chrome tabs, plus the browser setup sheet: 11 PNGs in `build/ceramic-validation/previews/`.

The Ceramic sliders use cobalt tracks, ceramic handles, arrow-key adjustment, focus indication and native slider accessibility representations. An initial redundant native slider label was removed during visual review. App names, output labels, percentage values and browser explanations remain readable. Long browser titles truncate with tooltips; the list and installation sheet scroll.

## Native UI verification

- Switched Ceramic → Retro → Ceramic using the header palette menu. The style choice persisted across app launches.
- Opened the question-mark help from Retro and Ceramic, inspected all four installation steps, and closed the sheet successfully.
- Entered a valid sample extension ID: the command used the running bundle's actual installer/app paths and the copy button became available. Entered an invalid ID: validation guidance appeared and copying was disabled. The sample command was not executed.
- Installed the verified bundle at `build/MacVolume.app` and preserved the former version at `build/MacVolume.backup-0.5.0-before-ceramic.app`.
- Reopened the installed app, confirmed automatic reconnection to the existing Chrome extension, and observed both playing and paused browser tabs with their capability-appropriate controls. Left the app open with Ceramic selected.

Live gain, mute and playback actions were not exercised during this UI validation. Their existing model tests passed; no audio/browser model implementation or host registration was changed.
