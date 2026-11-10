# Engineering log

Measurements recorded while building the Core Audio tap engine. Later validation records
(per release) live in the other files in this folder.

## Sprint 0 results (2026-11-03, MacBook Pro speakers, macOS 27.2)

| Check | Result |
|---|---|
| Gain applied | out/in peak ratio 0.300 at 30%, every second of the run |
| Format | tap 48 kHz stereo Float32 → output 96 kHz; HAL resamples, 512 frames in = 512 out |
| Added delay (device-reported estimate) | ≈ 7 ms |
| CPU, WinMix | 0.2–0.6% |
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
| CPU with 2 taps | WinMix 0.39–0.44%; coreaudiod 5.9% → 9.5% in one sample, with Chrome also playing |
| Real default-output change, real sleep/wake, AirPods call mode, login at boot, Settings window, mute restored after relaunch | _pending manual check_ |
| No full-volume blip during a device change | _pending manual check_ (a tap reads audio before the mute, so meters can't show it) |

Findings:
- An aggregate's input list holds its output device's own input streams first and the tap last. The
  render used to read from the front, so a device with an input played that instead of the app.
- Destroying an aggregate stops its tap for any other aggregate sharing it: the survivor keeps
  running but reads silence, about 0.5 s later. A peak over a long window hides this. That's why
  each route has its own tap.
- With the Background Music driver at 44.1 kHz (its app not running) a tap can read silence. It
  didn't happen on the speakers or Teams Audio, so this looks like that driver, not WinMix.
- A tap keeps its output device running even when the app is silent (seen on the speakers), so an
  idle saved app should keep AirPods active while WinMix runs. In a single check, tapping a
  process that wasn't playing added no sleep assertion.

Known limit: a `coreaudiod` restart isn't handled (relaunch the app).
