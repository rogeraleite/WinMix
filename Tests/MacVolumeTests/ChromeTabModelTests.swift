import XCTest
import Darwin
import ChromeSupport
@testable import MacVolume

final class ChromeTabModelTests: XCTestCase {
    @MainActor
    func testAutomaticMuteOnlyTabCannotSendVolumeAndWaitsForAcknowledgement() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = directory.appendingPathComponent("mute.sock").path
        let model = ChromeTabModel(socketPath: path)
        defer { model.stop(); try? FileManager.default.removeItem(at: directory) }
        let fd = try LocalSocket.connect(path: path)
        defer { close(fd) }
        let state = #"{"version":1,"type":"state","mode":"automatic-youtube","session":"browser","tabs":[{"id":2,"title":"YouTube","domain":"www.youtube.com","audible":true,"controlled":false,"canMute":true,"controlMode":"page","volume":1,"muted":false,"issue":"Waiting for player"}]}"#
        try BridgeFrame.write(Data(state.utf8), to: fd)
        try await until { model.connected && model.tabs.count == 1 }
        let tab = try XCTUnwrap(model.tabs.first)
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
        try await until({ model.error != nil && model.pending.isEmpty }, seconds: 5)
        XCTAssertEqual(model.tabs.first?.volume, 0.3, "Timeout must preserve the last confirmed value")
        shutdown(fd, SHUT_RDWR)
        try await until { !model.connected }
        XCTAssertTrue(model.pending.isEmpty)
        XCTAssertEqual(model.tabs.first?.volume, 0.3)
    }
}
