# Development notes

## Tests

```sh
swift test                                            # Swift unit tests
node --test Tests/ChromeExtension/*.test.mjs          # Chrome extension tests
python3 -m unittest discover -s Tests -p 'test_*.py'  # native-bridge installer tests
```

## Ad-hoc signing and the audio permission

The app is ad-hoc signed, so each rebuild resets the **System Audio Recording** grant: the first
tap after a rebuild takes 3–4 s to start while macOS re-grants access. Later launches start at once.
When testing, quit the running app and do one throwaway tap run after every rebuild: runs that built
a second tap during that window, or started while the old build was still running, hung.

## Probe modes

Headless probe modes (results go to the `--log` file):

```sh
# Tap one process and log levels, latency and CPU
open -n -W build/WinMix.app --args --probe --pid <pid> --gain 0.3 --seconds 5 --log /tmp/probe.log
# Log the mixer's rows as apps start/stop playing; --volume sets command-line process rows only
open -n build/WinMix.app --args --probe --watch 10 [--volume 0.3] --log /tmp/watch.log
# List audio processes grouped by app (helpers under their app)
open -n -W build/WinMix.app --args --probe --groups --log /tmp/groups.log
# Start a tap, then add/remove a playing process on the running tap
open -n -W build/WinMix.app --args --probe --pid <pid> --gain 0.3 --update-test --log /tmp/upd.log
# Print the System Audio Recording permission status
open -n build/WinMix.app --args --probe --permission --log /tmp/perm.log
# Play a tapped process into a given device instead of the default output
open -n -W build/WinMix.app --args --probe --pid <pid> --output <device uid> --log /tmp/probe.log
# Move a running tap between two devices and back
open -n build/WinMix.app --args --probe --pid <pid> --move-test --output <uid> --output2 <uid> --log /tmp/move.log
# Change the first device's sample rate and back under a running tap (restores it afterwards)
open -n build/WinMix.app --args --probe --pid <pid> --rate-test --output <uid> --output2 <uid> --log /tmp/rate.log
# Whole mixer on private settings: saved volume, device moves, stall, wake (<bundle id> must be playing)
open -n build/WinMix.app --args --probe --mixer-test <bundle id> --output <uid> --output2 <uid> [--other-pid <pid>] [--skip-rate] --log /tmp/mixer.log
# Register the login item, log the result and unregister it
open -n build/WinMix.app --args --probe --login-item --log /tmp/login.log
```

## UI previews without audio

```sh
.build/release/WinMix --probe --render-preview /tmp/mixer
```

Renders every appearance plus the menu-bar panel in light/dark, empty, denied, muted, Boost,
output fallback, error and many-app states. For native UI diagnostics with fake app rows, no sockets,
no audio and no saved-setting writes, launch with `--preview-ui`; its **Preview → Open Mini Mixer
Preview** command opens the exact panel in a regular diagnostic window. `--preview-many` and
`--preview-denied` select additional fixtures. Browser registration in that mode goes to a disposable
directory; `--preview-host-directory PATH` chooses an explicit test directory.

## Icons

`scripts/make-icon.py` draws the app icon into `Resources/AppIcon.icns` (`--style ceramic` exports the
alternative speaker-cone icon) and the Chrome extension icons at 16, 32, 48 and 128 px.
`python3 scripts/make-icon.py --chrome-only` regenerates only the extension PNGs; reload the unpacked
extension afterwards.

## Developer bridge installer

The setup sheet in the app is the normal way to connect Chrome. The command-line installer remains
available for development:

```sh
python3 scripts/install-chrome-bridge.py EXTENSION_ID --app "$PWD/build/WinMix.app"
python3 scripts/uninstall-chrome-bridge.py
```
