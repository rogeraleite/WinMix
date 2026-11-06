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

## 0.6.1 — service icons and original app identity

Owner requested distinct YouTube/YouTube Music icons in either style and restoration of the prior main icon. Added local SwiftUI service marks selected by hostname: YouTube's red rounded play mark, YouTube Music's red circular ring/play mark, and a globe for other hosts. No network icon loading or browser protocol changes are needed.

- `swift test`: 19 tests, zero failures (`build/ceramic-validation/icon-tests.log`).
- Production build and strict signature verification passed for `build/icon-validation/MacVolume.app` and the updated `build/MacVolume.app`.
- Rendered previews include both services; inspected connected-tab rows in Ceramic and Retro for icon distinction and label alignment (`build/icon-validation/previews/`).
- The restored `Resources/AppIcon.icns` and extension icon PNGs match the pre-Ceramic originals from commit `6509bfc`; verified SHA-256 equality for the main icon and 128px extension icon.
- Reopened the installed 0.6.1 app with the existing Retro selection and saved Chrome gain preserved. Retained the prior app in `build/MacVolume.backup-0.6.0-before-site-icons.app`.
- Confirmed the live Chrome connection and distinct accessible YouTube/YouTube Music images beside their corresponding real tabs.
