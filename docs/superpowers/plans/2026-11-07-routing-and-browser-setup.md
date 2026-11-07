# Per-app Routing and Browser Setup Implementation Plan

**Goal:** Persist independent app output destinations with automatic system fallback/return, and connect the browser from the app without Terminal.

**Architecture:** Audio routing and browser registration are independent delivery items. Routing adds a device inventory, persisted UID choice and injectable tap boundary to the existing mixer. Browser setup adds a native host installer behind the existing installation sheet. Shared final consumers are the app bundle, documentation and validation evidence.

**Tech Stack:** SwiftUI/AppKit, Core Audio process taps, Foundation FileManager/JSON, existing Swift/Node/Python tests. macOS 14.4+; no new packages or Chrome permissions.

**Spec:** docs/superpowers/specs/2026-11-07-routing-and-browser-setup-design.md

## Dependency and ownership graph

| Item | Inputs | Owner/files | Observable result | Verification | Consumers |
|---|---|---|---|---|---|
| A: app routing | Existing MixerModel and ProcessVolumeTap; owner's fallback choice | Primary: AudioOutputDevice.swift, MixerModel.swift, ProcessVolumeTap.swift/tap protocol, AppOutputMenu.swift, mixer views, routing tests and probes | Independent saved destinations, fallback and automatic return | Fake tap/device tests, render states, private routing probe | Final app bundle and routing reviewer |
| B: native setup | Existing BrowserSetup ID validation and Python host manifest contract | Setup developer: BrowserBridgeInstaller.swift, BrowserSetupView.swift, native installer tests | In-app Connect browser, ID prefill and honest live connection status | Disposable installer tests and sheet verification | Final app bundle and setup reviewer |
| C: close/release | A and B complete and reviewed | Primary: versions, README/setup docs, build packaging and evidence | Local updated app, prior version backed up | All required tests, signed bundle, native UI inspection | Owner |

A and B can run concurrently with disjoint write ownership. Do not run overlapping Swift builds. C depends on both A and B and independent review. Use the existing inline primary implementation for A, a delegated developer for B, and fresh read-only reviewers after integration.

## Contracts

- `AudioOutputDevice`: UID identity, display name and HAL object ID, with a live available-output snapshot. Menus include System default (`nil` UID).
- `VolumeSetting`: optional saved output UID/name; absent values from legacy JSON mean System default. `isDefault` also requires no explicit device.
- `MixerModel.setOutput(_:for:)`: accepts an optional device UID for one AppGroup; persists selection and reapplies only its route. Published output inventory and route-label helpers drive a shared AppOutputMenu.
- A `MixerAudioTap` protocol matches existing tap start/move/gain/process/health/diagnostic operations. A runtime dependency object supplies device/default snapshots and tap factory, and disables system observations for tests.
- `BrowserBridgeInstaller`: validates a normalized 32-letter a–p ID and a real app bundle, writes a per-user `com.rogerleite.macvolume.chrome` manifest for one origin, and exposes existing registration information. Setup developer may choose exact signatures, then report them before integration.
- Browser setup development does not modify MixerModel, audio views, app version, build script or shared release documentation. Root does not edit the installer/setup files until handoff.

## Delivery checklist

- [ ] Implement A: compatibility and injected routing tests; available-device watcher; per-group route resolution and failure recovery; per-app menus in both styles.
- [ ] Implement B: native manifest installer and filesystem tests; prefilled ID and Connect browser action; honest saved/live connection feedback and replacement handling.
- [ ] Integrate A and B, run one coordinated Swift test/build sequence, and resolve compilation/test failures at their source.
- [ ] Run separate fresh routing/setup reviews; cross-fix or explicitly assign findings with ownership handoff, then verify fixes and final interfaces.
- [ ] Extend/render previews for available, selected and fallback devices in both styles and native setup states.
- [ ] Run isolated routing/browser validation where available, preserving personal outputs, saved levels and host registration.
- [ ] Update version/docs, create and verify the signed bundle, back up/update the local app and verify native UI without changing user-selected audio destinations.
- [ ] Record final evidence, remaining limits and actual local availability, then commit only task-owned files.
