# Sticker Case 0.9.0 — validation, 2026-11-10

## Delivered behavior

The selected 3C appearance is implemented as **Sticker Case** in the header palette menu. It uses a white cut-out wordmark, colored tape, light paper grain, outlined cream controls, black fader handles, and a pink/turquoise Chrome group with a white die-cut border. Boost has matching outlined switch artwork with native toggle accessibility.

The appearance is the fallback for new installations. Existing Ceramic/Retro choices retain their raw values and are honored; selecting Sticker Case persists under the same `mixerAppearance` key. App and extension icons, audio/browser models, routing, browser registration and native menu-bar appearance are retained.

## Automated verification

- `swift test`: **57 passed**, zero failures, after the final source changes. Log: `build/sticker-case-swift-tests.log`.
- `node --test Tests/ChromeExtension/*.test.mjs`: **23 passed**, zero failures. Log: `build/sticker-case-node-tests.log`.
- `python3 -m unittest discover -s Tests -p 'test_*.py'`: **2 passed**. Log: `build/sticker-case-python-tests.log`.
- `./scripts/build-app.sh build/sticker-case/WinMix.app`: production build and ad-hoc signing passed. Log: `build/sticker-case/release-build.log`.
- `codesign --verify --deep --strict --verbose=2`: passed for the candidate and updated `build/WinMix.app`, including ChromeBridge.
- Bundle version is **0.9.0 (12)**. The bundled main icon SHA-256 matches `Resources/AppIcon.icns`; the extension, native bridge, guides and installer scripts are present.
- `git diff --check`: passed.

## Visual verification

The isolated `--probe --render-preview` mode rendered **42 PNGs** in `build/sticker-case/final-previews/`, covering all three appearances and native light/dark menu panels. Inspected normal, Boost, empty, Chrome connected/disconnected, output fallback, 560-point compact layout, long names/many rows, error banner and browser controls. Appearance overrides and fake models keep rendering independent of saved settings and live audio.

The native preview accepts `--preview-ui --preview-tabs --preview-appearance stickerCase`; appearance changes in this diagnostic mode are held in memory. Inspected the actual macOS window as well as the PNGs. Header now extends into the hidden title-bar region so traffic lights share the paper surface. Menus receive their outline outside the native menu label, and disabled buttons visibly fade.

AppKit's offscreen `cacheDisplay` snapshots show white speaker-wave glyphs inside the clipped Chrome sticker in some fixtures, despite explicit foreground/rendering mode. Actual native preview and installed-window screenshots show the intended black glyphs. This is a snapshot limitation; runtime contrast was checked in the native window.

## Native interaction verification

Used the separate `StickerCasePreview.app` and fake models, without writing personal audio settings:

- Set Chrome to **72%** through its accessible slider; the value and help text updated.
- Toggled Chrome mute; the label changed to `Unmute Google Chrome` and the confirmed state remained readable.
- Switched Sticker Case → Ceramic → Sticker Case; **72% and mute were preserved** across presentations.
- Clicked/focused the fader, set 72%, pressed Right; **73%** appeared and focus remained on the slider. Adjusting it followed existing behavior and cleared mute.
- Turned Boost off; app slider range changed from **0–200%** to **0–100%**, and the fake WhatsApp gain clamped from **160% to 100%**.
- Selected **USB Headphones** for Chrome in the preview output menu; its label/help updated and continued to explain that all Chrome tabs share that output.
- Opened and dismissed the installation sheet through the new header help button. No connection/registration action was executed.
- Confirmed capability-based previous/next/shuffle/playback controls and accessible disabled states in the preview; real site playback was not changed.

No live volume, mute, routing or browser playback actions were used for visual validation. The installed app's existing Chrome connection was already disconnected before the update and remained so; reconnecting/re-registering it was outside this appearance change.

## Local update

- Preserved the prior **0.8.0** bundle at `build/WinMix.backup-0.8.0-before-sticker-case.app`.
- Installed the verified **0.9.0** bundle at `build/WinMix.app` and reopened it.
- Selected **Sticker Case** through the real appearance menu and verified the resulting native window, unchanged Chrome volume **100%**, Boost off and existing AirPods output.
- Candidate also remains available at `build/sticker-case/WinMix.app`.
