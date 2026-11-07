import Foundation
import Darwin

/// Chrome Native Messaging and the local socket use the same bounded, little-endian framing.
public enum BridgeFrame {
    public static let limit = 256 * 1024

    private static func readExactly(_ fd: Int32, count: Int, allowEOF: Bool = false) throws -> Data? {
        var data = Data(count: count)
        let readCount: Int = try data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < count {
                let n = Darwin.read(fd, bytes.baseAddress!.advanced(by: offset), count - offset)
                if n < 0 && errno == EINTR { continue }
                if n == 0 && offset == 0 && allowEOF { return 0 }
                guard n > 0 else { throw BridgeError.invalidFrame }
                offset += n
            }
            return offset
        }
        return readCount == 0 && allowEOF ? nil : data
    }

    public static func read(_ fd: Int32) throws -> Data? {
        guard let header = try readExactly(fd, count: 4, allowEOF: true) else { return nil }
        let length = header.enumerated().reduce(0) { $0 | (Int($1.element) << (8 * $1.offset)) }
        guard length > 0 && length <= limit else { throw BridgeError.invalidFrame }
        return try readExactly(fd, count: length)
    }

    public static func write(_ data: Data, to fd: Int32) throws {
        guard !data.isEmpty && data.count <= limit else { throw BridgeError.invalidFrame }
        var length = UInt32(data.count).littleEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(data)
        try frame.withUnsafeBytes { bytes in
            var offset = 0
            while offset < frame.count {
                let n = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), frame.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw BridgeError.system("Chrome bridge connection closed.") }
                offset += n
            }
        }
    }
}

public enum LocalSocket {
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacVolume", isDirectory: true)
    }
    public static var path: String {
        ProcessInfo.processInfo.environment["MACVOLUME_CHROME_SOCKET"]
            ?? directory.appendingPathComponent("chrome.sock").path
    }

    public static func configure(_ fd: Int32) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }

    private static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw BridgeError.system("Home path is too long for the Chrome bridge socket.")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in buffer.copyBytes(from: bytes) }
        return address
    }

    public static func connect(path: String = LocalSocket.path) throws -> Int32 {
        var addr = try address(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BridgeError.system("Could not create Chrome bridge socket.") }
        configure(fd)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0, sameUser(fd) else {
            close(fd)
            throw BridgeError.system("Open WinMix, then reconnect the Chrome extension.")
        }
        return fd
    }

    public static func listen(path: String = LocalSocket.path) throws -> Int32 {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_uid == getuid(),
              (info.st_mode & S_IFMT) == S_IFDIR else { throw BridgeError.system("Unsafe Chrome bridge directory.") }
        guard chmod(directory.path, 0o700) == 0 else { throw BridgeError.system("Cannot protect Chrome bridge directory.") }
        // A held flock protects both the stale-socket cleanup and the running server.
        let lock = open(path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw BridgeError.system("Cannot lock Chrome bridge.") }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            close(lock); throw BridgeError.system("Chrome bridge is already running in another WinMix instance.")
        }
        do {
            var addr = try address(path)
            unlink(path)
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw BridgeError.system("Cannot open Chrome bridge.") }
            configure(fd)
            let result = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 4) == 0 else {
                close(fd); throw BridgeError.system("Cannot listen for Chrome extension.")
            }
            // Keep lock owned by the listener, released explicitly by closeListener.
            locksGuard.lock(); listenerLocks[fd] = lock; locksGuard.unlock()
            return fd
        } catch { close(lock); throw error }
    }

    // Access only from server startup/shutdown, not concurrent listener creation.
    private static var listenerLocks: [Int32: Int32] = [:]
    private static let locksGuard = NSLock()
    public static func closeListener(_ fd: Int32, path: String = LocalSocket.path) {
        shutdown(fd, SHUT_RDWR); close(fd); unlink(path)
        locksGuard.lock(); let lock = listenerLocks.removeValue(forKey: fd); locksGuard.unlock()
        if let lock { close(lock) }
    }

    public static func sameUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0; var gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
    }
}
