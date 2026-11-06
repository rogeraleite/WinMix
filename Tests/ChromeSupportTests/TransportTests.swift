import XCTest
import Darwin
@testable import ChromeSupport

final class TransportTests: XCTestCase {
    func testTrackCommandsAndConfirmedShuffleAreBackwardCompatibleAndStrict() throws {
        for action in ["previous", "next", "shuffle-on", "shuffle-off"] {
            let command = BridgeMessage(type: "transport", session: "s", requestID: "r", tabID: 1, action: action)
            XCTAssertEqual(try BridgeMessage.decode(command.encoded()).action, action)
        }
        for json in [
            #"{"version":1,"type":"transport","session":"s","requestID":"r","tabID":1,"action":"shuffle"}"#,
            #"{"version":1,"type":"transport","session":"s","requestID":"r","tabID":1,"action":"next","volume":0.4}"#,
            #"{"version":1,"type":"transport","session":"s","requestID":"r","tabID":1,"action":"next","muted":false}"#,
            #"{"version":1,"type":"transport","session":"s","requestID":"r","tabID":1}"#,
            #"{"version":1,"type":"playback","session":"s","requestID":"r","tabID":1,"action":"next"}"#
        ] { XCTAssertThrowsError(try BridgeMessage.decode(Data(json.utf8))) }
        let json = #"{"version":1,"type":"state","session":"s","tabs":[{"id":1,"title":"Music","domain":"music.youtube.com","audible":true,"controlled":true,"volume":0.4,"muted":false,"canNext":true,"canPrevious":false,"canShuffle":true,"shuffleEnabled":false}]}"#
        let tab = try XCTUnwrap(BridgeMessage.decode(Data(json.utf8)).tabs?.first)
        XCTAssertEqual(tab.canNext, true); XCTAssertEqual(tab.canPrevious, false); XCTAssertEqual(tab.shuffleEnabled, false)
        XCTAssertThrowsError(try BridgeMessage.decode(Data(json.replacingOccurrences(of: ",\"shuffleEnabled\":false", with: "").utf8)))
    }
    func testExplicitPlaybackCommandsAndLegacyCapabilities() throws {
        let command = BridgeMessage(type: "playback", session: "s", requestID: "r", tabID: 1, action: "pause")
        let decoded = try BridgeMessage.decode(command.encoded())
        XCTAssertEqual(decoded.action, "pause")
        XCTAssertNil(decoded.volume)
        XCTAssertNil(decoded.muted)
        for json in [
            #"{"version":1,"type":"playback","session":"s","requestID":"r","tabID":1,"action":"toggle"}"#,
            #"{"version":1,"type":"playback","session":"s","requestID":"r","tabID":1,"action":"play","volume":0.4}"#,
            #"{"version":1,"type":"playback","session":"s","requestID":"r","tabID":1,"action":"play","muted":false}"#,
            #"{"version":1,"type":"set","session":"s","requestID":"r","tabID":1,"volume":0.4,"muted":false,"action":"pause"}"#
        ] { XCTAssertThrowsError(try BridgeMessage.decode(Data(json.utf8))) }
        let legacy = Data(#"{"version":1,"type":"state","session":"s","tabs":[{"id":1,"title":"a","domain":"a","audible":true,"controlled":true,"volume":1,"muted":false}]}"#.utf8)
        XCTAssertNil(try BridgeMessage.decode(legacy).tabs?.first?.canPlay)
        let modern = Data(#"{"version":1,"type":"state","session":"s","tabs":[{"id":1,"title":"a","domain":"a","audible":false,"controlled":true,"volume":0,"muted":true,"playing":true,"canPlay":false,"canPause":true,"playbackIssue":"Blocked"}]}"#.utf8)
        let tab = try XCTUnwrap(BridgeMessage.decode(modern).tabs?.first)
        XCTAssertEqual(tab.playing, true)
        XCTAssertEqual(tab.canPause, true)
        XCTAssertEqual(tab.playbackIssue, "Blocked")
        let oversized = String(data: modern, encoding: .utf8)!.replacingOccurrences(of: "Blocked", with: String(repeating: "x", count: 513))
        XCTAssertThrowsError(try BridgeMessage.decode(Data(oversized.utf8)))
    }
    func testOptionalCaptureIssueIsBackwardCompatibleAndBounded() throws {
        let tab: [String: Any] = ["id": 1, "title": "Test", "domain": "example.com", "audible": false,
                                  "controlled": true, "volume": 0.3, "muted": true]
        func state(_ tab: [String: Any]) throws -> BridgeMessage {
            try BridgeMessage.decode(JSONSerialization.data(withJSONObject:
                ["version": 1, "type": "state", "session": "browser", "tabs": [tab]]))
        }
        XCTAssertNil(try state(tab).tabs?.first?.issue)
        var interrupted = tab
        interrupted["issue"] = "Output interrupted"
        let decoded = try state(interrupted).tabs?.first
        XCTAssertEqual(decoded?.issue, "Output interrupted")
        XCTAssertEqual(decoded?.volume, 0.3)
        XCTAssertEqual(decoded?.muted, true)
        interrupted["issue"] = String(repeating: "x", count: 513)
        XCTAssertThrowsError(try state(interrupted))
    }
    func testRejectsInvalidCommandsAndDuplicateTabs() throws {
        for json in [
            #"{"version":2,"type":"state","session":"s","tabs":[]}"#,
            #"{"version":1,"type":"set","session":"s","requestID":"r","tabID":1,"volume":2,"muted":false}"#,
            #"{"version":1,"type":"set","session":"s","tabID":1,"volume":0.5,"muted":false}"#,
            #"{"version":1,"type":"state","session":"s","tabs":[{"id":1,"title":"a","domain":"a","audible":true,"controlled":true,"volume":1,"muted":false},{"id":1,"title":"b","domain":"a","audible":true,"controlled":true,"volume":1,"muted":false}]}"#
        ] { XCTAssertThrowsError(try BridgeMessage.decode(Data(json.utf8))) }
    }

    func testCommandRoundTrip() throws {
        let message = BridgeMessage(type: "set", session: "browser", requestID: "request", tabID: 2, volume: 0.3, muted: true)
        let decoded = try BridgeMessage.decode(message.encoded())
        XCTAssertEqual(decoded.volume, 0.3)
        XCTAssertEqual(decoded.tabID, 2)
        XCTAssertEqual(decoded.muted, true)
    }

    func testFragmentedFrameAndCleanEOF() throws {
        var pair: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair), 0)
        defer { close(pair[0]); close(pair[1]) }
        let bytes: [UInt8] = [3, 0, 0, 0, 65, 66, 67]
        for byte in bytes { var b = byte; XCTAssertEqual(write(pair[0], &b, 1), 1) }
        shutdown(pair[0], SHUT_WR)
        XCTAssertEqual(try BridgeFrame.read(pair[1]), Data("ABC".utf8))
        XCTAssertNil(try BridgeFrame.read(pair[1]))
    }

    func testRejectsOversizedAndTruncatedFrames() throws {
        for bytes: [UInt8] in [[0, 0, 8, 0], [3, 0, 0, 0, 65], [1, 0]] {
            var pair: [Int32] = [0, 0]
            XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair), 0)
            bytes.withUnsafeBytes { _ = write(pair[0], $0.baseAddress, bytes.count) }
            shutdown(pair[0], SHUT_WR)
            XCTAssertThrowsError(try BridgeFrame.read(pair[1]))
            close(pair[0]); close(pair[1])
        }
    }

    func testPrivateSocketAndSingleListener() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = dir.appendingPathComponent("test.sock").path
        let listener = try LocalSocket.listen(path: path)
        defer { LocalSocket.closeListener(listener, path: path); try? FileManager.default.removeItem(at: dir) }
        XCTAssertThrowsError(try LocalSocket.listen(path: path))
        let client = try LocalSocket.connect(path: path)
        defer { close(client) }
        let server = accept(listener, nil, nil)
        defer { close(server) }
        XCTAssertTrue(LocalSocket.sameUser(server))
        let message = try BridgeMessage(type: "ready").encoded()
        try BridgeFrame.write(message, to: client)
        XCTAssertEqual(try BridgeMessage.decode(XCTUnwrap(BridgeFrame.read(server))).type, "ready")
        let attributes = try FileManager.default.attributesOfItem(atPath: dir.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testServerReceivesStateRejectsSecondProfileAndSendsShutdown() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = dir.appendingPathComponent("server.sock").path
        let received = expectation(description: "received state")
        let server = try ChromeSocketServer(path: path, received: { message in
            XCTAssertEqual(message.session, "browser")
            received.fulfill()
        }, disconnected: { _ in })
        server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: dir) }
        let client = try LocalSocket.connect(path: path)
        defer { close(client) }
        let state = Data(#"{"version":1,"type":"state","session":"browser","tabs":[]}"#.utf8)
        try BridgeFrame.write(state, to: client)
        wait(for: [received], timeout: 2)
        let second = try LocalSocket.connect(path: path)
        defer { close(second) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(second, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        let rejected = try BridgeMessage.decode(XCTUnwrap(BridgeFrame.read(second)))
        XCTAssertEqual(rejected.type, "error")
        server.send(BridgeMessage(type: "ready", session: "browser"))
        XCTAssertEqual(try BridgeMessage.decode(XCTUnwrap(BridgeFrame.read(client))).type, "ready")
        server.stop()
        XCTAssertEqual(try BridgeMessage.decode(XCTUnwrap(BridgeFrame.read(client))).type, "shutdown")
    }
}
