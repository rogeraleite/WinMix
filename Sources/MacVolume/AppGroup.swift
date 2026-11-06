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

    /// A bundled executable belongs to its enclosing app even when launched by an editor.
    /// Shared XPC services use macOS responsibility; command-line processes stay separate.
    init(of process: AudioProcess) {
        let responsible = Self.responsiblePID(for: process.pid)
        let enclosing = ProcessIdentity.executablePath(of: process.pid)
            .flatMap(ProcessIdentity.enclosingAppURL)
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
        self.init(pid: process.pid, bundleID: process.bundleID, enclosingBundleID: enclosing,
                  responsiblePID: responsible, responsibleBundleID: responsible.flatMap(Self.bundleID))
    }

    /// Pure ownership decision, also used by tests without inspecting live processes.
    init(pid: pid_t, bundleID: String, enclosingBundleID: String?,
         responsiblePID: pid_t?, responsibleBundleID: String?) {
        if !bundleID.isEmpty, let enclosingBundleID {
            key = enclosingBundleID
            self.bundleID = enclosingBundleID
            self.pid = responsibleBundleID == enclosingBundleID ? (responsiblePID ?? pid) : pid
        } else if !bundleID.isEmpty, let responsiblePID, responsiblePID != pid {
            (key, self.pid, self.bundleID) = (responsibleBundleID ?? "pid:\(responsiblePID)", responsiblePID, responsibleBundleID ?? "")
        } else {
            key = bundleID.isEmpty ? "pid:\(pid)" : bundleID
            self.pid = pid
            self.bundleID = bundleID
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
        return ProcessIdentity.executablePath(of: pid).flatMap(ProcessIdentity.enclosingAppURL)
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    private static func responsiblePID(for pid: pid_t) -> pid_t? {
        guard let responsible = responsiblePIDFunction?(pid), responsible > 0 else { return nil }
        return responsible
    }
}
