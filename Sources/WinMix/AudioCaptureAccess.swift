import Combine
import Foundation

/// The "System Audio Recording" permission (TCC service kTCCServiceAudioCapture).
///
/// macOS has no public API to check it, so this calls the private TCC framework, as other
/// tap-based tools do. If the symbol is missing we report `.unknown` and let the taps try
/// anyway (without access they just read silence). macOS itself asks on the first tap.
enum AudioCaptureAccess {
    enum Status { case authorized, denied, notDetermined, unknown }

    private typealias PreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int32

    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let framework = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    static func rawPreflight() -> Int32? {
        guard let framework, let symbol = dlsym(framework, "TCCAccessPreflight") else { return nil }
        return unsafeBitCast(symbol, to: PreflightFunction.self)(service, nil)
    }

    static func status() -> Status {
        switch rawPreflight() {
        case nil: .unknown
        case 0: .authorized
        case 1: .denied
        default: .notDetermined
        }
    }
}

@MainActor
final class PermissionModel: ObservableObject {
    @Published private(set) var status: AudioCaptureAccess.Status
    private let readStatus: () -> AudioCaptureAccess.Status

    init(readStatus: @escaping () -> AudioCaptureAccess.Status = AudioCaptureAccess.status) {
        self.readStatus = readStatus
        status = readStatus()
    }

    func refresh() {
        status = readStatus()
    }
}
