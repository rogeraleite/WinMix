import AppKit
import UniformTypeIdentifiers

/// Human-facing name and icon for an audio process, falling back from the running app,
/// to the app bundle, to the executable on disk.
struct ProcessIdentity {
    let name: String
    let icon: NSImage

    init(pid: pid_t, bundleID: String) {
        let app = NSRunningApplication(processIdentifier: pid).flatMap {
            bundleID.isEmpty || $0.bundleIdentifier == bundleID ? $0 : nil
        }
        let path = Self.executablePath(of: pid)
        let enclosingURL = path.flatMap(Self.enclosingAppURL).flatMap {
            Bundle(url: $0)?.bundleIdentifier == bundleID ? $0 : nil
        }
        let appURL = enclosingURL ?? (bundleID.isEmpty ? nil : NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID))

        name = app?.localizedName
            ?? appURL.map { FileManager.default.displayName(atPath: $0.path) }
            ?? path.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? (bundleID.isEmpty ? "pid \(pid)" : bundleID)
        icon = app?.icon
            ?? appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? path.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSWorkspace.shared.icon(for: .application)
    }

    static func enclosingAppURL(_ path: String) -> URL? {
        guard let range = path.range(of: ".app/") else { return nil }
        return URL(fileURLWithPath: String(path[..<range.lowerBound]) + ".app", isDirectory: true)
    }

    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)  // PROC_PIDPATHINFO_MAXSIZE
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
