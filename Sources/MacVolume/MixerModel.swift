import AppKit
import Combine
import CoreAudio

struct VolumeSetting: Equatable {
    var volume: Double = 1
    var isMuted = false

    /// At exactly 100% and unmuted the app plays directly, without a tap.
    var isDefault: Bool { volume == 1 && !isMuted }
    var gain: Float { isMuted ? 0 : Float(volume) }
}

/// One row per app that is playing (or that we are already controlling). An app gets a tap
/// covering all of its processes only while it is set away from 100% or muted.
@MainActor
final class MixerModel: ObservableObject {
    static let boostMaximum = 2.0

    @Published private(set) var rows: [AppGroup] = []
    @Published private(set) var settings: [String: VolumeSetting] = [:]
    @Published var boostEnabled = false {
        didSet { if !boostEnabled { clampToHundredPercent() } }
    }
    @Published var error: String?

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

    init() {
        monitor.$processes
            .sink { [weak self] in self?.reconcile($0) }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.stopAll() }
            .store(in: &subscriptions)
        monitor.start()
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
            try tap.start()
            taps[group.key] = tap
        } catch {
            failedTaps[group.key] = Set(group.processIDs)
            self.error = "Couldn't control \(group.identity.name): \(error.localizedDescription)"
        }
    }

    private func stopAll() {
        taps.values.forEach { $0.stop() }
        taps.removeAll()
    }
}
