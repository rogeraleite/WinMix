# Sticker Case (3C) — approved appearance

The owner selected `3C / Sticker Case` from the four Mixtape Collage variants and explicitly requested implementation on 2026-11-10. This authorizes the design and implementation in the same session.

## Visual contract

- Light recycled-paper surface `#EFEDE8`, white sticker `#FFFFFF`, ink `#191919`, turquoise `#28B8AF`, pink `#EF258D`.
- Centered WinMix wordmark in bold condensed italic sans serif, on a white die-cut sticker over two colored tape strips. The application/Dock and extension icons stay as they are.
- Clear black outlines, square cream speaker/transport buttons and black rectangular fader handles with a white notch. Text and control geometry stay sharp; faint static paper grain stays decorative.
- App icons, names and output selectors form the left column; mute, horizontal volume and numeric percentage form the right. The Chrome master is pink; child tabs sit on pale turquoise inside a single white-edged cut-corner sticker. Existing track controls and explanations remain available.
- Header keeps the appearance menu and setup help. System output stays informational; output selectors remain per app and tabs inherit Chrome's output.

## Integration

Add persistent `MixerAppearance.stickerCase` with title `Sticker Case`; preserve the `ceramic` and `retro` raw values. Use the new style as the fallback for fresh installs while honoring any saved selection. The menu-bar panel retains its native macOS appearance.

Use the same app-owned `MixerModel` and `ChromeTabModel`, output menu, tab capability checks, pending/requested volume semantics, errors, setup sheet, playback, shuffle and transport actions. No new audio/browser services or dependencies. macOS 14.4+ and SwiftUI remain the platform.

The window must scroll at compact sizes, truncate long names with help text, distinguish muted/disabled/pending/disconnected/unsupported states without color alone, and support keyboard adjustment, focus indication and native slider accessibility.

## Verification

Build and run existing Swift tests. Extend the isolated renderer and native preview to cover the new appearance, normal/Boost, empty, connected/disconnected browser, long names, many rows, routing failure/fallback and minimum width. Inspect actual rendered PNGs and native preview interaction. Package and verify an ad-hoc signed bundle without changing browser registration or live audio settings. Record evidence in `docs/sticker-case-validation.md`.
