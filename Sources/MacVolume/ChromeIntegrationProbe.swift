import AppKit
import ChromeSupport
import CoreAudio

/// Diagnostic JSON-line interface. Only touches the disposable Chrome for Testing group.
@MainActor
enum ChromeIntegrationProbe {
    private static let browserKey = "com.google.chrome.for.testing"

    static func run(outputUID: String) -> Int32 {
        guard AudioObjectID.device(uid: outputUID) != nil else {
            fputs("Unknown diagnostic output UID.\n", stderr); return 2
        }
        guard ProcessInfo.processInfo.environment["MACVOLUME_CHROME_SOCKET"] != nil else {
            fputs("Set MACVOLUME_CHROME_SOCKET to a private diagnostic socket.\n", stderr); return 2
        }
        _ = NSApplication.shared
        let chrome = ChromeTabModel()
        let mixer = MixerModel(defaults: nil, pinnedOutputUID: outputUID)
        defer { chrome.stop(); mixer.stopAll() }
        var finished = false

        func snapshot() -> [String: Any] {
            let tabs = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(chrome.tabs))) ?? []
            return ["connected": chrome.connected, "tabs": tabs, "pending": chrome.pending.count,
                    "chromeError": chrome.error ?? "", "status": chrome.status,
                    "mixerError": mixer.error ?? "", "output": mixer.outputName,
                    "browserFound": mixer.rows.contains { $0.key == browserKey },
                    "audioGroups": mixer.rows.filter { $0.processes.contains { $0.bundleID.lowercased().contains("chrome") } }
                        .map { ["key": $0.key, "processBundles": $0.processes.map(\.bundleID)] },
                    "routeGeneration": mixer.tapGeneration(for: browserKey)]
        }
        func reply(_ request: [String: Any], _ values: [String: Any] = [:]) {
            var response = snapshot().merging(values) { _, new in new }
            response["requestID"] = request["requestID"] ?? ""
            guard let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]) else { return }
            FileHandle.standardOutput.write(data + Data([10]))
        }
        func handle(_ command: [String: Any]) {
            do {
                switch command["action"] as? String {
                case "status": break
                case "master":
                    guard let gain = command["gain"] as? Double, gain.isFinite, (0...1).contains(gain),
                          let row = mixer.rows.first(where: { $0.key == browserKey }) else {
                        throw SpikeError("No test browser row or invalid gain.")
                    }
                    fputs("Native master: creating tap, permission=\(AudioCaptureAccess.status())\n", stderr)
                    mixer.setVolume(gain, for: row)
                    fputs("Native master: tap request returned\n", stderr)
                case "tab":
                    guard let id = command["tabID"] as? Int,
                          let tab = chrome.tabs.first(where: { $0.id == id && ($0.controlled || $0.canMute == true) }),
                          chrome.connected, chrome.pending[id] == nil else { throw SpikeError("Tab is unavailable or awaiting confirmation.") }
                    if let volume = command["volume"] as? Double, volume.isFinite, (0...1).contains(volume), command["muted"] == nil {
                        guard tab.controlled else { throw SpikeError("Volume unavailable for this player.") }
                        chrome.setVolume(volume, for: tab)
                    } else if let muted = command["muted"] as? Bool, command["volume"] == nil {
                        if muted != tab.muted { chrome.toggleMute(tab) }
                    } else { throw SpikeError("Supply either volume or muted for a tab.") }
                case "meters":
                    guard mixer.tapMeters(for: browserKey) != nil else { throw SpikeError("No native test-browser tap. Set master below 100% first.") }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        guard let meter = mixer.tapMeters(for: browserKey) else {
                            reply(command, ["error": "Native tap disappeared."]); return
                        }
                        reply(command, ["inputPeak": meter.inputPeak, "outputPeak": meter.outputPeak,
                                        "callbacks": meter.callbacks,
                                        "ratio": meter.inputPeak > 0 ? meter.outputPeak / meter.inputPeak : 0])
                    }
                    return
                case "route":
                    guard let uid = command["uid"] as? String, AudioObjectID.device(uid: uid) != nil else { throw SpikeError("Unknown output UID.") }
                    mixer.route(to: uid)
                case "stall": mixer.simulateStall(for: browserKey)
                case "sleep": NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: NSWorkspace.shared)
                case "wake": NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
                case "stop": finished = true
                default: throw SpikeError("Unknown diagnostic action.")
                }
                reply(command)
            } catch { reply(command, ["error": error.localizedDescription]) }
        }

        // All model mutations are dispatched to the main thread; stdin may block off-thread.
        DispatchQueue.global(qos: .utility).async {
            while let line = readLine() {
                guard line.utf8.count <= 16_384,
                      let command = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                DispatchQueue.main.async { handle(command) }
            }
            DispatchQueue.main.async { finished = true }
        }
        let deadline = Date().addingTimeInterval(300)
        while !finished && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        return finished ? 0 : 1
    }
}
