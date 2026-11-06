# MacVolume

Per-app volume control for macOS 14.4+, built on Core Audio process taps.

## Automatic YouTube tab volume

Version 0.3.0 automatically discovers and controls YouTube and YouTube Music players. No
per-tab activation or popup interaction is required. Access is limited to the approved HTTPS
YouTube origins; other sites are excluded. The extension controls HTML audio/video volume,
keeps the site's own volume separate, and uses Chrome's tab mute. It does not capture audio.

For an existing installation, reload **MacVolume Tabs** once at `chrome://extensions` and
approve the YouTube/Music access if requested. Already-open pages are bootstrapped
automatically. Chrome's app slider remains the master for every Chrome tab.

For initial setup, load `Extensions/Chrome` as an unpacked extension, copy its ID and run:

```sh
python3 scripts/install-chrome-bridge.py EXTENSION_ID --app "$PWD/build/MacVolume.app"
open build/MacVolume.app
```

See the [setup and behavior guide](docs/chrome-tab-volume.md), [validation evidence](docs/chrome-tab-validation.md)
and [remaining live checks](docs/chrome-manual-validation.md), in Portuguese. The app bundle
includes the extension, native bridge and setup scripts; the original extension folder and
registered ID can remain unchanged across this update.

## Build and run

```sh
./scripts/build-app.sh
open build/MacVolume.app
```

On first use macOS asks for **System Audio Recording** access. If the meters stay at zero,
check System Settings → Privacy & Security → Screen & System Audio Recording.
The app is ad-hoc signed, so each rebuild resets this: the first tap after a rebuild takes
3–4 s to start while macOS re-grants access. Later launches start at once. When testing, quit the
running app and do one throwaway tap run after every rebuild: runs that built a second tap during
that window, or started while the old build was still running, hung.

**Launch at login** is in MacVolume → Settings (⌘,). macOS remembers the app's path, so turn it on
from wherever the app will stay.

Headless probe modes (results go to the `--log` file):

```sh
# Tap one process and log levels, latency and CPU
open -n -W build/MacVolume.app --args --probe --pid <pid> --gain 0.3 --seconds 5 --log /tmp/probe.log
# Log the mixer's rows as apps start/stop playing; --volume sets command-line process rows only
open -n build/MacVolume.app --args --probe --watch 10 [--volume 0.3] --log /tmp/watch.log
# List audio processes grouped by app (helpers under their app)
open -n -W build/MacVolume.app --args --probe --groups --log /tmp/groups.log
# Start a tap, then add/remove a playing process on the running tap
open -n -W build/MacVolume.app --args --probe --pid <pid> --gain 0.3 --update-test --log /tmp/upd.log
# Print the System Audio Recording permission status
open -n build/MacVolume.app --args --probe --permission --log /tmp/perm.log
# Play a tapped process into a given device instead of the default output
open -n -W build/MacVolume.app --args --probe --pid <pid> --output <device uid> --log /tmp/probe.log
# Move a running tap between two devices and back
open -n build/MacVolume.app --args --probe --pid <pid> --move-test --output <uid> --output2 <uid> --log /tmp/move.log
# Change the first device's sample rate and back under a running tap (restores it afterwards)
open -n build/MacVolume.app --args --probe --pid <pid> --rate-test --output <uid> --output2 <uid> --log /tmp/rate.log
# Whole mixer on private settings: saved volume, device moves, stall, wake (<bundle id> must be playing)
open -n build/MacVolume.app --args --probe --mixer-test <bundle id> --output <uid> --output2 <uid> [--other-pid <pid>] [--skip-rate] --log /tmp/mixer.log
# Register the login item, log the result and unregister it
open -n build/MacVolume.app --args --probe --login-item --log /tmp/login.log
```

## Look

The window is a retro hardware skin: gunmetal panels, a scrolling dot-matrix display and segmented
LED sliders (`Skin.swift`). The display holds still while the app is in the background. The logo is
drawn by `scripts/make-icon.py`, which writes `Resources/AppIcon.icns`; rerun it after changing it.
The same script exports the Chrome extension icons at 16, 32, 48 and 128 pixels. Use
`python3 scripts/make-icon.py --chrome-only` to regenerate only those PNGs, then reload the
unpacked extension in Chrome to refresh its toolbar and extension-manager icons.

To check the look without opening the app or touching audio, render the window to PNGs:

```sh
.build/release/MacVolume --probe --render-preview /tmp/mixer
```

## How it works

`AudioProcessMonitor` watches Core Audio's process list. `AppOwner` first uses an executable's
enclosing app bundle (Chrome Helper → Chrome), so a browser launched from an editor still owns
its audio. Shared services such as WebKit GPU use the app responsible for them through the
private `responsibility_get_pid_responsible_for_pid`. `MixerModel` shows one row per app that is
playing and runs one tap per app, covering all its processes, only while that app is away from 100%
or muted. New helpers are added to the running tap as soon as they appear, before they play, so
they never sound at full volume. A tapped app stays tapped while paused.

Boost (toolbar) lets sliders reach 200%; above 100% a soft clipper keeps samples below ±1.

For each app, `ProcessVolumeTap` creates a tap with `.mutedWhenTapped` (the app's normal
output goes silent while we read it), wraps it in a private aggregate device whose main sub-device
is the default output, and in the IO callback copies tap → output multiplied by the gain. Mono
outputs get both channels mixed.

`MixerModel` follows the default output. To change device, a tap builds a complete new route (its
own tap and aggregate), waits for its first IO callback and only then destroys the old one, so the
app is never left unread and playing at full volume. The same move rebuilds every route after wake,
and a 3-second check rebuilds any route whose IO has stopped or retries one that failed to move.

Each app's volume, mute state and the Boost toggle are saved in UserDefaults, by bundle ID.
Command-line processes aren't saved, since their `pid:` keys mean nothing after they exit.

## Sprint 0 results (2026-11-03, MacBook Pro speakers, macOS 27.2)

| Check | Result |
|---|---|
| Gain applied | out/in peak ratio 0.300 at 30%, every second of the run |
| Format | tap 48 kHz stereo Float32 → output 96 kHz; HAL resamples, 512 frames in = 512 out |
| Added delay (device-reported estimate) | ≈ 7 ms |
| CPU, MacVolume | 0.2–0.6% |
| CPU, coreaudiod | 7% → 8% steady state (one-time spike while creating the tap) |
| By ear (voice pitch normal, no clicks) | _pending manual check_ |

## Sprint 1 results (2026-11-03)

| Check | Result |
|---|---|
| Row appears when an app starts playing | ~0.2 s after start |
| Row disappears when the app exits | ~0.1 s after exit; its tap is destroyed with it |
| Setting a row to 30% | creates one tap, no error; app's playback duration unchanged |
| Permission check (private TCC API) | "not determined" after a rebuild, "authorized" once granted |
| Mixer window, icons, mute button, permission screen | _pending manual check_ |

Finding: macOS 27.2 never sends a notification for `kAudioProcessPropertyIsRunningOutput`;
playback start/stop arrives as `kAudioProcessPropertyIsRunning`, so the monitor listens to both.

## Sprint 2 results (2026-11-03)

| Check | Result |
|---|---|
| Grouping on this Mac | Chrome 3 processes → 1 row, Teams 5 → 1, Claude/ChatGPT/VS Code helpers → their app, each WebKit GPU process → its app (Outlook, Google Drive, …) |
| Add a playing process to a running tap | applied immediately, out/in 0.300 |
| Remove a process from a running tap | applied within ~1.5 s |
| Boost 1.8× | out/in 1.800 |
| Soft clipper | identity below 0.9, slope 1.0 at the knee, never exceeds ±1 |
| Browser row control, no full-volume blip on a new tab, boost by ear | _pending manual check_ |

Findings:
- Updating a tap with a process that has already exited fails with `'!obj'`; the mixer then
  rebuilds the tap, and retries a failed app whenever its process set changes.
- With permission "not determined" taps still receive audio and macOS records the grant, so the
  app only shows the permission screen when access is explicitly denied.

## Sprint 3 results (2026-11-04)

Tested on the test devices below, never on the default output, because Chrome was playing through
AirPods throughout. Signal checks read a short window after settling, using a −50 dB tone.

| Check | Result |
|---|---|
| Saved volume at launch | applied 205–217 ms after launch, out/in 0.300 |
| Move between devices (Background Music ↔ Microsoft Teams Audio) | out/in unchanged; main thread blocked 42–48 ms; longest IO gap ≤ 50 ms |
| Device with its own input streams | fixed: out peak 0.0000 → 0.0015 at 50% |
| Mono output | both channels: right-only 0.0030 → 0.0015 mixed |
| Rate change on real hardware (speakers, 96 → 48 → 96 kHz) | signal in every 0.5 s sample, no rebuild needed |
| Stopped IO | detected and rebuilt in 4.0–4.9 s, out/in 0.300 |
| Wake (simulated notification) | routes rebuilt, longest IO gap 42–45 ms, out/in 0.300 |
| Saved settings | volume and Boost persist; 100% entries and `pid:` rows aren't stored |
| Login item | registers ("enabled") and unregisters on this ad-hoc build |
| CPU with 2 taps | MacVolume 0.39–0.44%; coreaudiod 5.9% → 9.5% in one sample, with Chrome also playing |
| Real default-output change, real sleep/wake, AirPods call mode, login at boot, Settings window, mute restored after relaunch | _pending manual check_ |
| No full-volume blip during a device change | _pending manual check_ (a tap reads audio before the mute, so meters can't show it) |

Findings:
- An aggregate's input list holds its output device's own input streams first and the tap last. The
  render used to read from the front, so a device with an input played that instead of the app.
- Destroying an aggregate stops its tap for any other aggregate sharing it: the survivor keeps
  running but reads silence, about 0.5 s later. A peak over a long window hides this. That's why
  each route has its own tap.
- With the Background Music driver at 44.1 kHz (its app not running) a tap can read silence. It
  didn't happen on the speakers or Teams Audio, so this looks like that driver, not MacVolume.
- A tap keeps its output device running even when the app is silent (seen on the speakers), so an
  idle saved app should keep AirPods active while MacVolume runs. In a single check, tapping a
  process that wasn't playing added no sleep assertion.

Known limits: a `coreaudiod` restart isn't handled (relaunch the app), and audio always goes to the
default output, even for an app set to a different device.

