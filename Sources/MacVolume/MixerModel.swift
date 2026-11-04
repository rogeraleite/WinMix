import AppKit
import Combine
import CoreAudio

struct VolumeSetting: Equatable, Codable {
    var volume: Double = 1
    var isMuted = false

    /// At exactly 100% and unmuted the app plays directly, without a tap.
    var isDefault: Bool { volume == 1 && !isMuted }
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

    var maximumVolume: Double { boostEnabled ? Self.boostMaximum : 1 }
    var activeTapCount: Int { taps.count }

    private let monitor = AudioProcessMonitor()
    private var groups: [String: AppGroup] = [:]
    private var owners: [AudioObjectID: AppOwner] = [:]
    private var identities: [String: ProcessIdentity] = [:]
    private var taps: [String: ProcessVolumeTap] = [:]
    /// Apps whose tap failed to start, with the processes it was tried with. Retried when the
    /// app's processes change (e.g. a process exited mid-update) or the user changes the setting.
    private var failedTaps: [String: Set<AudioObjectID>] = [:]
    private var subscriptions: Set<AnyCancellable> = []
    private let defaults: UserDefaults?
    /// The device taps play into. Follows the system default unless `pinnedOutput` is set.
    private var outputUID: String?
    private let pinnedOutput: Bool
    private var isAsleep = false
    private var hadRouteFailure = false

    /// Sample data for rendering the UI headlessly; touches no audio.
    init(previewRows: [AppGroup], settings: [String: VolumeSetting], boostEnabled: Bool, outputName: String) {
        defaults = nil
        pinnedOutput = true
        rows = previewRows
        self.settings = settings
        self.boostEnabled = boostEnabled
        self.outputName = outputName
    }

    /// - Parameters:
    ///   - defaults: where settings persist; nil keeps them in memory, so headless tests can
    ///     neither read the user's saved volumes (which would tap real apps) nor overwrite them.
    ///   - pinnedOutputUID: plays into this device instead of following the system default.
    init(defaults: UserDefaults? = .standard, pinnedOutputUID: String? = nil) {
        self.defaults = defaults
        pinnedOutput = pinnedOutputUID != nil
        outputUID = pinnedOutputUID ?? (try? AudioObjectID.defaultOutputUID())
        if let defaults {
            settings = SavedSettings.load(from: defaults)
            boostEnabled = SavedSettings.loadBoost(from: defaults)
        }

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
            .sink { [weak self] _ in self?.checkRoutes() }
            .store(in: &subscriptions)
        if !pinnedOutput { watchDefaultOutput() }
        updateOutputName()
        monitor.start()
    }

    private func watchDefaultOutput() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(.systemObject, &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.defaultOutputChanged() }
        }
    }

    private func defaultOutputChanged() {
        guard let uid = try? AudioObjectID.defaultOutputUID(), uid != outputUID else { return }
        route(to: uid)
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
        if !pinnedOutput, let uid = try? AudioObjectID.defaultOutputUID() { outputUID = uid }
        updateOutputName()
        checkRoutes(rebuildAll: true)
        retryFailedTaps()
    }

    /// Moves taps that aren't on the current output or have stopped running. A move that fails
    /// keeps the old route and is retried on the next timer tick.
    private func checkRoutes(rebuildAll: Bool = false) {
        guard !isAsleep, let outputUID else { return }
        var failure: String?
        for (key, tap) in taps {
            let isStalled = tap.checkStalled()
            guard rebuildAll || isStalled || tap.outputUID != outputUID else { continue }
            do {
                try tap.moveOutput(to: outputUID)
            } catch {
                failure = "Couldn't move \(groups[key]?.identity.name ?? key) to the current output: \(error.localizedDescription)"
            }
        }
        if let failure {
            error = failure
        } else if hadRouteFailure {
            error = nil
        }
        hadRouteFailure = failure != nil
    }

    private func updateOutputName() {
        outputName = outputUID.flatMap(AudioObjectID.device(uid:))
            .flatMap { try? $0.readString(kAudioObjectPropertyName) } ?? ""
    }

    private func retryFailedTaps() {
        failedTaps.removeAll()
        for group in groups.values {
            apply(settings[group.key] ?? VolumeSetting(), to: group)
        }
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

    private func reconcile(_ processes: [AudioProcess]) {
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
            return
        }
        if let tap = taps[group.key] {
            tap.gain = setting.gain
            guard Set(tap.processIDs) != Set(group.processIDs) else { return }
            do {
                try tap.setProcesses(group.processIDs)
                return
            } catch {
                tap.stop()
                taps[group.key] = nil
            }
        }
        guard failedTaps[group.key] == nil else { return }

        // Tap every process of the app, playing or not, so a helper that starts playing later
        // is already routed through us and never plays a moment at full volume.
        let tap = ProcessVolumeTap(processIDs: group.processIDs, name: group.identity.name)
        tap.gain = setting.gain
        do {
            try tap.start(outputUID: outputUID)
            taps[group.key] = tap
        } catch {
            failedTaps[group.key] = Set(group.processIDs)
            self.error = "Couldn't control \(group.identity.name): \(error.localizedDescription)"
        }
    }

    /// For headless tests.
    func tapMeters(for key: String) -> ProcessVolumeTap.Meters? { taps[key]?.takeMeters() }
    func tapDiagnostics(for key: String) -> ProcessVolumeTap.Diagnostics? { taps[key]?.diagnostics }
    func simulateStall(for key: String) { taps[key]?.simulateStall() }

    private func stopAll() {
        taps.values.forEach { $0.stop() }
        taps.removeAll()
    }
}
