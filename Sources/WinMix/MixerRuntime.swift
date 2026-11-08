import CoreAudio

/// Boundary for deterministic routing tests without tapping any user processes.
protocol MixerAudioTap: AnyObject {
    var gain: Float { get set }
    var holdsMuteWithoutIO: Bool { get set }
    var processIDs: [AudioObjectID] { get }
    var outputUID: String? { get }
    var pendingOutputUID: String? { get }
    var routeFailure: String? { get }
    var diagnostics: ProcessVolumeTap.Diagnostics { get }
    var routeGeneration: Int { get }
    func start(outputUID: String?) throws
    func moveOutput(to uid: String) throws
    func setProcesses(_ ids: [AudioObjectID]) throws
    func checkStalled() -> Bool
    func takeMeters() -> ProcessVolumeTap.Meters
    func simulateStall()
    func stop()
}

extension MixerAudioTap {
    var pendingOutputUID: String? { nil }
    var routeFailure: String? { nil }
}

extension ProcessVolumeTap: MixerAudioTap {}

struct MixerRuntime {
    var outputs: () -> [AudioOutputDevice]? = { AudioOutputDevice.available() }
    var defaultOutput: () -> String? = { try? AudioObjectID.defaultOutputUID() }
    var makeTap: ([AudioObjectID], String) -> any MixerAudioTap = { ProcessVolumeTap(processIDs: $0, name: $1) }
    var observesSystem = true
}
