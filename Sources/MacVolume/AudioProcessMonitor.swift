import Combine
import CoreAudio

/// Publishes Core Audio's process list, refreshed whenever a process appears, disappears,
/// or starts/stops playing.
@MainActor
final class AudioProcessMonitor: ObservableObject {
    @Published private(set) var processes: [AudioProcess] = []

    /// Changes to IsRunningOutput are announced through IsRunning (seen on macOS 27.2),
    /// so listen to both.
    private static let playbackSelectors = [kAudioProcessPropertyIsRunning, kAudioProcessPropertyIsRunningOutput]

    private var listObserver: AudioObjectPropertyListenerBlock?
    private var playbackObservers: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]

    func start() {
        guard listObserver == nil else { return }
        let observer = makeObserver()
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectAddPropertyListenerBlock(.systemObject, &address, .main, observer)
        listObserver = observer
        reload()
    }

    private func reload() {
        let current = (try? AudioProcess.all()) ?? []
        let ids = Set(current.map(\.id))

        for (id, observer) in playbackObservers where !ids.contains(id) {
            for selector in Self.playbackSelectors {
                var address = Self.address(selector)
                AudioObjectRemovePropertyListenerBlock(id, &address, .main, observer)
            }
            playbackObservers[id] = nil
        }
        for process in current where playbackObservers[process.id] == nil {
            let observer = makeObserver()
            for selector in Self.playbackSelectors {
                var address = Self.address(selector)
                AudioObjectAddPropertyListenerBlock(process.id, &address, .main, observer)
            }
            playbackObservers[process.id] = observer
        }

        if current != processes { processes = current }
    }

    /// Listener blocks are delivered on the main queue (see the `.main` argument above).
    private func makeObserver() -> AudioObjectPropertyListenerBlock {
        { [weak self] _, _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
