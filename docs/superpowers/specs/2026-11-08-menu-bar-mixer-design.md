# WinMix menu-bar mini mixer — approved design

Date: 2026-11-08

Status: Design approved by the owner on 2026-11-08, followed by authorization to write the detailed implementation plan. Implementation is outside the current planning request. The selected scope is volume, mute and output per app, with detailed Chrome-tab controls remaining in the main window.

## Context and dependencies

No prior menu-bar feature plan or implementation was found in the repository. The 2026-11-07 routing/browser spec explicitly excludes this feature from its update. This is a separate follow-up, not a change to that earlier scope.

`WinMixApp` owns one `MixerModel`, `ChromeTabModel`, `PermissionModel` and `LoginItemModel` above its window. Audio therefore already outlives a closed mixer window. Preserve that ownership when adding the menu-bar surface.

Per-app routing and native browser setup are still uncommitted work. Finish and validate their shared model interfaces before implementing this feature. Planning can proceed now; do not overwrite, reimplement or silently include those changes in a menu-bar commit.

## Options considered

1. **Selected: app mini mixer.** A compact panel with app volume, mute and output selection, plus shortcuts. It covers quick adjustments while keeping detailed browser controls in the main window.
2. **App and browser-tab mini mixer.** Include tab playback, volume, mute and track controls. More control without opening the window, but longer content and extra disconnected/pending states. Not selected for this release.
3. **Shortcuts menu.** Open mixer, settings and quit. Smallest implementation, but every audio adjustment still requires the main window.

## First release

Show a static monochrome mixer icon in the macOS menu bar whenever WinMix runs. Its accessible name and tooltip are `WinMix`. Use the SF Symbol `slider.horizontal.3`; preserve the existing Dock/app icon. Do not animate meters or show continuously changing numeric text in the menu bar.

Click opens a compact native panel, approximately 360 points wide, with a maximum height of 520 points. Only the app list scrolls; the header and footer remain visible. Clicking outside or pressing Escape closes it. Dragging a slider and interacting with an output picker must keep the interaction usable. These behaviors require native UI verification, not screenshot checks alone.

Panel content, in order:

- Header: `WinMix`, current system output name, shared Boost toggle.
- App list: use exactly `MixerModel.rows`, with stable `AppGroup.key` identity and the same ordering. Each app shows its icon, name, Playing/Paused/Muted state, mute button, volume slider, numeric percentage and output selector.
- Status: routing failures explain the selected and effective output using existing model labels/help. Do not report success while a move is still failing.
- Footer: `Open Mixer`, `Settings…`, `Chrome Setup…`, and `Quit WinMix`.

Reuse the model's volume range (100%, or 200% with Boost), clamping, persistence, routing fallback/return and mute behavior. Moving a slider while muted follows the main window's existing behavior. Chrome is one app-level master here; its tabs continue to share its selected output. There is no new global/system-volume slider.

Use native controls and semantic system colors so the panel follows macOS light/dark appearance and accessibility settings. The main window keeps its Ceramic/Retro selection. This proposal does not introduce a third saved skin or copy the full main window into the panel.

## Lifecycle and navigation

- Keep the current regular application/Dock behavior and launch-at-login setting. Do not add `LSUIElement` or change activation policy.
- The icon is always present while the app runs; no show/hide preference in this first release.
- Closing the main window or panel leaves the same model, audio routes and browser connection alive.
- `Open Mixer` brings the existing mixer window forward or recreates it if closed. Repeated use must not accumulate mixer windows. Give the main mixer a stable scene identity and preserve opening from the Dock.
- `Settings…` opens the existing settings scene and brings it forward. `Chrome Setup…` opens the existing native setup sheet from the main window; consume this navigation request once so later window opens do not reopen the sheet.
- `Quit WinMix` terminates the application through its existing termination path, which stops taps. Clearly distinguish closing a view from quitting the app.
- Refresh audio permission when the panel appears and when the app becomes active; the menu-bar surface must not depend on the main window being open to notice permission changes.

## States and accessibility

- Empty list: explain that apps appear when they play audio; keep navigation and quit available.
- Permission denied: show a short explanation and `Open Mixer` to the existing permission screen; hide audio controls. Permission not determined follows the existing first-use flow without proactively creating taps just to open the panel.
- Device disconnected: keep the saved destination visible and describe fallback, using `outputLabel(for:)` and `outputHelp(for:)`.
- Route failure: show the model's failure message and effective-route help; opening the panel never retries by creating an independent route.
- Browser disconnected: app-level Chrome audio control remains independent of tab bridge availability. Setup remains available through the footer.
- Long names and many apps: truncate labels with full-name tooltips, preserve a usable slider width and percentage, scroll without hiding footer actions.
- Support keyboard focus, slider arrow adjustment, descriptive mute labels, accessible current values and visible focus. Do not rely on color alone for mute/failure/Boost state.

## Technical approach and boundaries

Use SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)`. Apple documents the window style for menu-bar panels containing standard interactive controls: https://developer.apple.com/documentation/swiftui/menubarextra and https://developer.apple.com/documentation/swiftui/menubarextrastyle/window . This stays within the existing macOS 14.4 minimum and adds no package dependency.

Keep the menu icon label independent from the meter timer. All content observes the existing app-owned models; no second process monitor, `MixerModel`, Chrome socket server, UserDefaults schema for audio settings or Core Audio tap implementation.

Planned file boundaries:

| File | Responsibility |
|---|---|
| `Sources/WinMix/WinMixApp.swift` | Compose the menu-bar scene with the existing model instances; stable main-window identity; scene navigation and permission refresh. |
| `Sources/WinMix/MenuBarMixerView.swift` (new) | Panel layout, rows, native controls, status and footer actions. Receives models and action closures; creates no runtime services. |
| `Sources/WinMix/MenuBarSceneContent.swift` (new) | Bridge panel actions to SwiftUI window/settings navigation and refresh permission independently of the main window. |
| `Sources/WinMix/AppNavigation.swift` (new) | Main-actor observable one-shot request for opening Chrome Setup from a different scene. Keep this boundary small. |
| `Sources/WinMix/MixerView.swift` | Consume the Chrome Setup navigation request and present the existing sheet once. |
| `Sources/WinMix/AppOutputMenu.swift` | Add a native/semantic-color presentation option while preserving Ceramic and Retro callers. Continue using the same routing methods. |
| `Sources/WinMix/Probe.swift` | Render deterministic panel states using preview models, without live audio or preference writes. |
| `Tests/WinMixTests/AppNavigationTests.swift` (new) | Verify one-shot navigation consumption and repeated requests. |
| `Tests/WinMixTests/MixerRoutingTests.swift` | Reuse isolated routing fixtures for shared-control regressions only when a model change makes them necessary. |
| `README.md`, `docs/menu-bar-validation.md` (new) | Explain usage/lifecycle and record actual validation evidence. |

Do not refactor the existing main-window row layouts solely to share visuals: native compact controls may differ while model mutations stay identical. Extend the shared output menu only where its current required `MixerAppearance` would force Ceramic/Retro colors into a native panel.

## Delivery sequence for the implementation plan

1. **Prerequisite checkpoint:** validate and commit routing/native setup separately. Confirm `MixerModel` routing interface and clean ownership of shared files.
2. **Shared lifecycle and navigation:** stable mixer scene, menu scene scaffold, shared model injection, existing settings navigation, one-shot Chrome Setup request. Verify closing/reopening and repeated open actions before audio UI is expanded.
3. **Compact app controls:** native panel, volume/mute/Boost, shared output selector, empty/denied/failure states, accessibility. Keep browser-tab detail in the main window, as selected by the owner.
4. **Verification and delivery:** deterministic preview renders; native interaction checks; isolated shared-model/routing checks; regression tests/build; documentation; preserved prior bundle and locally packaged app.

The executable checkbox plan is `docs/superpowers/plans/2026-11-08-menu-bar-mixer.md`, with interfaces, code steps and commands. No implementation is part of the current planning request.

## Acceptance and validation

Verify all of these before marking the later implementation complete:

1. One icon appears and opens the panel when the main window is closed. Closing/reopening either surface does not create new mixer/Chrome services or taps by itself.
2. An app adjustment in one surface is reflected in the other through the same model. The existing persistence and route selection survive relaunch.
3. Explicit outputs, fallback/return, unity-gain routing and failure recovery remain covered by injected fake-device/tap tests; tests do not reroute the owner's playing apps or change macOS default output.
4. `Open Mixer` repeatedly reveals a single intended main window; Dock reopening works; settings and Chrome Setup work with the main window initially closed; setup opens once per request.
5. Empty, muted, Boost, disconnected-output, route-failure, long-name, many-app and denied-permission panels render without clipping. Check light/dark modes and keyboard/accessibility interaction in the native panel.
6. Slider dragging, nested output picker use, Escape and outside-click dismissal work in the real menu-bar panel on the supported deployment target and development macOS. Headless images do not prove this.
7. Run `swift test`, `node --test Tests/ChromeExtension/*.test.mjs`, `python3 -m unittest discover -s Tests -p 'test_*.py'`, and a release app build. Record results and any unperformed hardware/manual checks honestly.
8. For local packaging, preserve the installed prior app before replacement, verify signing and launch, and do not alter the current browser host registration or personal audio settings merely to validate this feature.

## Not in this first release

Per-tab controls, media artwork, animated meters in the menu bar, global shortcuts, a Dock-less mode, hidden-icon preferences, system output changes, a global mute command, launch/login redesign and additional browser permissions.

## Review decisions

The owner confirmed app controls with detailed browser-tab controls in the main window, then approved the full design, including native light/dark presentation and keeping the Dock/current launch behavior. No runtime code has been changed by the planning work.
