# MacVolume

Per-app volume control for macOS 14.4+, built on Core Audio process taps.

## Build and run

```sh
./scripts/build-app.sh
open build/MacVolume.app
```

On first use macOS asks for **System Audio Recording** access. If the meters stay at zero,
check System Settings → Privacy & Security → Screen & System Audio Recording.
The app is ad-hoc signed, so a rebuild may make macOS ask again.

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
```

## How it works

`AudioProcessMonitor` watches Core Audio's process list. `AppOwner` groups each process under the
app responsible for it (Chrome Helper → Chrome, WebKit GPU → the app it renders for), using the
private `responsibility_get_pid_responsible_for_pid`. `MixerModel` shows one row per app that is
playing and runs one tap per app, covering all its processes, only while that app is away from 100%
or muted. New helpers are added to the running tap as soon as they appear, before they play, so
they never sound at full volume. A tapped app stays tapped while paused.

Boost (toolbar) lets sliders reach 200%; above 100% a soft clipper keeps samples below ±1.

For each app, `ProcessVolumeTap` creates a tap with `.mutedWhenTapped` (the app's normal
output goes silent while we read it), wraps it in a private aggregate device whose main sub-device
is the default output, and in the IO callback copies tap → output multiplied by the gain.

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
