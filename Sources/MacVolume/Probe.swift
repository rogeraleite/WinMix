import Foundation

/// Headless test mode: taps one process for a few seconds and logs what the engine sees.
///
///     MacVolume --probe --pid <pid> [--gain 0.3] [--seconds 5] [--log <file>]
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

            let tap = ProcessVolumeTap(processIDs: [process.id], name: name)
            tap.gain = gain
            try tap.start()
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
            let mixer = MixerModel()
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
