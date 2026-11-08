# Per-app output routing and native browser setup

Owner authorization: implement per-app output devices and simpler browser setup. Owner explicitly chose automatic fallback to the current system output if a selected device disappears, followed by return to that device when it reappears. The menu-bar question was explanatory; a menu-bar mixer is outside this update.

## Output routing

Each app row in Ceramic and Retro gets a compact output menu with System default and currently available output devices. Choices persist by device UID and application bundle ID, along with a last-known device name for disconnected selections. Chrome tabs share Chrome's app-level output. Do not change the macOS system output as a side effect of selecting an app's destination.

An explicit destination requires a process tap even at 100% gain. A System default app at 100% and unmuted keeps the existing direct-output optimization. Existing volume/mute settings decode unchanged. App groups, gain, Boost, browser controls and original icon remain intact.

On output/default changes, resolve each app independently. Keep apps pinned to an available selected device; move default-following apps to the new system output. If a selected device is unavailable, retain the selection, route to the system output and clearly show the fallback. Return automatically when the selected UID reappears. On route creation/move failure preserve the existing working route, show the failure, and retry on subsequent device/health events. Continue the existing new-route-before-old-route-retirement behavior. Reconnect/sleep/wake recovery applies per app.

Enumerate alive devices with output streams, excluding WinMix private aggregate devices and other hidden devices. Device monitoring must not loop on aggregate devices created by WinMix itself. UI must distinguish a saved selection from the currently effective destination.

## Browser setup without Terminal

Keep the current Chrome extension permissions, ID validation and one-ID native-host registration boundary. A native Swift installer writes the same per-user host manifest previously written by the Python helper. It validates the bundled executable/extension, handles paths directly, writes atomically, and rejects symlink destinations and unrelated existing manifests. Replacing a different valid WinMix registration requires an explicit replace option in the setup sheet.

The primary setup flow is Open Chrome extensions → Load unpacked from the supplied folder → Paste extension ID → Connect browser. When an existing valid WinMix registration is available, prefill its extension ID. Show saved-registration success separately from the actual live Chrome connection. Keep folder/show/copy actions, update guidance and clear failure messages. First-time users still approve Developer mode, loading the extension and site access in Chrome; do not claim automatic extension installation.

No Terminal or Python is required by the new primary flow. Preserve the existing Python installer for development/test compatibility. Do not inspect browser profiles or unrelated extensions to find IDs.

## Verification and delivery

Use injected tap/device dependencies for routing tests without touching personal audio settings. Test saved-setting migration, routing at unity gain, separate destinations, system-default changes, device disappearance/return, route failures, helper-process updates and resetting to direct output. Native installer tests use disposable app bundles and host directories to cover validation, idempotence, replacement, safe paths, symlink refusal and atomic output.

Run Swift and relevant existing extension/installer tests, release build, both-style render checks, and isolated Core Audio/browser integration where available. Exercise output switching only in a private probe/test browser and explicit test output devices; do not reroute the user's playing apps for testing. Native setup validation should preserve the currently registered ID and host path. Use fresh independent reviewers for routing and setup after development; resolve their findings before final packaging. Preserve the previous installed app and record what was implemented, tested and made available locally.
