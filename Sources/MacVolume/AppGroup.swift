import AppKit
import CoreAudio

/// All audio processes that belong to one app: the app itself plus helpers such as browser
/// renderers or WebKit's GPU process. One row and one volume setting per group.
struct AppGroup: Identifiable {
    let key: String
    let identity: ProcessIdentity
    let processes: [AudioProcess]

    var id: String { key }
    var isPlaying: Bool { processes.contains(where: \.isPlaying) }
    var processIDs: [AudioObjectID] { processes.map(\.id) }
}

/// The app a process's audio should be attributed to.
struct AppOwner {
    let key: String
    let pid: pid_t
    let bundleID: String

    /// Bundled helpers and XPC services are grouped under the app responsible for them
    /// (Chrome Helper → Chrome, WebKit GPU → the app showing the web content). Command-line
    /// tools stay on their own, otherwise everything run from a terminal would group under it.
    init(of process: AudioProcess) {
        if !process.bundleID.isEmpty,
           let responsible = Self.responsiblePID(for: process.pid), responsible != process.pid {
            let bundleID = Self.bundleID(of: responsible)
            (key, pid, self.bundleID) = (bundleID ?? "pid:\(responsible)", responsible, bundleID ?? "")
        } else {
            key = process.bundleID.isEmpty ? "pid:\(process.pid)" : process.bundleID
            pid = process.pid
            bundleID = process.bundleID
        }
    }

    private typealias ResponsiblePIDFunction = @convention(c) (pid_t) -> pid_t

    /// Private libsystem call; `bitPattern: -2` is RTLD_DEFAULT. Without it every process is its own group.
    private static let responsiblePIDFunction = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                                                      "responsibility_get_pid_responsible_for_pid")
        .map { unsafeBitCast($0, to: ResponsiblePIDFunction.self) }

    /// From the running app, or else from the outermost .app bundle around its executable.
    private static func bundleID(of pid: pid_t) -> String? {
        if let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier { return bundleID }
        guard let path = ProcessIdentity.executablePath(of: pid),
              let range = path.range(of: ".app/") else { return nil }
        return Bundle(path: String(path[..<range.lowerBound]) + ".app")?.bundleIdentifier
    }

    private static func responsiblePID(for pid: pid_t) -> pid_t? {
        guard let responsible = responsiblePIDFunction?(pid), responsible > 0 else { return nil }
        return responsible
    }
}
