# Sticker Case Implementation Plan

> Execute the approved 3C appearance in this session, task by task. User instruction already authorizes implementation; no further design or execution-choice approval is required.

**Goal:** Implement the selected 3C Sticker Case appearance in the native WinMix mixer.

**Architecture:** Add one presentation view and a small set of native SwiftUI drawing/control primitives. Extend the shared output and browser-tab presentation paths while preserving the current models and all existing action/capability logic.

**Tech Stack:** SwiftUI, AppKit, Swift Package Manager; macOS 14.4+; no dependencies.

**Spec:** `docs/superpowers/specs/2026-11-10-sticker-case-design.md`

## Global Constraints

- Preserve existing `ceramic` and `retro` saved raw values and the original app/extension icons.
- Keep app-owned models and per-app output routing; tabs inherit Chrome output.
- Keep macOS 14.4+, no additional packages, native menu-bar presentation.
- Diagnostics use fake models and appearance overrides; never write personal preferences or register a browser host to test presentation.

### Task 1: Native appearance and shared controls

**Files:** Create `Sources/WinMix/StickerCaseStyle.swift`, `Sources/WinMix/StickerCaseMixerView.swift`; modify `Sources/WinMix/MixerAppearance.swift`, `Sources/WinMix/MixerView.swift`, `Sources/WinMix/AppOutputMenu.swift`, `Sources/WinMix/BrowserTabIcon.swift`, `Sources/WinMix/ChromeTabView.swift`.

**Interfaces:** `StickerCaseMixerView(model:chrome:appearance:showSetup:)` consumes the existing models and `Binding<MixerAppearance>`. `StickerVolumeSlider(value:maximum:isMuted:label:accent:)` matches the existing slider semantics; `StickerButtonStyle(selected:)` draws shared button chrome. `StickerPaper` and `StickerOutline` provide deterministic decorative materials.

- [x] Add `case stickerCase` and an exhaustive title switch; dispatch it from `MixerView` and use it as the initial fallback.
- [x] Implement the paper, cut-corner outline, label, outlined buttons and accessible fader using the existing `CeramicVolumeSlider` interaction/accessibility pattern.
- [x] Implement the sticky header/output strip, app rows, Chrome sticker group, empty and error states using existing model mutations.
- [x] Update shared header colors/help, output-selector chrome and generic-site icon for the light new theme.
- [x] Add a Sticker Case layout to shared browser rows and use the same capability/connection/pending guards and transport helpers. Put extra track actions below the primary row at compact widths.
- [x] Compile with `swift build`; resolve compiler diagnostics before visual validation.

### Task 2: Isolated validation and delivery

**Files:** Modify `Sources/WinMix/Probe.swift`, `Sources/WinMix/MixerPreview.swift`, `README.md`; create `docs/sticker-case-validation.md`.

**Interfaces:** Existing `--probe --render-preview <prefix>` continues to render all appearances; add compact/long/error fixtures for Sticker Case. `--preview-ui --preview-appearance stickerCase` selects a diagnostic style without saved-setting writes.

- [x] Extend the render width selection and fixtures; allow selecting the native preview appearance from the command line.
- [x] Run `swift test` and render real SwiftUI screenshots with `--probe --render-preview`; inspect header, group border, text wrapping and controls.
- [x] Exercise the isolated native preview with keyboard/mouse, including style switching, slider adjustment, Boost and setup help where supported by automation. Record any limits accurately.
- [x] Run `node --test Tests/ChromeExtension/*.test.mjs` and `python3 -m unittest discover -s Tests -p 'test_*.py'` for shared integration regressions.
- [x] Build `build/sticker-case/WinMix.app` using `./scripts/build-app.sh build/sticker-case/WinMix.app`; run `codesign --verify --deep --strict` and check bundled resources.
- [x] Document the new appearance and actual validation evidence, then review `git diff --check` and the final diff.

Delivery evidence and native/offscreen verification limits are recorded in `docs/sticker-case-validation.md`. Local 0.8.0 bundle was preserved before replacing `build/WinMix.app` with verified 0.9.0 and selecting Sticker Case through its actual menu.
