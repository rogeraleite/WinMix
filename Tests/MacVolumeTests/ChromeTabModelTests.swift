import XCTest
import Darwin
import ChromeSupport
@testable import MacVolume

final class ChromeTabModelTests: XCTestCase {
    @MainActor
    func testTrackControlUsesCapabilitiesAndWaitsForConfirmedShuffle() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = ChromeTabModel(socketPath: directory.appendingPathComponent("track.sock").path)
        defer { model.stop(); try? FileManager.default.removeItem(at: directory) }
        let fd = try LocalSocket.connect(path: directory.appendingPathComponent("track.sock").path)
        defer { close(fd) }
        var state = sliderState()
        var tabs = state["tabs"] as! [[String: Any]]
        tabs[0]["canNext"] = true; tabs[0]["canPrevious"] = false
        tabs[0]["canShuffle"] = true; tabs[0]["shuffleEnabled"] = false
        state["tabs"] = tabs; try write(state, to: fd)
        try await until { model.connected && model.tabs.count == 2 }
        let tab = model.tabs[0]
        model.setTransport("previous", for: tab)
        XCTAssertTrue(model.pending.isEmpty)
        model.setTransport("shuffle-on", for: tab)
        let command = try await readCommand(fd)
        XCTAssertEqual(command.type, "transport"); XCTAssertEqual(command.action, "shuffle-on")
        XCTAssertNil(command.volume); XCTAssertNil(command.muted)
        XCTAssertEqual(model.tabs[0].shuffleEnabled, false)
        model.setTransport("next", for: tab)
        XCTAssertEqual(model.pending[tab.id], command.requestID)
        tabs[0]["shuffleEnabled"] = true; state["tabs"] = tabs; state["requestID"] = command.requestID
        try write(state, to: fd)
        try await until { model.pending.isEmpty }
        XCTAssertEqual(model.tabs[0].shuffleEnabled, true)
        XCTAssertEqual(model.tabs[0].volume, 1)
        model.setTransport("next", for: tab)
        let next = try await readCommand(fd)
        XCTAssertEqual(next.action, "next")
    }
    @MainActor
    func testSliderCoalescesLatestGainWithoutBlockingAnotherTab() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = directory.appendingPathComponent("slider.sock").path
        let model = ChromeTabModel(socketPath: path)
        defer { model.stop(); try? FileManager.default.removeItem(at: directory) }
        let fd = try LocalSocket.connect(path: path)
        defer { close(fd) }
        var state = sliderState()
        try write(state, to: fd)
        try await until { model.connected && model.tabs.count == 2 }
        XCTAssertFalse(model.status.contains("Reload"))
        let first = model.tabs[0], second = model.tabs[1]
        model.setVolume(0.2, for: first)
        model.setVolume(0.4, for: first)
        model.setVolume(0.8, for: first)
        model.setVolume(0.6, for: second)
        XCTAssertEqual(model.requestedVolumes[7], 0.8)
        XCTAssertEqual(model.tabs[0].volume, 1, "Confirmed gain stays separate from the requested gain")
        let a = try await readCommand(fd), b = try await readCommand(fd)
        XCTAssertEqual(a.tabID, 7); XCTAssertEqual(a.volume, 0.2)
        XCTAssertEqual(b.tabID, 8); XCTAssertEqual(b.volume, 0.6)
        try write(state, to: fd) // Unsolicited state must not flush the queue.
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(model.pending[7], a.requestID)
        state["requestID"] = a.requestID
        var tabs = state["tabs"] as! [[String: Any]]
        tabs[0]["volume"] = 0.2; state["tabs"] = tabs
        try write(state, to: fd)
        try await until { model.pending[7] != nil && model.pending[7] != a.requestID }
        let last = try await readCommand(fd)
        XCTAssertEqual(last.tabID, 7); XCTAssertEqual(last.volume, 0.8, "Intermediate drag values are replaced")
        XCTAssertEqual(model.requestedVolumes[7], 0.8)
        tabs[0]["volume"] = 0.8; tabs[1]["volume"] = 0.6; state["tabs"] = tabs
        state["requestID"] = last.requestID; try write(state, to: fd)
        state["requestID"] = b.requestID; try write(state, to: fd)
        try await until { model.pending.isEmpty && model.requestedVolumes.isEmpty }
        XCTAssertEqual(model.tabs.map(\.volume), [0.8, 0.6])
    }

    @MainActor
    func testSliderDiscardsQueuedValuesOnFailureSessionChangeAndDisconnect() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = directory.appendingPathComponent("failure.sock").path
        let model = ChromeTabModel(socketPath: path)
        defer { model.stop(); try? FileManager.default.removeItem(at: directory) }
        let fd = try LocalSocket.connect(path: path)
        defer { close(fd) }
        var state = sliderState()
        try write(state, to: fd)
        try await until { model.tabs.count == 2 }
        let tab = model.tabs[0]
        model.setVolume(0.2, for: tab); model.setVolume(0.8, for: tab)
        let command = try await readCommand(fd)
        try write(["version": 1, "type": "error", "requestID": command.requestID!, "error": "Player unavailable"], to: fd)
        try await until { model.pending.isEmpty && model.requestedVolumes.isEmpty }
        XCTAssertEqual(model.tabs[0].volume, 1)
        model.setVolume(0.3, for: tab); model.setVolume(0.9, for: tab)
        _ = try await readCommand(fd)
        state["session"] = "replacement"; try write(state, to: fd)
        try await until { model.pending.isEmpty && model.requestedVolumes.isEmpty }
        model.setVolume(0.4, for: tab); model.setVolume(0.7, for: tab)
        _ = try await readCommand(fd)
        shutdown(fd, SHUT_RDWR)
        try await until { !model.connected && model.pending.isEmpty && model.requestedVolumes.isEmpty }
        model.setVolume(0.5, for: tab)
        XCTAssertTrue(model.requestedVolumes.isEmpty)
    }

    private func sliderState() -> [String: Any] {
        ["version": 1, "type": "state", "mode": "automatic-sites", "session": "browser",
         "tabs": [7, 8].map { id in ["id": id, "title": "Player \(id)", "domain": "example.com",
            "audible": true, "controlled": true, "canMute": true, "volume": 1.0,
            "muted": false, "playing": true, "canPlay": false, "canPause": true] as [String: Any] }]
    }

    private func write(_ value: [String: Any], to fd: Int32) throws {
        try BridgeFrame.write(JSONSerialization.data(withJSONObject: value), to: fd)
    }

    private func readCommand(_ fd: Int32) async throws -> BridgeMessage {
        try await Task.detached {
            while let data = try BridgeFrame.read(fd) {
                let message = try BridgeMessage.decode(data)
                if message.type != "ready" { return message }
            }
            throw BridgeError.invalidFrame
        }.value
    }
    @MainActor
    func testPlaybackRequiresCapabilityAndWaitsForMatchingConfirmation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = ChromeTabModel(socketPath: directory.appendingPathComponent("play.sock").path)
        defer { model.stop(); try? FileManager.default.removeItem(at: directory) }
        let fd = try LocalSocket.connect(path: directory.appendingPathComponent("play.sock").path)
        defer { close(fd) }
        let state = #"{"version":1,"type":"state","mode":"automatic-sites","session":"browser","tabs":[{"id":7,"title":"Music","domain":"music.youtube.com","audible":false,"controlled":true,"canMute":true,"volume":0.3,"muted":true,"playing":true,"canPlay":false,"canPause":true}]}"#
        try BridgeFrame.write(Data(state.utf8), to: fd)
        try await until { model.connected && model.tabs.count == 1 }
        var tab = try XCTUnwrap(model.tabs.first)
        XCTAssertFalse(model.status.contains("Reload"))
        model.setPlayback("play", for: tab)
        model.setPlayback("toggle", for: tab)
        XCTAssertTrue(model.pending.isEmpty)
        var legacy = tab; legacy.canPause = nil
        model.setPlayback("pause", for: legacy)
        XCTAssertTrue(model.pending.isEmpty)
        model.setPlayback("pause", for: tab)
        XCTAssertNotNil(model.pending[7])
        XCTAssertEqual(model.tabs.first?.playing, true)
        let command = try await Task.detached { () throws -> BridgeMessage in
            _ = try BridgeFrame.read(fd)
            return try BridgeMessage.decode(XCTUnwrap(BridgeFrame.read(fd)))
        }.value
        XCTAssertEqual(command.type, "playback")
        XCTAssertEqual(command.action, "pause")
        XCTAssertNil(command.volume); XCTAssertNil(command.muted)
        try BridgeFrame.write(Data(state.utf8), to: fd)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNotNil(model.pending[7])
        var ack = try JSONSerialization.jsonObject(with: Data(state.utf8)) as! [String: Any]
        ack["requestID"] = command.requestID
        var tabs = ack["tabs"] as! [[String: Any]]
        tabs[0]["playing"] = false; tabs[0]["canPause"] = false; tabs[0]["canPlay"] = true
        ack["tabs"] = tabs
        try BridgeFrame.write(JSONSerialization.data(withJSONObject: ack), to: fd)
        try await until { model.pending.isEmpty && model.tabs.first?.playing == false }
        tab = try XCTUnwrap(model.tabs.first)
        XCTAssertEqual(tab.volume, 0.3); XCTAssertTrue(tab.muted)
        model.setPlayback("play", for: tab)
        try await until({ model.error != nil && model.pending.isEmpty }, seconds: 5)
        XCTAssertTrue(model.requestedVolumes.isEmpty)
        XCTAssertEqual(model.tabs.first?.playing, false)
        shutdown(fd, SHUT_RDWR)
        try await until { !model.connected }
        model.setPlayback("play", for: tab)
        XCTAssertTrue(model.pending.isEmpty)
    }
    @MainActor
    func testAutomaticMuteOnlyTabCannotSendVolumeAndWaitsForAcknowledgement() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = directory.appendingPathComponent("mute.sock").path
        let model = ChromeTabModel(socketPath: path)
        defer { model.stop(); try? FileManager.default.removeItem(at: directory) }
        let fd = try LocalSocket.connect(path: path)
        defer { close(fd) }
        let state = #"{"version":1,"type":"state","mode":"automatic-sites","session":"browser","tabs":[{"id":2,"title":"YouTube","domain":"www.youtube.com","audible":true,"controlled":false,"canMute":true,"controlMode":"page","volume":1,"muted":false,"issue":"Waiting for player"}]}"#
        try BridgeFrame.write(Data(state.utf8), to: fd)
        try await until { model.connected && model.tabs.count == 1 }
        let tab = try XCTUnwrap(model.tabs.first)
        XCTAssertTrue(model.status.contains("Reload older pages"))
        model.setVolume(0.3, for: tab)
        XCTAssertTrue(model.pending.isEmpty)
        model.toggleMute(tab)
        XCTAssertNotNil(model.pending[2])
        let command = try await Task.detached { () throws -> BridgeMessage in
            _ = try BridgeFrame.read(fd) // ready
            return try BridgeMessage.decode(XCTUnwrap(BridgeFrame.read(fd)))
        }.value
        XCTAssertEqual(command.volume, 1)
        XCTAssertEqual(command.muted, true)
        try BridgeFrame.write(Data(state.utf8), to: fd) // Unsolicited state is not an acknowledgement.
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNotNil(model.pending[2])
        var ack = try JSONSerialization.jsonObject(with: Data(state.utf8)) as! [String: Any]
        ack["requestID"] = command.requestID
        var tabs = ack["tabs"] as! [[String: Any]]
        tabs[0]["muted"] = true; ack["tabs"] = tabs
        try BridgeFrame.write(JSONSerialization.data(withJSONObject: ack), to: fd)
        try await until { model.pending.isEmpty && model.tabs.first?.muted == true }
        XCTAssertTrue(model.status.contains("automatic"))
    }

    @MainActor
    private func until(_ predicate: () -> Bool, seconds: Double = 2) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !predicate() && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(predicate())
    }

    @MainActor
    func testConfirmedStateTimeoutAndDisconnectWithoutTouchingAudio() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = directory.appendingPathComponent("model.sock").path
        let model = ChromeTabModel(socketPath: path)
        defer { model.stop(); try? FileManager.default.removeItem(at: directory) }
        let fd = try LocalSocket.connect(path: path)
        defer { close(fd) }
        let state = #"{"version":1,"type":"state","session":"browser","tabs":[{"id":1,"title":"Music","domain":"example.com","audible":true,"controlled":true,"volume":1,"muted":false}]}"#
        try BridgeFrame.write(Data(state.utf8), to: fd)
        try await until { model.connected && model.tabs.count == 1 }
        let initial = try XCTUnwrap(model.tabs.first)
        model.setVolume(0.3, for: initial)
        XCTAssertEqual(model.tabs.first?.volume, 1, "Must not display an unconfirmed gain")
        XCTAssertNotNil(model.pending[1])
        let command = try await Task.detached { () throws -> BridgeMessage in
            _ = try BridgeFrame.read(fd) // ready
            return try BridgeMessage.decode(XCTUnwrap(BridgeFrame.read(fd)))
        }.value
        XCTAssertEqual(command.type, "set")
        XCTAssertEqual(command.volume, 0.3)
        let confirmed = try JSONSerialization.jsonObject(with: Data(state.utf8)) as! [String: Any]
        var ack = confirmed
        ack["requestID"] = command.requestID
        var tabs = ack["tabs"] as! [[String: Any]]
        tabs[0]["volume"] = 0.3
        ack["tabs"] = tabs
        try BridgeFrame.write(JSONSerialization.data(withJSONObject: ack), to: fd)
        try await until { model.pending.isEmpty && model.tabs.first?.volume == 0.3 }
        model.setVolume(0.4, for: try XCTUnwrap(model.tabs.first))
        model.setVolume(0.9, for: try XCTUnwrap(model.tabs.first))
        try await until({ model.error != nil && model.pending.isEmpty }, seconds: 5)
        XCTAssertTrue(model.requestedVolumes.isEmpty, "Timeout discards the queued drag intent")
        XCTAssertEqual(model.tabs.first?.volume, 0.3, "Timeout must preserve the last confirmed value")
        shutdown(fd, SHUT_RDWR)
        try await until { !model.connected }
        XCTAssertTrue(model.pending.isEmpty)
        XCTAssertEqual(model.tabs.first?.volume, 0.3)
    }
}
