import Foundation
import Darwin

/// One Chrome profile per app instance. Reads and writes never block the UI thread.
public final class ChromeSocketServer {
    private let listener: Int32
    private let path: String
    private let lock = NSLock()
    private var active: Connection?
    private var stopped = false
    private let received: (BridgeMessage) -> Void
    private let disconnected: (String) -> Void

    private final class Connection {
        let fd: Int32
        let writer = DispatchQueue(label: "MacVolume.Chrome.write")
        init(_ fd: Int32) {
            self.fd = fd
            LocalSocket.configure(fd)
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        }
        deinit { close(fd) }
    }

    public init(path: String = LocalSocket.path, received: @escaping (BridgeMessage) -> Void,
                disconnected: @escaping (String) -> Void) throws {
        self.path = path; self.received = received; self.disconnected = disconnected
        listener = try LocalSocket.listen(path: path)
    }

    public func start() {
        DispatchQueue.global(qos: .utility).async { [self] in
            while true {
                let fd = accept(listener, nil, nil)
                if fd < 0 { if errno == EINTR { continue }; break }
                guard LocalSocket.sameUser(fd) else { close(fd); continue }
                let connection = Connection(fd)
                lock.lock()
                let canAccept = !stopped && active == nil
                if canAccept { active = connection }
                lock.unlock()
                guard canAccept else {
                    let message = BridgeMessage(type: "error", error: "Only one Chrome profile can connect to MacVolume.")
                    if let data = try? message.encoded() { try? BridgeFrame.write(data, to: fd) }
                    continue
                }
                DispatchQueue.global(qos: .utility).async { [self] in read(connection) }
            }
        }
    }

    private func read(_ connection: Connection) {
        var reason = "Chrome disconnected. Reconnect using the extension."
        do {
            while let data = try BridgeFrame.read(connection.fd) {
                let message = try BridgeMessage.decode(data)
                guard ["state", "error"].contains(message.type) else { throw BridgeError.invalidMessage }
                received(message)
            }
        } catch { reason = error.localizedDescription }
        lock.lock()
        let notify = !stopped
        if notify { disconnected(reason) }
        if active === connection { active = nil }
        lock.unlock()
    }

    public func send(_ message: BridgeMessage) {
        lock.lock(); let connection = active; lock.unlock()
        guard let connection else { return }
        connection.writer.async {
            do { try BridgeFrame.write(message.encoded(), to: connection.fd) }
            catch { shutdown(connection.fd, SHUT_RDWR) }
        }
    }

    public func stop() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true
        let connection = active; active = nil
        lock.unlock()
        // Order shutdown after queued commands and allow Chrome to restore direct playback.
        if let connection {
            connection.writer.sync {
                if let data = try? BridgeMessage(type: "shutdown").encoded() {
                    try? BridgeFrame.write(data, to: connection.fd)
                }
                shutdown(connection.fd, SHUT_RDWR)
            }
        }
        LocalSocket.closeListener(listener, path: path)
    }
}
