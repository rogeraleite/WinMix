import AppKit
import CoreAudio

struct CoreAudioError: LocalizedError {
    let operation: String
    let status: OSStatus

    var errorDescription: String? {
        "\(operation) failed (OSStatus \(status) \(UInt32(bitPattern: status).fourCC))"
    }
}

struct SpikeError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

func check(_ status: OSStatus, _ operation: @autoclosure () -> String) throws {
    guard status == noErr else { throw CoreAudioError(operation: operation(), status: status) }
}

extension UInt32 {
    /// Renders Core Audio four-char codes ('!obj') readably, falling back to the number.
    var fourCC: String {
        let bytes = [24, 16, 8, 0].map { UInt8((self >> UInt32($0)) & 0xFF) }
        guard bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return String(self) }
        return "'" + String(decoding: bytes, as: UTF8.self) + "'"
    }
}

extension AudioObjectID {
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)

    static func defaultOutputDevice() throws -> AudioObjectID {
        try systemObject.read(kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID.unknown)
    }

    static func defaultOutputUID() throws -> String {
        try defaultOutputDevice().readString(kAudioDevicePropertyDeviceUID)
    }

    static func device(uid: String) -> AudioObjectID? {
        let devices = (try? systemObject.readObjectList(kAudioHardwarePropertyDevices)) ?? []
        return devices.first { (try? $0.readString(kAudioDevicePropertyDeviceUID)) == uid }
    }

    private func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    func read<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector,
                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                 initial: T) throws -> T {
        var address = address(selector, scope)
        var size = UInt32(MemoryLayout<T>.size)
        var value = initial
        try check(AudioObjectGetPropertyData(self, &address, 0, nil, &size, &value),
                  "Reading \(selector.fourCC) of object \(self)")
        return value
    }

    func readString(_ selector: AudioObjectPropertySelector,
                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> String {
        var address = address(selector, scope)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        try check(AudioObjectGetPropertyData(self, &address, 0, nil, &size, &value),
                  "Reading \(selector.fourCC) of object \(self)")
        return value?.takeRetainedValue() as String? ?? ""
    }

    func readObjectList(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [AudioObjectID] {
        var address = address(selector, scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size),
                  "Sizing \(selector.fourCC) of object \(self)")
        var list = [AudioObjectID](repeating: .unknown, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(self, &address, 0, nil, &size, &list),
                  "Reading \(selector.fourCC) of object \(self)")
        return Array(list.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }
}

extension AudioStreamBasicDescription {
    var isFloat32: Bool {
        mFormatID == kAudioFormatLinearPCM && mFormatFlags & kAudioFormatFlagIsFloat != 0 && mBitsPerChannel == 32
    }

    var summary: String {
        let layout = mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? "non-interleaved" : "interleaved"
        let sample = isFloat32 ? "Float32" : "\(mFormatID.fourCC) \(mBitsPerChannel)-bit"
        return "\(Int(mSampleRate)) Hz, \(mChannelsPerFrame) ch, \(sample), \(layout)"
    }
}

/// A process Core Audio knows about (it has opened an audio connection at some point).
struct AudioProcess: Identifiable, Hashable {
    let id: AudioObjectID
    let pid: pid_t
    let bundleID: String
    let isPlaying: Bool

    static func all() throws -> [AudioProcess] {
        try AudioObjectID.systemObject.readObjectList(kAudioHardwarePropertyProcessObjectList).map { objectID in
            AudioProcess(
                id: objectID,
                pid: (try? objectID.read(kAudioProcessPropertyPID, initial: pid_t(-1))) ?? -1,
                bundleID: (try? objectID.readString(kAudioProcessPropertyBundleID)) ?? "",
                isPlaying: ((try? objectID.read(kAudioProcessPropertyIsRunningOutput, initial: UInt32(0))) ?? 0) != 0
            )
        }
        .filter { $0.pid != getpid() }
    }
}

/// CPU used by this process, as a percentage of one core, averaged since the previous sample.
struct CPUMeter {
    private var lastCPU = CPUMeter.processCPUSeconds()
    private var lastWall = Date()

    mutating func sample() -> Double {
        let cpu = Self.processCPUSeconds()
        let now = Date()
        let elapsed = now.timeIntervalSince(lastWall)
        defer { lastCPU = cpu; lastWall = now }
        return elapsed > 0 ? (cpu - lastCPU) / elapsed * 100 : 0
    }

    private static func processCPUSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }
}
