import AppKit
import CoreAudio
import ServiceManagement
import SwiftUI

/// Headless test mode: taps one process for a few seconds and logs what the engine sees.
///
///     MacVolume --probe --pid <pid> [--gain 0.3] [--seconds 5] [--output <device uid>] [--log <file>]
///
/// The README lists the other modes. None of them touch saved volumes or the default output.
enum Probe {
    static func run(arguments: [String]) -> Int32 {
        func value(_ flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        let logURL = value("--log").map(URL.init(fileURLWithPath:))
        if let logURL { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
        func log(_ line: String) {
            print(line)
            if let logURL, let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(Data((line + "\n").utf8))
                try? handle.close()
            }
        }

        if arguments.contains("--permission") {
            log("permission: \(AudioCaptureAccess.status()) (raw \(AudioCaptureAccess.rawPreflight().map(String.init) ?? "nil"))")
            return 0
        }
        if arguments.contains("--groups") {
            let processes = (try? AudioProcess.all()) ?? []
            let groups = Dictionary(grouping: processes) { AppOwner(of: $0).key }
            for (key, members) in groups.sorted(by: { $0.key < $1.key }) {
                let owner = AppOwner(of: members[0])
                let name = ProcessIdentity(pid: owner.pid, bundleID: owner.bundleID).name
                log("\(name) [\(key)]: " + members.map { "\($0.bundleID.isEmpty ? "pid \($0.pid)" : $0.bundleID)\($0.isPlaying ? " ▶︎" : "")" }.joined(separator: ", "))
            }
            return 0
        }
        if let path = value("--render-preview") {
            return MainActor.assumeIsolated { renderPreview(to: path, log: log) }
        }
        if arguments.contains("--login-item") {
            return loginItemTest(log: log)
        }
        if let key = value("--mixer-test"), let first = value("--output"), let second = value("--output2") {
            return mixerTest(key: key, outputs: (first, second), otherPID: value("--other-pid").flatMap(pid_t.init), changeRate: !arguments.contains("--skip-rate"), log: log)
        }
        if let seconds = value("--watch").flatMap(Int.init) {
            return watch(seconds: seconds, volume: value("--volume").flatMap(Double.init), log: log)
        }

        guard let pid = value("--pid").flatMap(pid_t.init) else {
            log("usage: MacVolume --probe --pid <pid> [--gain 0.3] [--seconds 5] [--log <file>]")
            return 2
        }
        let gain = value("--gain").flatMap(Float.init) ?? 0.3
        let seconds = value("--seconds").flatMap(Int.init) ?? 5

        do {
            guard let process = try AudioProcess.all().first(where: { $0.pid == pid }) else {
                log("pid \(pid) is not in Core Audio's process list (has it started playing audio?)")
                return 1
            }
            let name = ProcessIdentity(pid: pid, bundleID: process.bundleID).name
            log("target: \(name) [\(process.bundleID)] pid \(pid), playing: \(process.isPlaying), gain: \(gain)")

            if arguments.contains("--update-test") {
                return updateTest(target: process, gain: gain, log: log)
            }

            if arguments.contains("--rate-test"), let first = value("--output"), let second = value("--output2") {
                return rateTest(process: process, name: name, gain: gain, first: first, second: second, log: log)
            }
            if arguments.contains("--move-test"), let first = value("--output"), let second = value("--output2") {
                return moveTest(process: process, name: name, gain: gain, first: first, second: second, log: log)
            }

            let tap = ProcessVolumeTap(processIDs: [process.id], name: name)
            tap.gain = gain
            try tap.start(outputUID: value("--output"))
            for (label, value) in tap.diagnostics.rows { log("\(label): \(value)") }

            var cpu = CPUMeter()
            for second in 1...seconds {
                RunLoop.current.run(until: Date().addingTimeInterval(1))
                let m = tap.takeMeters()
                let ratio = m.inputPeak > 0 ? m.outputPeak / m.inputPeak : 0
                log(String(format: "t=%ds callbacks=%d in=%dch/%dfr out=%dch/%dfr inPeak=%.4f outPeak=%.4f out/in=%.3f cpu=%.1f%%",
                           second, m.callbacks, m.inputChannels, m.inputFrames, m.outputChannels, m.outputFrames,
                           m.inputPeak, m.outputPeak, ratio, cpu.sample()))
            }
            tap.stop()
            log("stopped")
            return 0
        } catch {
            log("error: \(error.localizedDescription)")
            return 1
        }
    }

    /// Moves a running tap between two devices, sampling the signal every half second.
    private static func moveTest(process: AudioProcess, name: String, gain: Float, first: String, second: String, log: (String) -> Void) -> Int32 {
        do {
            let tap = ProcessVolumeTap(processIDs: [process.id], name: name)
            tap.gain = gain
            try tap.start(outputUID: first)
            func sample(_ stage: String, count: Int) {
                for i in 1...count {
                    _ = tap.takeMeters()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                    let m = tap.takeMeters()
                    log(String(format: "%@ +%.1fs [%@]: inPeak=%.5f outPeak=%.5f callbacks=%d", stage, Double(i) * 0.5,
                               tap.diagnostics.outputDevice, m.inputPeak, m.outputPeak, m.callbacks))
                }
            }
            sample("start", count: 8)
            try tap.moveOutput(to: second)
            sample("moved", count: 6)
            try tap.moveOutput(to: first)
            sample("moved back", count: 6)
            tap.stop()
            return 0
        } catch {
            log("error: \(error.localizedDescription)")
            return 1
        }
    }

    /// Takes a device's sample rate away and back under a running tap, as AirPods do around a
    /// call, then checks whether the signal comes back by itself or after moving the tap.
    private static func rateTest(process: AudioProcess, name: String, gain: Float, first: String, second: String, log: (String) -> Void) -> Int32 {
        do {
            guard let device = AudioObjectID.device(uid: first) else { log("no device \(first)"); return 1 }
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            func rate() -> Double { (try? device.read(kAudioDevicePropertyNominalSampleRate, initial: Float64(0))) ?? 0 }
            func setRate(_ value: Double) -> OSStatus {
                var value = value
                return AudioObjectSetPropertyData(device, &address, 0, nil, 8, &value)
            }
            let original = rate()
            let other = original == 48000 ? 44100.0 : 48000.0
            defer { _ = setRate(original) }

            let tap = ProcessVolumeTap(processIDs: [process.id], name: name)
            tap.gain = gain
            try tap.start(outputUID: first)
            func sample(_ stage: String, count: Int) {
                for i in 1...count {
                    _ = tap.takeMeters()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                    let m = tap.takeMeters()
                    log(String(format: "%@ +%.1fs [%@ %.0f Hz]: inPeak=%.5f outPeak=%.5f cb=%d", stage, Double(i) * 0.5,
                               tap.diagnostics.outputDevice, rate(), m.inputPeak, m.outputPeak, m.callbacks))
                }
            }
            sample("start", count: 4)
            log("set \(other): \(setRate(other))")
            sample("changed", count: 4)
            log("set \(original): \(setRate(original))")
            sample("restored", count: 10)
            try tap.moveOutput(to: first)
            sample("rebuilt, same device", count: 4)
            try tap.moveOutput(to: second)
            sample("moved to other device", count: 4)
            try tap.moveOutput(to: first)
            sample("moved back", count: 4)
            tap.stop()
            return 0
        } catch {
            log("error: \(error.localizedDescription)")
            return 1
        }
    }

    /// Renders the mixer window to PNGs with sample rows, so the look can be checked headlessly.
    @MainActor
    private static func renderPreview(to path: String, log: (String) -> Void) -> Int32 {
        _ = NSApplication.shared
        func row(_ bundleID: String, playing: Bool) -> AppGroup {
            AppGroup(key: bundleID, identity: ProcessIdentity(pid: -1, bundleID: bundleID),
                     processes: [AudioProcess(id: 1, pid: 1, bundleID: bundleID, isPlaying: playing)])
        }
        let rows = [row("com.google.Chrome", playing: true), row("com.microsoft.teams2", playing: false),
                    row("com.apple.Music", playing: true), row("net.whatsapp.WhatsApp", playing: true)]
        let settings = ["com.google.Chrome": VolumeSetting(volume: 0.3),
                        "com.microsoft.teams2": VolumeSetting(volume: 0.8, isMuted: true),
                        "com.apple.Music": VolumeSetting(volume: 1),
                        "net.whatsapp.WhatsApp": VolumeSetting(volume: 1.6)]
        let states: [(String, MixerModel)] = [
            ("normal", MixerModel(previewRows: rows, settings: settings.mapValues { var s = $0; s.volume = min(s.volume, 1); return s }, boostEnabled: false, outputName: "Roger’s AirPods Pro #2")),
            ("boost", MixerModel(previewRows: rows, settings: settings, boostEnabled: true, outputName: "MacBook Pro Speakers")),
            ("empty", MixerModel(previewRows: [], settings: [:], boostEnabled: false, outputName: "MacBook Pro Speakers")),
        ]
        for (name, model) in states {
            let size = NSSize(width: 480, height: 340)
            let view = NSHostingView(rootView: MixerView(model: model).frame(width: size.width, height: size.height))
            view.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 1 }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let file = "\(path)-\(name).png"
            FileManager.default.createFile(atPath: file, contents: bitmap.representation(using: .png, properties: [:]))
            log("wrote \(file)")
        }
        return 0
    }

    /// Registers the login item, logs the result and always unregisters it again.
    private static func loginItemTest(log: (String) -> Void) -> Int32 {
        func status() -> String {
            switch SMAppService.mainApp.status {
            case .notRegistered: "not registered"
            case .enabled: "enabled"
            case .requiresApproval: "requires approval"
            case .notFound: "not found"
            @unknown default: "unknown"
            }
        }
        log("before: \(status())")
        do { try SMAppService.mainApp.register() } catch { log("register failed: \(error.localizedDescription)") }
        log("after register: \(status())")
        do { try SMAppService.mainApp.unregister() } catch { log("unregister failed: \(error.localizedDescription)") }
        log("after unregister: \(status())")
        return 0
    }

    /// Runs the mixer end to end on a private settings suite, with its output pinned to test
    /// devices, so neither the user's saved volumes nor the system default output are touched.
    /// `key` must be the bundle ID of a test app that is already playing.
    private static func mixerTest(key: String, outputs: (String, String), otherPID: pid_t?, changeRate: Bool, log: @escaping (String) -> Void) -> Int32 {
        MainActor.assumeIsolated { runMixerTest(key: key, outputs: outputs, otherPID: otherPID, changeRate: changeRate, log: log) }
    }

    @MainActor
    private static func runMixerTest(key: String, outputs: (String, String), otherPID: pid_t?, changeRate: Bool, log: @escaping (String) -> Void) -> Int32 {
        let suite = "com.rogerleite.MacVolume.probe"
        guard let defaults = UserDefaults(suiteName: suite) else { return 1 }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        SavedSettings.save([key: VolumeSetting(volume: 0.3)], to: defaults)

        func run(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

        let launched = Date()
        let mixer = MixerModel(defaults: defaults, pinnedOutputUID: outputs.0)
        log(String(format: "mixer init took %.0f ms, taps=%d", Date().timeIntervalSince(launched) * 1000, mixer.activeTapCount))
        while mixer.activeTapCount == 0, Date().timeIntervalSince(launched) < 8 { run(0.01) }
        log(String(format: "saved volume applied %.0f ms after launch, taps=%d", Date().timeIntervalSince(launched) * 1000, mixer.activeTapCount))

        func measure(_ stage: String) {
            // Settle first, then read a short window: a long peak would hide audio dying midway.
            run(2)
            _ = mixer.tapMeters(for: key)
            run(0.4)
            guard let m = mixer.tapMeters(for: key) else { return log("\(stage): no tap") }
            let d = mixer.tapDiagnostics(for: key)
            let playing = mixer.rows.first { $0.key == key }?.isPlaying ?? false
            log(String(format: "%@: output=%@ in=%dch out=%dch inPeak=%.5f outPeak=%.5f out/in=%.3f targetPlaying=%@ error=%@",
                       stage, d?.outputDevice ?? "?", m.inputChannels, m.outputChannels, m.inputPeak, m.outputPeak,
                       m.inputPeak > 0 ? m.outputPeak / m.inputPeak : 0, playing ? "yes" : "NO", mixer.error ?? "none"))
        }
        /// Longest stretch without IO callbacks while `action` runs and for a moment after.
        func longestGap(_ action: () -> Void) -> Double {
            var last = mixer.tapMeters(for: key)?.callbacks ?? 0
            var lastChange = Date()
            var longest = 0.0
            action()
            let end = Date().addingTimeInterval(2.5)
            while Date() < end {
                run(0.002)
                let count = mixer.tapMeters(for: key)?.callbacks ?? 0
                if count != last { longest = max(longest, Date().timeIntervalSince(lastChange)); last = count; lastChange = Date() }
            }
            return longest * 1000
        }

        measure("saved volume, first output")

        var moveMs = 0.0
        let gap = longestGap {
            let start = Date()
            mixer.route(to: outputs.1)
            moveMs = Date().timeIntervalSince(start) * 1000
        }
        log(String(format: "move to second output: blocked %.0f ms, longest IO gap %.0f ms", moveMs, gap))
        measure("after move")
        mixer.route(to: outputs.0)
        run(0.5)
        measure("moved back")

        // Sample-rate change under a running tap, restored straight after.
        if changeRate, let device = AudioObjectID.device(uid: outputs.0) {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            let original = (try? device.read(kAudioDevicePropertyNominalSampleRate, initial: Float64(0))) ?? 0
            var changed = original == 48000 ? 44100.0 : 48000.0
            let status = AudioObjectSetPropertyData(device, &address, 0, nil, 8, &changed)
            log("sample rate \(original) -> \(changed): status \(status)")
            run(1)
            measure("after rate change")
            var restored = original
            AudioObjectSetPropertyData(device, &address, 0, nil, 8, &restored)
            run(1)
            measure("rate restored")
        }

        let stalled = Date()
        mixer.simulateStall(for: key)
        let before = mixer.tapMeters(for: key)?.callbacks ?? 0
        var recovered = false
        while Date().timeIntervalSince(stalled) < 12 {
            run(0.05)
            let now = mixer.tapMeters(for: key)?.callbacks ?? 0
            if now > before + 20 { recovered = true; break }
        }
        log(String(format: "stall: %@ after %.1f s", recovered ? "recovered" : "NOT recovered", Date().timeIntervalSinceReferenceDate - stalled.timeIntervalSinceReferenceDate))
        measure("after stall")

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
        let wakeGap = longestGap {}
        log(String(format: "simulated wake: longest IO gap %.0f ms", wakeGap))
        measure("after simulated wake")

        if let otherPID, let other = mixer.rows.first(where: { $0.processes.contains { $0.pid == otherPID } }) {
            mixer.setVolume(0.4, for: other)
            log("second row \(other.key) at 40%: taps=\(mixer.activeTapCount)")
            var cpu = CPUMeter()
            run(10)
            log(String(format: "CPU with %d taps over 10 s: %.2f%%", mixer.activeTapCount, cpu.sample()))
            let saved = SavedSettings.load(from: defaults)
            log("saved keys: \(saved.keys.sorted()) (pid rows must be absent)")
        }

        mixer.boostEnabled = true
        log("boost saved: \(SavedSettings.loadBoost(from: defaults))")
        if let row = mixer.rows.first(where: { $0.key == key }) {
            mixer.setVolume(0.55, for: row)
            log("after change, saved: \(SavedSettings.load(from: defaults)[key].map { String($0.volume) } ?? "none")")
            mixer.setVolume(1, for: row)
            log("back at 100%: saved entry present=\(SavedSettings.load(from: defaults)[key] != nil)")
        }
        return 0
    }

    /// Starts a tap on an idle process, then adds the playing target to the running tap and
    /// removes it again, logging meters at each stage.
    private static func updateTest(target: AudioProcess, gain: Float, log: (String) -> Void) -> Int32 {
        do {
            guard let idle = try AudioProcess.all().first(where: { !$0.isPlaying && $0.id != target.id && kill($0.pid, 0) == 0 }) else {
                log("no idle process to start the tap with")
                return 1
            }
            let tap = ProcessVolumeTap(processIDs: [idle.id], name: "update test")
            tap.gain = gain
            try tap.start()
            func measure(_ stage: String) {
                _ = tap.takeMeters()
                RunLoop.current.run(until: Date().addingTimeInterval(1.5))
                let m = tap.takeMeters()
                log(String(format: "%@: inPeak=%.4f outPeak=%.4f out/in=%.3f",
                           stage, m.inputPeak, m.outputPeak, m.inputPeak > 0 ? m.outputPeak / m.inputPeak : 0))
            }
            measure("idle process only")
            try tap.setProcesses([idle.id, target.id])
            measure("target added")
            try tap.setProcesses([idle.id])
            measure("target removed")
            measure("target removed, +1.5 s")
            tap.stop()
            return 0
        } catch {
            log("error: \(error.localizedDescription)")
            return 1
        }
    }

    /// Logs the mixer's rows every time they change, for `seconds` seconds.
    /// With `volume`, every command-line process row (never a real app) is set to that volume,
    /// like dragging its slider.
    private static func watch(seconds: Int, volume: Double?, log: @escaping (String) -> Void) -> Int32 {
        MainActor.assumeIsolated {
            let mixer = MixerModel(defaults: nil)
            let start = Date()
            let subscription = mixer.$rows.sink { rows in
                let names = rows.map { "\($0.identity.name) [\($0.processes.count) proc]\($0.isPlaying ? " ▶︎" : "")" }
                log(String(format: "t=%.1fs epoch=%.1f taps=%d rows: ", Date().timeIntervalSince(start), Date().timeIntervalSince1970, mixer.activeTapCount)
                    + (names.isEmpty ? "(none)" : names.joined(separator: ", ")))
                if let volume {
                    for row in rows where row.key.hasPrefix("pid:") && mixer.setting(for: row).volume != volume {
                        DispatchQueue.main.async {
                            mixer.setVolume(volume, for: row)
                            log("set \(row.identity.name) to \(volume): taps=\(mixer.activeTapCount) error=\(mixer.error ?? "none")")
                        }
                    }
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(TimeInterval(seconds)))
            subscription.cancel()
        }
        return 0
    }
}
