import AppKit
import Combine
import CoreAudio

struct VolumeSetting: Equatable, Codable {
    var volume: Double = 1
    var isMuted = false
    var outputUID: String?
    var outputName: String?

    /// At exactly 100% and unmuted the app plays directly, without a tap.
    var isDefault: Bool { volume == 1 && !isMuted && outputUID == nil }
    var gain: Float { isMuted ? 0 : Float(volume) }
}

/// Per-app settings kept between launches, by bundle ID. Command-line processes are skipped:
/// their "pid:" keys mean nothing after they exit.
enum SavedSettings {
    private static let settingsKey = "volumeSettings"
    private static let boostKey = "boostEnabled"

    static func load(from defaults: UserDefaults) -> [String: VolumeSetting] {
        defaults.data(forKey: settingsKey)
            .flatMap { try? JSONDecoder().decode([String: VolumeSetting].self, from: $0) } ?? [:]
    }

    static func save(_ settings: [String: VolumeSetting], to defaults: UserDefaults) {
        let saved = settings.filter { !$0.key.hasPrefix("pid:") && !$0.value.isDefault }
        defaults.set(try? JSONEncoder().encode(saved), forKey: settingsKey)
    }

    static func loadBoost(from defaults: UserDefaults) -> Bool { defaults.bool(forKey: boostKey) }
    static func saveBoost(_ enabled: Bool, to defaults: UserDefaults) { defaults.set(enabled, forKey: boostKey) }
}

/// One row per app that is playing (or that we are already controlling). An app gets a tap
/// covering all of its processes only while it is set away from 100% or muted.
@MainActor
final class MixerModel: ObservableObject {
    static let boostMaximum = 2.0

    @Published private(set) var rows: [AppGroup] = []
    @Published private(set) var settings: [String: VolumeSetting] = [:]
    @Published var boostEnabled = false {
        didSet {
            if !boostEnabled { clampToHundredPercent() }
            if let defaults { SavedSettings.saveBoost(boostEnabled, to: defaults) }
        }
    }
    @Published var error: String?
    @Published private(set) var outputName = ""
    @Published private(set) var outputDevices: [AudioOutputDevice] = []
    @Published private(set) var routingFailures: [String: String] = [:]
    @Published private(set) var pendingOutputs: [String: String] = [:]

    var maximumVolume: Double { boostEnabled ? Self.boostMaximum : 1 }
    var activeTapCount: Int { taps.count }

    private let monitor = AudioProcessMonitor()
    private var groups: [String: AppGroup] = [:]
    private var owners: [AudioObjectID: AppOwner] = [:]
    private var identities: [String: ProcessIdentity] = [:]
    private var taps: [String: any MixerAudioTap] = [:]
    /// Apps whose tap failed to start, with the processes it was tried with. Retried when the
    /// app's processes change (e.g. a process exited mid-update) or the user changes the setting.
    private var failedTaps: [String: Set<AudioObjectID>] = [:]
    private var subscriptions: Set<AnyCancellable> = []
    private let defaults: UserDefaults?
    /// The device taps play into. Follows the system default unless `pinnedOutput` is set.
    private var outputUID: String?
    private let pinnedOutput: Bool
    private let runtime: MixerRuntime
    private var outputWatcher: AudioOutputWatcher?
    private var isAsleep = false

    /// Sample data for rendering the UI headlessly; touches no audio.
    init(previewRows: [AppGroup], settings: [String: VolumeSetting], boostEnabled: Bool, outputName: String,
         outputDevices: [AudioOutputDevice] = []) {
        defaults = nil
        pinnedOutput = true
        runtime = MixerRuntime(outputs: { outputDevices }, defaultOutput: { nil }, observesSystem: false)
        rows = previewRows
        self.settings = settings
        self.boostEnabled = boostEnabled
        self.outputName = outputName
        self.outputDevices = outputDevices
        outputUID = outputDevices.first(where: { $0.name == outputName })?.uid
    }

    /// - Parameters:
    ///   - defaults: where settings persist; nil keeps them in memory, so headless tests can
    ///     neither read the user's saved volumes (which would tap real apps) nor overwrite them.
    ///   - pinnedOutputUID: plays into this device instead of following the system default.
    init(defaults: UserDefaults? = .standard, pinnedOutputUID: String? = nil, runtime: MixerRuntime = MixerRuntime()) {
        self.defaults = defaults
        self.runtime = runtime
        pinnedOutput = pinnedOutputUID != nil
        outputUID = pinnedOutputUID ?? runtime.defaultOutput()
        outputDevices = runtime.outputs() ?? []
        if let defaults {
            settings = SavedSettings.load(from: defaults)
            boostEnabled = SavedSettings.loadBoost(from: defaults)
        }
        updateOutputName()
        guard runtime.observesSystem else { return }

        monitor.$processes
            .sink { [weak self] in self?.reconcile($0) }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.stopAll() }
            .store(in: &subscriptions)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in self?.isAsleep = true }
            .store(in: &subscriptions)
        workspace.publisher(for: NSWorkspace.didWakeNotification)
            .delay(for: .seconds(1), scheduler: DispatchQueue.main)  // let audio devices come back first
            .sink { [weak self] _ in self?.didWake() }
            .store(in: &subscriptions)
        // A dead device or a stuck IO thread sends no notification, so check on them.
        Timer.publish(every: 3, tolerance: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.refreshOutputs(); self?.checkRoutes(); self?.retryFailedTaps() }
            .store(in: &subscriptions)
        outputWatcher = AudioOutputWatcher { [weak self] in
            MainActor.assumeIsolated { self?.refreshOutputs() }
        }
        monitor.start()
    }

    func refreshOutputs() {
        let inventory = runtime.outputs() ?? outputDevices
        let systemOutput = pinnedOutput ? outputUID : runtime.defaultOutput()
        guard inventory != outputDevices || systemOutput != outputUID else { return }
        outputDevices = inventory
        outputUID = systemOutput
        updateOutputName()
        checkRoutes()
        retryFailedTaps()
    }

    /// Sends every tap to `uid`. Also how headless tests switch a pinned mixer between devices.
    func route(to uid: String) {
        outputUID = uid
        updateOutputName()
        checkRoutes()
        retryFailedTaps()
    }

    /// Rebuilds every route: a device can come back from sleep looking fine but no longer playing.
    private func didWake() {
        isAsleep = false
        refreshOutputs()
        updateOutputName()
        checkRoutes(rebuildAll: true)
        retryFailedTaps()
    }

    /// Moves taps that aren't on the current output or have stopped running. A move that fails
    /// keeps the old route and is retried on the next timer tick.
    func checkRoutes(rebuildAll: Bool = false) {
        guard !isAsleep else { return }
        for (key, tap) in taps {
            if let group = groups[key], !updateProcesses(on: tap, for: group) { continue }
            let isStalled = tap.checkStalled()
            let destination = effectiveOutputUID(for: key)
            synchronizeRouteState(for: key, tap: tap, destination: destination)
            guard let destination, tap.pendingOutputUID != destination else { continue }
            guard rebuildAll || isStalled || tap.outputUID != destination
                    || tap.pendingOutputUID != nil || tap.routeFailure != nil else { continue }
            move(tap, for: key, to: destination)
        }
    }

    private func synchronizeRouteState(for key: String, tap: any MixerAudioTap, destination: String?) {
        if pendingOutputs[key] != tap.pendingOutputUID { pendingOutputs[key] = tap.pendingOutputUID }
        if let failure = tap.routeFailure {
            recordFailure(key, failure)
        } else if tap.pendingOutputUID == nil, let destination, tap.outputUID == destination {
            clearFailure(key)
        }
    }

    private func move(_ tap: any MixerAudioTap, for key: String, to destination: String) {
        do {
            try tap.moveOutput(to: destination)
            synchronizeRouteState(for: key, tap: tap, destination: destination)
            objectWillChange.send()
        } catch {
            if pendingOutputs[key] != tap.pendingOutputUID { pendingOutputs[key] = tap.pendingOutputUID }
            recordFailure(key, "Couldn't move \(groups[key]?.identity.name ?? key) to \(deviceName(destination)): \(error.localizedDescription)")
        }
    }

    private func updateProcesses(on tap: any MixerAudioTap, for group: AppGroup) -> Bool {
        guard Set(tap.processIDs) != Set(group.processIDs) else { return true }
        do {
            try tap.setProcesses(group.processIDs)
            return true
        } catch {
            recordFailure(group.key, "Couldn't update \(group.identity.name)'s audio processes: \(error.localizedDescription)")
            return false
        }
    }

    private func updateOutputName() {
        outputName = outputUID.map(deviceName) ?? ""
    }

    private func retryFailedTaps() {
        guard !isAsleep, !failedTaps.isEmpty else { return }
        let keys = Set(failedTaps.keys)
        failedTaps.removeAll()
        for group in groups.values where keys.contains(group.key) {
            apply(settings[group.key] ?? VolumeSetting(), to: group)
        }
    }

    private func effectiveOutputUID(for key: String) -> String? {
        if let selected = settings[key]?.outputUID, outputDevices.contains(where: { $0.uid == selected }) { return selected }
        return outputUID
    }

    private func deviceName(_ uid: String) -> String {
        outputDevices.first(where: { $0.uid == uid })?.name ?? "Unavailable output"
    }

    func outputLabel(for group: AppGroup) -> String {
        let setting = setting(for: group)
        let selected = setting.outputUID
        let name = selected.map { uid in outputDevices.first(where: { $0.uid == uid })?.name ?? setting.outputName ?? "Saved output" }
        if routingFailures[group.key] != nil { return "\(name ?? "System default") · retrying" }
        if let pending = pendingOutputs[group.key] {
            return "\(name ?? "System default") · connecting to \(deviceName(pending))"
        }
        if let selected, !outputDevices.contains(where: { $0.uid == selected }) {
            return "\(name ?? "Saved output") disconnected · \(outputName.isEmpty ? "no system output" : outputName)"
        }
        return name ?? "System default\(outputName.isEmpty ? "" : " · \(outputName)")"
    }

    func outputHelp(for group: AppGroup) -> String {
        var text = "Output: \(outputLabel(for: group))."
        if let failure = routingFailures[group.key] {
            let actual = taps[group.key]?.outputUID.map(deviceName) ?? "the app's normal output"
            text += " Still using \(actual). \(failure) WinMix will retry automatically."
        } else if let pending = pendingOutputs[group.key] {
            let actual = taps[group.key]?.outputUID.map(deviceName) ?? "the app's normal output"
            text += " Connecting to \(deviceName(pending)). Still using \(actual) until the new output starts."
        }
        if group.key == "com.google.Chrome" { text += " All Chrome tabs share this output." }
        if setting(for: group).outputUID != nil { text += " If this device disconnects, use the Mac's system output and return when it reconnects." }
        return text
    }

    func setOutput(_ uid: String?, for group: AppGroup) {
        // Only live menu devices (or System default) may be chosen. Saved missing devices
        // remain in settings for automatic return, but cannot be newly selected.
        guard uid == nil || outputDevices.contains(where: { $0.uid == uid }) else { return }
        update(group.key) {
            $0.outputUID = uid
            $0.outputName = uid.flatMap { selected in outputDevices.first(where: { $0.uid == selected })?.name }
        }
    }

    private func recordFailure(_ key: String, _ message: String) {
        if routingFailures[key] != message { routingFailures[key] = message; error = message }
    }

    private func clearFailure(_ key: String) {
        guard let old = routingFailures.removeValue(forKey: key) else { return }
        if error == old { error = routingFailures.values.sorted().first }
    }

    func setting(for group: AppGroup) -> VolumeSetting {
        settings[group.key] ?? VolumeSetting()
    }

    func setVolume(_ volume: Double, for group: AppGroup) {
        // Snap to 100% so "untouched" is easy to hit when the slider goes past it.
        let volume = abs(volume - 1) < 0.03 ? 1 : volume
        update(group.key) {
            $0.volume = volume
            $0.isMuted = false
        }
    }

    func toggleMute(_ group: AppGroup) {
        update(group.key) { $0.isMuted.toggle() }
    }

    private func update(_ key: String, _ change: (inout VolumeSetting) -> Void) {
        var setting = settings[key] ?? VolumeSetting()
        change(&setting)
        settings[key] = setting
        if let defaults { SavedSettings.save(settings, to: defaults) }
        failedTaps[key] = nil
        if let group = groups[key] { apply(setting, to: group) }
    }

    private func clampToHundredPercent() {
        for (key, setting) in settings where setting.volume > 1 {
            update(key) { $0.volume = 1 }
        }
    }

    func reconcile(_ processes: [AudioProcess]) {
        let alive = Set(processes.map(\.id))
        owners = owners.filter { alive.contains($0.key) }

        var members: [String: (owner: AppOwner, processes: [AudioProcess])] = [:]
        for process in processes {
            let owner = owners[process.id] ?? AppOwner(of: process)
            owners[process.id] = owner
            members[owner.key, default: (owner, [])].processes.append(process)
        }
        groups = members.mapValues { member in
            let key = member.owner.key
            let identity = identities[key] ?? ProcessIdentity(pid: member.owner.pid, bundleID: member.owner.bundleID)
            identities[key] = identity
            return AppGroup(key: key, identity: identity, processes: member.processes)
        }
        identities = identities.filter { groups[$0.key] != nil }

        for (key, tap) in taps where groups[key] == nil {
            tap.stop()
            taps[key] = nil
        }
        // A failed start has no active tap, so clear vanished-app failures independently.
        for key in routingFailures.keys where groups[key] == nil {
            clearFailure(key)
        }
        for key in pendingOutputs.keys where groups[key] == nil { pendingOutputs[key] = nil }
        // A pid can be reused, and a new process must not inherit an old one's volume.
        for key in settings.keys where key.hasPrefix("pid:") && groups[key] == nil {
            settings[key] = nil
        }
        failedTaps = failedTaps.filter { groups[$0.key].map { Set($0.processIDs) } == $0.value }
        for group in groups.values {
            apply(settings[group.key] ?? VolumeSetting(), to: group)
        }

        // Rows only change here, not on slider moves, so a row never vanishes mid-drag.
        rows = groups.values
            .filter { $0.isPlaying || taps[$0.key] != nil }
            .sorted { $0.identity.name.localizedCaseInsensitiveCompare($1.identity.name) == .orderedAscending }
    }

    private func apply(_ setting: VolumeSetting, to group: AppGroup) {
        if setting.isDefault {
            taps.removeValue(forKey: group.key)?.stop()
            pendingOutputs[group.key] = nil
            clearFailure(group.key)
            return
        }
        guard !isAsleep else { return }
        if let tap = taps[group.key] {
            tap.gain = setting.gain
            // Retain the working route if its helper update/replacement fails.
            // The health check retries the process list without releasing mute.
            guard updateProcesses(on: tap, for: group) else { return }
            if taps[group.key] != nil {
                if let destination = effectiveOutputUID(for: group.key) {
                    synchronizeRouteState(for: group.key, tap: tap, destination: destination)
                    if tap.pendingOutputUID != destination,
                       tap.outputUID != destination || tap.pendingOutputUID != nil || tap.routeFailure != nil {
                        move(tap, for: group.key, to: destination)
                    }
                }
                return
            }
        }
        guard failedTaps[group.key] == nil else { return }

        // Tap every process of the app, playing or not, so a helper that starts playing later
        // is already routed through us and never plays a moment at full volume.
        let tap = runtime.makeTap(group.processIDs, group.identity.name)
        tap.gain = setting.gain
        tap.holdsMuteWithoutIO = true
        do {
            guard let destination = effectiveOutputUID(for: group.key) else { throw SpikeError("No output device is available") }
            try tap.start(outputUID: destination)
            taps[group.key] = tap
            clearFailure(group.key)
        } catch {
            failedTaps[group.key] = Set(group.processIDs)
            recordFailure(group.key, "Couldn't control \(group.identity.name): \(error.localizedDescription)")
        }
    }

    /// For headless tests.
    func tapMeters(for key: String) -> ProcessVolumeTap.Meters? { taps[key]?.takeMeters() }
    func tapDiagnostics(for key: String) -> ProcessVolumeTap.Diagnostics? { taps[key]?.diagnostics }
    func tapGeneration(for key: String) -> Int { taps[key]?.routeGeneration ?? 0 }
    func simulateStall(for key: String) { taps[key]?.simulateStall() }

    func stopAll() {
        taps.values.forEach { $0.stop() }
        taps.removeAll()
        pendingOutputs.removeAll()
    }
}
