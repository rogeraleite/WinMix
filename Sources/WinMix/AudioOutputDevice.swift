import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Equatable {
    let uid: String
    let name: String
    var objectID: AudioObjectID = .unknown
    var id: String { uid }

    static func available() -> [AudioOutputDevice]? {
        guard let devices = try? AudioObjectID.systemObject.readObjectList(kAudioHardwarePropertyDevices) else { return nil }
        return devices.compactMap { device in
            guard let uid = try? device.readString(kAudioDevicePropertyDeviceUID), !uid.isEmpty,
                  let name = try? device.readString(kAudioObjectPropertyName),
                  let streams = try? device.readObjectList(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput),
                  isSelectable(name: name,
                               alive: (try? device.read(kAudioDevicePropertyDeviceIsAlive, initial: UInt32(0))) == 1,
                               hidden: (try? device.read(kAudioDevicePropertyIsHidden, initial: UInt32(0))) == 1,
                               hasOutput: !streams.isEmpty) else { return nil }
            return AudioOutputDevice(uid: uid, name: name, objectID: device)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func isSelectable(name: String, alive: Bool, hidden: Bool, hasOutput: Bool) -> Bool {
        alive && !hidden && hasOutput && !name.hasPrefix("WinMix (") && !name.hasPrefix("MacVolume (")
    }
}

/// The model compares filtered snapshots, so our own private aggregate notifications
/// never trigger routing retries or a create/destroy notification loop.
final class AudioOutputWatcher {
    private struct Listener {
        let object: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }
    private var listeners: [Listener] = []
    private var deviceIDs: Set<AudioObjectID> = []
    private let changed: () -> Void

    init(changed: @escaping () -> Void) {
        self.changed = changed
        add(.systemObject, kAudioHardwarePropertyDevices)
        add(.systemObject, kAudioHardwarePropertyDefaultOutputDevice)
        updateDevices()
    }

    private func add(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.updateDevices()
            self?.changed()
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
            listeners.append(Listener(object: object, address: address, block: block))
        }
    }

    private func updateDevices() {
        guard let devices = try? AudioObjectID.systemObject.readObjectList(kAudioHardwarePropertyDevices) else { return }
        let current = Set(devices)
        for var listener in listeners where listener.object != .systemObject && !current.contains(listener.object) {
            AudioObjectRemovePropertyListenerBlock(listener.object, &listener.address, .main, listener.block)
        }
        listeners.removeAll { $0.object != .systemObject && !current.contains($0.object) }
        for id in current.subtracting(deviceIDs) {
            add(id, kAudioDevicePropertyDeviceIsAlive)
            add(id, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
            add(id, kAudioObjectPropertyName)
        }
        deviceIDs = current
    }

    deinit {
        for var listener in listeners {
            AudioObjectRemovePropertyListenerBlock(listener.object, &listener.address, .main, listener.block)
        }
    }
}
