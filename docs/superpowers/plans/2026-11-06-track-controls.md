# Browser Track Controls Implementation Plan

**Goal:** Previous, next and confirmed shuffle control in MacVolume browser rows.

**Architecture:** A scoped page transport adapter reports capabilities alongside the existing media controller. Content bridge and service worker validate and route transport messages to one top-level player. Swift models use the existing per-tab request/pending flow; both appearances share buttons.

**Tech Stack:** SwiftUI, Swift Codable, Chrome MV3 JavaScript, existing Node/Swift tests and isolated browser integration.

**Spec:** docs/superpowers/specs/2026-11-06-track-controls-design.md

## Constraints

macOS 14.4+; no additional permissions/dependencies; preserve gains, mute and active style; explicit shuffle-on/off; legacy capabilities optional; no automatic repeated next/previous clicks.

## Tasks (execute inline)

- [ ] Add transport command validation and optional capabilities in Swift and JavaScript; test rejected actions, mixed volume writes and legacy state.
- [ ] Add transport-controller.js, scope DOM lookups to YouTube players, check readiness, read semantic shuffle state, and confirm outcomes; add focused adapter tests.
- [ ] Wire the adapter into page state, content bridge, manifest/bootstrap and one-frame worker routing; retain gain/playback behavior.
- [ ] Add capability-gated model actions and shared previous/next/shuffle buttons in both appearances; exercise model acknowledgements and render previews.
- [ ] Extend the real-extension isolated integration fixture and verify previous/next/shuffle with unchanged gain and other tabs.
- [ ] Run Swift/Node/installer checks, package 0.7.0, inspect both appearances, update the local app/extension, verify live controls, and record evidence.
