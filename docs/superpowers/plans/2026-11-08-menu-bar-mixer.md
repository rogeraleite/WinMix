# Menu-Bar Mini Mixer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent menu-bar icon opening a compact per-app volume, mute and output mixer synchronized with the existing main window.

**Architecture:** Add a SwiftUI `MenuBarExtra` with window style alongside a single identified main `Window` and the existing `Settings` scene. Inject the app-owned mixer and permission models into a small native panel; route every audio mutation through the existing `MixerModel`. A small observable navigation object delivers one-shot Chrome Setup requests to the main window.

**Tech Stack:** SwiftUI/AppKit, existing Core Audio model, XCTest, existing Node/Python tests; macOS 14.4+; no new packages.

**Spec:** `docs/superpowers/specs/2026-11-08-menu-bar-mixer-design.md` (approved 2026-11-08).

**Authorization:** The owner requested implementation of all three open items on 2026-11-08. Implementation source is complete through `cfeb7b8`; the combined local candidate is 0.8.0 (11). Unchecked native/hardware steps below remain unverified; see `docs/menu-bar-validation.md` for precise evidence and tool limitations. The workflow skill names in the standard header are not installed in the current skill catalog; do not assume they are available or make installation a product dependency. At execution time follow the available workflow and the owner's delegation preference. No sub-agents are needed for this planning task.

## Global Constraints

- macOS 14.4 minimum; no new package dependency.
- Use the SF Symbol `slider.horizontal.3`; preserve the existing Dock/app icon.
- Keep the current regular application/Dock behavior and launch-at-login setting. Do not add `LSUIElement` or change activation policy.
- The icon is always present while the app runs; no show/hide preference in this first release.
- All content observes the existing app-owned models; no second process monitor, `MixerModel`, Chrome socket server, UserDefaults schema for audio settings or Core Audio tap implementation.
- Chrome is one app-level master here; its tabs continue to share its selected output. There is no new global/system-volume slider.
- Use native controls and semantic system colors so the panel follows macOS light/dark appearance and accessibility settings. The main window keeps its Ceramic/Retro selection.
- Only the app list scrolls; the header and footer remain visible.
- Tests do not reroute the owner's playing apps or change macOS default output.
- Do not alter the current browser host registration or personal audio settings merely to validate this feature.
- Complete and commit the existing routing/native-browser work separately before modifying shared implementation files for this feature.

## Files and dependencies

| Task | Files | Deliverable |
|---|---|---|
| 1 | Existing routing/setup plan and its source/test files | Separately verified prerequisite baseline |
| 2 | New `AppNavigation.swift`, new `AppNavigationTests.swift`; `MixerView.swift` | One-shot cross-scene setup navigation |
| 3 | New `MenuBarMixerView.swift`; `AppOutputMenu.swift` | Native compact panel, driven by existing model |
| 4 | New `MenuBarSceneContent.swift`; `WinMixApp.swift` | Working menu icon, one main window and lifecycle integration |
| 5 | `Probe.swift`; new `docs/menu-bar-validation.md`; `README.md`; release metadata | Visual/native verification and packaged delivery |

Paths in this table are under `Sources/WinMix/`, except tests under `Tests/WinMixTests/`, and the explicitly named docs. Tasks 2–5 run sequentially. Do not run overlapping Swift builds.

## Task 1: Establish the routing/setup prerequisite baseline

**Files:**
- Read: `docs/superpowers/plans/2026-11-07-routing-and-browser-setup.md`
- Read: `Sources/WinMix/MixerModel.swift`, `MixerRuntime.swift`, `AppOutputMenu.swift`, `BrowserBridgeInstaller.swift`, `BrowserSetupView.swift`
- Validate: `Tests/WinMixTests/MixerRoutingTests.swift`, `BrowserBridgeInstallerTests.swift`

**Interfaces consumed by later tasks:**

```swift
// Existing MixerModel, @MainActor:
var rows: [AppGroup] { get }
var outputName: String { get }
var boostEnabled: Bool { get set }
var maximumVolume: Double { get }
var error: String? { get set }
func setting(for group: AppGroup) -> VolumeSetting
func setVolume(_ volume: Double, for group: AppGroup)
func toggleMute(_ group: AppGroup)
func setOutput(_ uid: String?, for group: AppGroup)
func outputLabel(for group: AppGroup) -> String
func outputHelp(for group: AppGroup) -> String
```

- [x] Inspect `git status --short --branch` and the earlier plan. If routing/setup is still unfinished, complete it as its own delivery using that plan before starting Task 2. Record its final commit in the later validation report. Do not label the prerequisite finished merely because source files exist.
- [x] Run `swift test --filter MixerRoutingTests` and `swift test --filter BrowserBridgeInstallerTests` sequentially. Resolve baseline failures in the routing/setup change, preserving route recovery and installer safety. The menu-bar feature must not absorb unresolved audio behavior.
- [x] Confirm the earlier change's full tests/build and delivery checklist are complete. Save its tracked implementation in its own commit; stage exact task-owned paths, never `git add .` in this mixed worktree.
- [x] Record `git rev-parse HEAD` and inspect `git status --short`. Start Task 2 with known ownership of the files being modified. Planning docs can already be committed separately without including the prerequisite's uncommitted implementation.

**Acceptance:** routing/setup behavior is independently reviewable, its tests pass, and the exact interfaces above are present. If those interfaces changed during prerequisite review, reconcile this plan before writing menu-bar source.

## Task 2: Deliver one-shot Chrome Setup navigation

**Files:**
- Create: `Sources/WinMix/AppNavigation.swift`
- Create: `Tests/WinMixTests/AppNavigationTests.swift`
- Modify: `Sources/WinMix/MixerView.swift` (`MixerView` only; preserve both row layouts)

**Interfaces:**
- Produces: `@MainActor final class AppNavigation: ObservableObject` with `browserSetupRequested: Bool`, `requestBrowserSetup()`, `consumeBrowserSetupRequest() -> Bool`.
- Consumes: the existing `MixerView` sheet state `showingSetup` and `BrowserSetupView(chrome:)`.
- Produces: `MixerView(..., navigation: AppNavigation)`; default navigation supports existing isolated preview callers. Live scenes always supply the shared app-owned navigation.

- [x] Write these behavior tests first:

```swift
import XCTest
@testable import WinMix

@MainActor
final class AppNavigationTests: XCTestCase {
    func testRequestSurvivesUntilConsumerAppearsAndIsConsumedOnce() {
        let navigation = AppNavigation()
        XCTAssertFalse(navigation.consumeBrowserSetupRequest())
        navigation.requestBrowserSetup()
        XCTAssertTrue(navigation.browserSetupRequested)
        XCTAssertTrue(navigation.consumeBrowserSetupRequest())
        XCTAssertFalse(navigation.browserSetupRequested)
        XCTAssertFalse(navigation.consumeBrowserSetupRequest())
    }

    func testRepeatedPendingRequestsCoalesceAndLaterRequestWorks() {
        let navigation = AppNavigation()
        navigation.requestBrowserSetup()
        navigation.requestBrowserSetup()
        XCTAssertTrue(navigation.consumeBrowserSetupRequest())
        XCTAssertFalse(navigation.consumeBrowserSetupRequest())
        navigation.requestBrowserSetup()
        XCTAssertTrue(navigation.consumeBrowserSetupRequest())
    }
}
```

- [x] Run `swift test --filter AppNavigationTests`; expect missing-type errors before the new implementation exists.
- [x] Implement the navigation object:

```swift
import Combine

@MainActor
final class AppNavigation: ObservableObject {
    @Published private(set) var browserSetupRequested = false

    func requestBrowserSetup() { browserSetupRequested = true }

    @discardableResult
    func consumeBrowserSetupRequest() -> Bool {
        guard browserSetupRequested else { return false }
        browserSetupRequested = false
        return true
    }
}
```

- [x] Extend `MixerView` with the observation and consumption below. Append the observer after the existing `.sheet`. Do not create another setup sheet; the header help button and menu shortcut converge on `showingSetup`.

```swift
// Property in MixerView; existing preview call sites remain valid.
@ObservedObject var navigation = AppNavigation()

// Modifiers on the root content, after .sheet(...):
.onAppear(perform: consumeSetupRequest)
.onChange(of: navigation.browserSetupRequested) { _, requested in
    if requested { consumeSetupRequest() }
}

// Method in MixerView:
private func consumeSetupRequest() {
    if navigation.consumeBrowserSetupRequest() { showingSetup = true }
}
```

Requests remain pending while the permission screen replaces `MixerView`; they are consumed once when that view becomes available. Repeated clicks while the sheet is already presented keep a single sheet open. Later main-window reopen must not reopen a consumed request.

- [x] Run `swift test --filter AppNavigationTests`; expect both tests to pass, with no live audio accessed by these tests. Run `swift build` for the view integration.
- [x] Review the diff, then commit only these three implementation/test files with message `Add one-shot navigation to browser setup`.

## Task 3: Deliver the compact native app-control panel

**Files:**
- Create: `Sources/WinMix/MenuBarMixerView.swift`
- Modify: `Sources/WinMix/AppOutputMenu.swift`

**Interfaces:**
- Consumes: `MixerModel` methods from Task 1; `AudioCaptureAccess.Status`; existing `MixerControlHelp` helpers.
- Produces: `MenuBarMixerView(model:permissionStatus:openMixer:openChromeSetup:)`.
- Produces: `AppOutputMenu(model:row:appearance:)` accepting `MixerAppearance?`, default `nil` for native appearance. Existing explicit `.ceramic` / `.retro` calls keep their behavior.

- [x] Extend output-menu presentation without copying routing logic. Replace its appearance property and label foreground expression with:

```swift
var appearance: MixerAppearance? = nil

private var labelColor: Color {
    switch appearance {
    case .ceramic: return Ceramic.secondary
    case .retro: return .white.opacity(0.65)
    case nil: return Color(nsColor: .secondaryLabelColor)
    }
}
// The existing label uses .foregroundStyle(labelColor).
```

Keep the same Picker binding, saved-disconnected item, Chrome explanation, help text and accessibility values. Use `var` for this defaulted stored property so the synthesized memberwise initializer preserves the explicit `appearance:` argument used by existing callers.

- [x] Define the panel inputs and layout. Keep only rows scrollable and leave space for a status message:

```swift
import AppKit
import SwiftUI

struct MenuBarMixerView: View {
    @ObservedObject var model: MixerModel
    let permissionStatus: AudioCaptureAccess.Status
    let openMixer: () -> Void
    let openChromeSetup: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if permissionStatus == .denied {
                Text("Allow System Audio Recording in Settings to control app audio.")
                    .font(.callout).padding(14)
            } else if model.rows.isEmpty {
                Text("Apps appear here when they play audio.")
                    .font(.callout).foregroundStyle(.secondary).padding(20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.rows) { row in
                            appRow(row)
                            if row.id != model.rows.last?.id { Divider() }
                        }
                    }
                }
                .frame(height: min(CGFloat(model.rows.count) * 116, 300))
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).lineLimit(2).help(error)
                    .padding(.horizontal, 12).padding(.vertical, 6)
            }
            Divider()
            footer
        }
        .frame(width: 360)
        .frame(maxHeight: 520)
    }
}
```

Use actual measured row height when adjusting the 116-point sizing estimate. If content grows under larger accessibility text, shrink the scroll area first and retain footer visibility. A native render/native UI check, rather than a hardcoded row count assertion, determines whether 520 points is respected.

- [x] Add the header and footer inside `MenuBarMixerView`. Settings uses the existing scene through `SettingsLink`; no duplicate `SettingsView` in the panel:

```swift
private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack {
            Text("WinMix").font(.headline)
            Spacer()
            Toggle("Boost", isOn: $model.boostEnabled)
                .toggleStyle(.switch).controlSize(.mini)
                .fixedSize().help(MixerControlHelp.boost(model.boostEnabled))
                .disabled(permissionStatus == .denied)
        }
        Text(model.outputName.isEmpty ? "System output" : model.outputName)
            .font(.caption).foregroundStyle(.secondary)
            .lineLimit(1).help(model.outputName)
    }
    .padding(12)
}

private var footer: some View {
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            Button("Open Mixer", action: openMixer)
            Spacer()
            SettingsLink { Text("Settings…") }
        }
        HStack {
            Button("Chrome Setup…", action: openChromeSetup)
            Spacer()
            Button("Quit WinMix") { NSApplication.shared.terminate(nil) }
        }
    }
    .buttonStyle(.borderless)
    .padding(12)
}
```

Verify Settings activation from another frontmost app in Task 4. Do not intercept Escape globally: native menu-bar window handling must dismiss only the panel, not close the main mixer.

- [x] Add the app row using a native `Slider`. Its two-line layout retains room for controls at 360 points:

```swift
private func appRow(_ row: AppGroup) -> some View {
    let setting = model.setting(for: row)
    let state = setting.isMuted ? "Muted" : row.isPlaying ? "Playing" : "Paused"
    return VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
            Image(nsImage: row.identity.icon).resizable()
                .frame(width: 22, height: 22).accessibilityHidden(true)
            Text(row.identity.name).font(.callout.weight(.medium))
                .lineLimit(1).help(row.identity.name)
            Spacer(minLength: 4)
            Text(state).font(.caption).foregroundStyle(.secondary)
        }
        HStack(spacing: 8) {
            Button { model.toggleMute(row) } label: {
                Image(systemName: setting.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.borderless)
            .help(MixerControlHelp.mute(setting.isMuted))
            .accessibilityLabel(setting.isMuted ? "Unmute \(row.identity.name)" : "Mute \(row.identity.name)")
            .accessibilityValue(setting.isMuted ? "Muted" : "Not muted")
            Slider(value: Binding(
                get: { min(model.setting(for: row).volume, model.maximumVolume) },
                set: { model.setVolume($0, for: row) }
            ), in: 0...model.maximumVolume) {
                Text("\(row.identity.name) volume")
            }
            .labelsHidden()
            .help(MixerControlHelp.volume(setting.volume, maximum: model.maximumVolume, muted: setting.isMuted))
            .accessibilityValue("\(Int((setting.volume * 100).rounded())) percent")
            Text("\(Int((setting.volume * 100).rounded()))%")
                .font(.caption.monospacedDigit()).frame(width: 38, alignment: .trailing)
        }
        AppOutputMenu(model: model, row: row)
    }
    .padding(12)
}
```

The text state explicitly identifies mute and the existing output label identifies disconnected/retrying routes. Preserve `outputHelp(for:)` so route errors expose the effective destination. The existing `setVolume` clears mute, so dragging a muted app's slider also unmutes it in this panel; keep that same behavior. Do not create a panel-specific audio setting cache or mutate macOS system volume.

- [x] Run `swift build`, then `swift test --filter MixerRoutingTests`. These checks verify compilation and the existing routing contract, not native menu tracking. Task 5 supplies visual and interaction evidence; do not add tests that merely assert the SwiftUI hierarchy matches its implementation.
- [x] Review and commit the two files with message `Add native compact per-app mixer panel`.

## Task 4: Integrate the menu-bar scene and window lifecycle

**Files:**
- Create: `Sources/WinMix/MenuBarSceneContent.swift`
- Modify: `Sources/WinMix/WinMixApp.swift`

**Interfaces:**
- Consumes: Task 2 `AppNavigation`, Task 3 `MenuBarMixerView`, existing `PermissionModel.refresh()`.
- Produces: `MenuBarSceneContent(model:permission:navigation:)`, a bridge that owns no audio/browser services.
- Stable scene ID: `mixer`.

- [x] Implement the bridge below:

```swift
import AppKit
import SwiftUI

struct MenuBarSceneContent: View {
    @ObservedObject var model: MixerModel
    @ObservedObject var permission: PermissionModel
    @ObservedObject var navigation: AppNavigation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarMixerView(model: model, permissionStatus: permission.status,
                         openMixer: showMixer,
                         openChromeSetup: {
                             navigation.requestBrowserSetup()
                             showMixer()
                         })
            .onAppear(perform: permission.refresh)
            .onReceive(NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification)) { _ in
                    permission.refresh()
                }
    }

    private func showMixer() {
        openWindow(id: "mixer")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
```

- [x] Add the shared navigation object beside the existing app-owned models; replace `WindowGroup("WinMix")` with `Window("WinMix", id: "mixer")`, retaining the existing size, hidden-title-bar styling, permission branching and active-notification refresh. Pass the shared navigation into `MixerView`:

```swift
@StateObject private var navigation = AppNavigation()

// Inside the existing non-denied branch:
MixerView(model: mixer, chrome: chrome, navigation: navigation)

// A sibling Scene, before or after the existing Settings scene:
MenuBarExtra {
    MenuBarSceneContent(model: mixer, permission: permission, navigation: navigation)
} label: {
    Image(systemName: "slider.horizontal.3")
        .accessibilityLabel("WinMix")
        .help("WinMix")
}
.menuBarExtraStyle(.window)
```

Keep `Main.main()` and its `--probe` branch intact. Do not instantiate `ChromeTabModel` in the menu scene: the existing app-owned one keeps tab controls alive in the main mixer and setup sheet.

- [x] Run `swift build` and `swift test --filter AppNavigationTests`. Check that no newer-than-14.4 API has entered the scene code. Use native `Window` single-window semantics rather than an unbounded identified `WindowGroup`.
- [ ] On an isolated/test app session, close the main window, open the menu panel, click `Open Mixer` five times, minimize and reopen, then close and click the Dock icon. Confirm one intended mixer window and retained main-window size/appearance. Keep any running personal audio app untouched.
- [ ] Test `Settings…` while another app is frontmost and with the mixer closed. It must bring the existing Settings window forward. Test `Chrome Setup…` with the mixer closed and while already open; dismiss the sheet, close/reopen the mixer, and verify no stale request reopens it. With permission denied, navigation remains queued until the existing permission screen yields to the mixer.
- [ ] Open/close the panel repeatedly without changing controls. Using the isolated routing fixture or private probe session, confirm `activeTapCount` and existing route generations do not change simply from presenting views. Never infer audio continuity from a static screenshot.
- [ ] Verify the actual native icon tooltip/accessibility name, Escape, outside-click dismissal, slider dragging and nested output-picker behavior. These are release gates; repair scene integration if native `MenuBarExtra` behavior differs on a supported macOS. Do not silently ship a nonfunctional menu or add a global event monitor to force dismissal.
- [x] Review and commit the two files with message `Integrate persistent menu-bar mixer and single-window navigation`.

## Task 5: Render states, validate interactions and package the release

**Files:**
- Modify: `Sources/WinMix/Probe.swift`, `README.md`
- Create: `docs/menu-bar-validation.md`
- Modify at release only: `Resources/Info.plist` (advance version/build from the completed prerequisite; preserve bundle ID, app icon and deployment minimum)

**Interfaces:**
- Consumes: `MixerModel(previewRows:settings:boostEnabled:outputName:outputDevices:)`, Task 3 panel with an explicit permission status and no-op navigation closures, the existing local `render(_:size:name:)` helper in `Probe.renderPreview`.
- Produces: `--probe --render-preview` PNGs for menu states plus evidence of actual native scene interaction.

- [x] Extend `renderPreview` after its existing render helper. Retain all existing main-window and setup renders. The following creates normal, Boost, empty, denied, disconnected and error states without a live tap or preference write:

```swift
let speakers = AudioOutputDevice(uid: "preview-speakers", name: "MacBook Pro Speakers")
let normalPanel = MixerModel(previewRows: rows,
    settings: settings.mapValues { value in
        var value = value
        value.volume = min(value.volume, 1)
        return value
    }, boostEnabled: false, outputName: speakers.name, outputDevices: [speakers])
let boostPanel = MixerModel(previewRows: rows, settings: settings,
    boostEnabled: true, outputName: speakers.name, outputDevices: [speakers])
let emptyPanel = MixerModel(previewRows: [], settings: [:], boostEnabled: false,
    outputName: speakers.name, outputDevices: [speakers])
var disconnectedSettings = settings
disconnectedSettings["com.google.Chrome"] = VolumeSetting(volume: 0.3,
    outputUID: "preview-missing", outputName: "Disconnected headphones")
let disconnectedPanel = MixerModel(previewRows: rows, settings: disconnectedSettings,
    boostEnabled: true, outputName: speakers.name, outputDevices: [speakers])
let failurePanel = MixerModel(previewRows: rows, settings: settings,
    boostEnabled: true, outputName: speakers.name, outputDevices: [speakers])
failurePanel.error = "Could not move the test app to USB audio. Still using MacBook Pro Speakers."

let menuStates: [(String, MixerModel, AudioCaptureAccess.Status)] = [
    ("normal", normalPanel, .authorized), ("boost", boostPanel, .authorized),
    ("empty", emptyPanel, .authorized), ("denied", normalPanel, .denied),
    ("disconnected", disconnectedPanel, .authorized),
    ("error", failurePanel, .authorized)
]
for (name, model, permissionStatus) in menuStates {
    for dark in [false, true] {
        let panel = MenuBarMixerView(model: model, permissionStatus: permissionStatus,
            openMixer: {}, openChromeSetup: {})
            .environment(\.colorScheme, dark ? .dark : .light)
        guard render(panel, size: NSSize(width: 360, height: 520),
                     name: "menu-\(name)-\(dark ? "dark" : "light")") else { return 1 }
    }
}
```

The `error` render proves presentation, not a simulated route failure. The prerequisite's fake-tap tests prove selected/effective route behavior. Avoid adding a production API just to mutate private failure state for screenshots.

- [ ] Add a many-app/long-name preview fixture after the menu renders. These unregistered preview identities fall back to their long bundle IDs as display names. Check footer visibility in native UI as well as the image:

```swift
let manyRows = (1...12).map { index -> AppGroup in
    let key = "preview.long.application.name.for.truncation.\(index)"
    return AppGroup(key: key, identity: ProcessIdentity(pid: -1, bundleID: key),
                    processes: [])
}
let manyPanel = MixerModel(previewRows: manyRows, settings: [:], boostEnabled: false,
    outputName: speakers.name, outputDevices: [speakers])
for dark in [false, true] {
    let panel = MenuBarMixerView(model: manyPanel, permissionStatus: .authorized,
        openMixer: {}, openChromeSetup: {})
        .environment(\.colorScheme, dark ? .dark : .light)
    guard render(panel, size: NSSize(width: 360, height: 520),
                 name: "menu-many-long-\(dark ? "dark" : "light")") else { return 1 }
}
```
- [x] Run these commands sequentially; record exit status and failures in the evidence document. Re-run a failed check after a relevant fix, not as a blind loop:

```sh
swift test
node --test Tests/ChromeExtension/*.test.mjs
python3 -m unittest discover -s Tests -p 'test_*.py'
swift build -c release
.build/release/WinMix --probe --render-preview /tmp/winmix-menu-preview
```

- [x] Inspect PNGs for both native color schemes and both existing main-window skins. Check readable labels/percentages, visible footer/focus, disconnected-output text, permission/error layout and truncation. Use a render session with no live audio; do not launch a second production mixer over the owner's existing instance.
- [ ] Complete the native matrix and record each outcome in `docs/menu-bar-validation.md`:

| Check | Required outcome |
|---|---|
| Close main window and panel | Audio/browser services remain alive; icon still available |
| Repeated open, minimized window, Dock reopen | A single intended mixer is brought forward |
| Open panel from another active application | Panel is usable; sliders and output picker track normally |
| Native light/dark, keyboard, VoiceOver | Names, percentages, mute/Boost states and output selection are understandable |
| Fake/private test app gain/mute/output | Main window and panel immediately reflect the same values |
| Saved settings and relaunch | Existing values restore; no alternate menu-specific settings |
| Boost on/off with a boosted private fixture | 200% range when enabled; existing clamp when disabled |
| Device disappears/returns in injected fixture | Existing fallback/return and selection retention pass |
| Failed move in fake-tap tests | Existing working route retained; failure/effective output remain honest |
| Chrome disconnected | App-level Chrome controls still work; footer setup navigation works |
| Escape / click outside / nested output menu | Dismissal does not interrupt an active slider/picker interaction |
| Main window closed during setup navigation | Sheet opens once on the recreated/revealed mixer |
| Quit in isolated app session | Process exits through normal termination and test taps stop |

Real personal-device switching, host replacement and changing privacy permission are not required test side effects. When hardware or minimum-OS testing is unavailable, state exactly what was not exercised and do not mark that gate passed.

- [x] Add README usage text explaining the menu icon, per-app controls, keeping WinMix running after window close, quitting through the footer, shared Chrome output and detailed tab controls in the main window. Document that the mini panel follows system appearance while the main mixer retains Ceramic/Retro. Link the new validation document.
- [x] Read the prerequisite's final `Resources/Info.plist` version before choosing the next release number/build. Record the chosen values in the validation document. Preserve `com.rogerleite.MacVolume`, `AppIcon` and macOS `14.4`; do not revert the prerequisite's release metadata.
- [x] Preserve any existing destination bundle before packaging: create a uniquely named sibling backup with `ditto` and verify it exists before invoking the build script, which deletes its output path. Prefer a new task-specific path `build/WinMix-menu-bar.app` for initial packaging:

```sh
./scripts/build-app.sh build/WinMix-menu-bar.app
codesign --verify --deep --strict build/WinMix-menu-bar.app
```

Do not run the script against an installed/working destination until its backup is verified. Building at a new path must not rewrite the registered Chrome host path. Quit the old instance before a native launch check; preserve all personal settings and host registration.

- [x] Record final commit, macOS/build version, commands/results, image paths, native checks performed, bundle path, backup path if used, signing result, and unperformed manual/hardware checks. Distinguish packaged locally from installed or published. Do not claim menu tracking or audio continuity was verified solely from PNGs or unit tests.
- [x] Review the final implementation diff against the approved spec; fix material gaps before delivery. Commit only menu-bar implementation/docs/release changes with message `Validate and package menu-bar mini mixer`. Do not push or publish unless separately requested.

## Plan self-review / acceptance mapping

| Approved requirement | Implemented/verified by |
|---|---|
| Static menu icon and compact native surface | Tasks 3–4, Task 5 image/native matrix |
| Volume/mute/output/Boost share existing behavior | Task 1 interfaces, Task 3 bindings, Task 5 private/fake checks |
| Native colors; main skins preserved | Task 3 output-menu extension, Task 5 all appearances |
| One mixer, audio outlives views, no duplicate browser service | Task 4 shared injection and lifecycle checks |
| Main window, settings, one-shot setup, quit | Task 2 behavior tests, Tasks 3–4 native navigation checks |
| Denied/unknown permission; empty/errors/disconnects | Tasks 3–5 states and permission refresh |
| Scroll, long names, keyboard and accessibility | Task 3 layout/native Slider, Task 5 fixtures/native checks |
| Preserve user audio/settings/host registration | Global constraints, Task 1 fake boundaries, Task 5 packaging procedure |
| Regression checks and locally reviewable bundle | Task 5 tests, release build, signing and evidence |

Planning originally changed no feature source. The later implementation ran 57 Swift tests, extension/Python checks, native browser/audio integration, native diagnostic-window interactions and release packaging. Actual status-item popover interaction is unverified because the UI tool could not expose the macOS status item. Many-app fixtures are implemented and rendered; their native many-app interaction check remains open. These unchecked checks are not implementation omissions or passing release gates. Final evidence: `docs/menu-bar-validation.md`.

## Platform references

- [Apple: MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) — window-style menu-bar content with standard controls.
- [Apple: Window](https://developer.apple.com/documentation/swiftui/window) — single, unique scene window.
- [Apple: SettingsLink](https://developer.apple.com/documentation/swiftui/settingslink) — open the Settings scene or bring its existing window forward.
