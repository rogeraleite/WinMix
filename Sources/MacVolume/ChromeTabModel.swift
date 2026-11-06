import AppKit
import Combine
import ChromeSupport

@MainActor
final class ChromeTabModel: ObservableObject {
    @Published private(set) var tabs: [ChromeTab] = []
    @Published private(set) var connected = false
    @Published private(set) var status = "Connect MacVolume Tabs for automatic YouTube and YouTube Music controls."
    @Published private(set) var pending: [Int: String] = [:]
    @Published var error: String?
    private var session: String?
    private var server: ChromeSocketServer?
    private var termination: AnyCancellable?

    /// Preview-only: no socket, saved settings or audio side effects.
    init(previewTabs: [ChromeTab], connected: Bool) {
        tabs = previewTabs
        self.connected = connected
        status = connected ? "Chrome connected · YouTube and YouTube Music are automatic." : "Chrome disconnected · Last confirmed tab state."
    }

    init(socketPath: String = LocalSocket.path) {
        do {
            server = try ChromeSocketServer(path: socketPath, received: { [weak self] message in
                DispatchQueue.main.async { self?.receive(message) }
            }, disconnected: { [weak self] reason in
                DispatchQueue.main.async { self?.disconnected(reason) }
            })
            server?.start()
        } catch { status = error.localizedDescription }
        termination = NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.stop() }
    }

    func stop() { server?.stop() }

    private func receive(_ message: BridgeMessage) {
        if message.type == "error" {
            error = message.error
            if let request = message.requestID { pending = pending.filter { $0.value != request } }
            return
        }
        guard message.type == "state", let newSession = message.session, let newTabs = message.tabs else { return }
        if session != newSession { pending.removeAll() }
        session = newSession
        tabs = newTabs.sorted { $0.id < $1.id }
        connected = true
        status = message.mode == "automatic-youtube"
            ? "Chrome connected · YouTube and YouTube Music are automatic."
            : "Chrome connected · Reload MacVolume Tabs once to enable automatic YouTube controls."
        if let request = message.requestID { pending = pending.filter { $0.value != request } }
        let alive = Set(newTabs.filter { $0.controlled || $0.canMute == true }.map(\.id))
        pending = pending.filter { alive.contains($0.key) }
        server?.send(BridgeMessage(type: "ready", session: newSession))
    }

    private func disconnected(_ reason: String) {
        connected = false
        session = nil
        pending.removeAll()
        status = reason + " Page gains remain while the extension is active."
    }

    func setVolume(_ volume: Double, for tab: ChromeTab) {
        guard tab.controlled else { return }
        send(tab, volume: min(1, max(0, volume)), muted: false)
    }

    func toggleMute(_ tab: ChromeTab) { send(tab, volume: tab.volume, muted: !tab.muted) }

    private func send(_ tab: ChromeTab, volume: Double, muted: Bool) {
        guard connected, tab.controlled || tab.canMute == true, pending[tab.id] == nil, let session, volume.isFinite else { return }
        let request = UUID().uuidString
        pending[tab.id] = request
        error = nil
        server?.send(BridgeMessage(type: "set", session: session, requestID: request,
                                   tabID: tab.id, volume: volume, muted: muted))
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.pending[tab.id] == request else { return }
            self.pending[tab.id] = nil
            self.error = "Chrome did not confirm the volume for tab #\(tab.id). Reconnect using the extension."
        }
    }

    static var extensionURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("ChromeExtension", isDirectory: true)
    }
    static var guideURL: URL? { Bundle.main.url(forResource: "chrome-tab-volume", withExtension: "md") }
}
