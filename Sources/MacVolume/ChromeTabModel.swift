import AppKit
import Combine
import ChromeSupport

@MainActor
final class ChromeTabModel: ObservableObject {
    @Published private(set) var tabs: [ChromeTab] = []
    @Published private(set) var connected = false
    @Published private(set) var status = "Connect MacVolume Tabs and allow site access for individual tab volume."
    @Published private(set) var pending: [Int: String] = [:]
    /// Latest slider intent; tabs always retain the last confirmed browser state.
    @Published private(set) var requestedVolumes: [Int: Double] = [:]
    @Published var error: String?
    private var session: String?
    private var server: ChromeSocketServer?
    private var termination: AnyCancellable?

    /// Preview-only: no socket, saved settings or audio side effects.
    init(previewTabs: [ChromeTab], connected: Bool) {
        tabs = previewTabs
        self.connected = connected
        status = connected ? "Chrome connected · Individual audio/video tab controls are automatic." : "Chrome disconnected · Last confirmed tab state."
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
            if let request = message.requestID {
                for id in pending.filter({ $0.value == request }).keys {
                    pending[id] = nil; requestedVolumes[id] = nil
                }
            }
            return
        }
        guard message.type == "state", let newSession = message.session, let newTabs = message.tabs else { return }
        if session != newSession { pending.removeAll(); requestedVolumes.removeAll() }
        session = newSession
        tabs = newTabs.sorted { $0.id < $1.id }
        connected = true
        if message.mode != "automatic-sites" {
            status = "Extension update required · Reload MacVolume Tabs in chrome://extensions and allow access to sites."
        } else if newTabs.contains(where: { $0.canPlay == nil || $0.canPause == nil }) {
            status = "Chrome connected · Tab controls are automatic. Reload older pages once for play/pause."
        } else {
            status = newTabs.isEmpty
                ? "Chrome connected · Play audio to see individual tabs. If none appear, check the extension's site access."
                : "Chrome connected · Individual audio/video tab controls are automatic."
        }
        let completed = Set(pending.filter { $0.value == message.requestID }.keys)
        if let request = message.requestID { pending = pending.filter { $0.value != request } }
        let alive = Set(newTabs.filter { $0.controlled || $0.canMute == true || $0.canPlay == true || $0.canPause == true }.map(\.id))
        pending = pending.filter { alive.contains($0.key) }
        requestedVolumes = requestedVolumes.filter { id, _ in newTabs.contains { $0.id == id && $0.controlled } }
        server?.send(BridgeMessage(type: "ready", session: newSession))
        for id in completed { flushVolume(for: id) }
    }

    private func disconnected(_ reason: String) {
        connected = false
        session = nil
        pending.removeAll()
        requestedVolumes.removeAll()
        status = reason + " Page gains remain while the extension is active."
    }

    func setVolume(_ volume: Double, for tab: ChromeTab) {
        guard connected, volume.isFinite, tabs.contains(where: { $0.id == tab.id && $0.controlled }) else { return }
        requestedVolumes[tab.id] = min(1, max(0, volume))
        flushVolume(for: tab.id)
    }

    private func flushVolume(for id: Int) {
        guard pending[id] == nil, let volume = requestedVolumes[id],
              let tab = tabs.first(where: { $0.id == id && $0.controlled }) else { return }
        if abs(tab.volume - volume) < 1e-9 && !tab.muted {
            requestedVolumes[id] = nil
        } else {
            send(tab, volume: volume, muted: false)
        }
    }

    func toggleMute(_ tab: ChromeTab) { send(tab, volume: tab.volume, muted: !tab.muted) }

    func setPlayback(_ action: String, for tab: ChromeTab) {
        guard (action == "play" && tab.canPlay == true) || (action == "pause" && tab.canPause == true) else { return }
        sendRequest(for: tab) { session, request in
            BridgeMessage(type: "playback", session: session, requestID: request, tabID: tab.id, action: action)
        }
    }

    func setTransport(_ action: String, for tab: ChromeTab) {
        guard let current = tabs.first(where: { $0.id == tab.id }) else { return }
        let supported: Bool
        switch action {
        case "previous": supported = current.canPrevious == true
        case "next": supported = current.canNext == true
        case "shuffle-on", "shuffle-off": supported = current.canShuffle == true && current.shuffleEnabled != nil
        default: return
        }
        guard supported else { return }
        sendRequest(for: current) { session, request in
            BridgeMessage(type: "transport", session: session, requestID: request, tabID: current.id, action: action)
        }
    }

    private func send(_ tab: ChromeTab, volume: Double, muted: Bool) {
        guard tab.controlled || tab.canMute == true, volume.isFinite else { return }
        sendRequest(for: tab) { session, request in
            BridgeMessage(type: "set", session: session, requestID: request, tabID: tab.id, volume: volume, muted: muted)
        }
    }

    private func sendRequest(for tab: ChromeTab, message: (String, String) -> BridgeMessage) {
        guard connected, pending[tab.id] == nil, let session else { return }
        let request = UUID().uuidString
        pending[tab.id] = request
        error = nil
        server?.send(message(session, request))
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.pending[tab.id] == request else { return }
            self.pending[tab.id] = nil
            self.requestedVolumes[tab.id] = nil
            self.error = "Chrome did not confirm the control for tab #\(tab.id). Reconnect using the extension."
        }
    }

    static var extensionURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("ChromeExtension", isDirectory: true)
    }
    static var guideURL: URL? { Bundle.main.url(forResource: "chrome-tab-volume", withExtension: "md") }
}
