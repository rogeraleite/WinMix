import CoreAudio
import XCTest
@testable import WinMix

private final class FakeTap: MixerAudioTap {
    var gain: Float = 1
    var holdsMuteWithoutIO = false
    var processIDs: [AudioObjectID]
    var outputUID: String?
    var diagnostics = ProcessVolumeTap.Diagnostics()
    var routeGeneration = 0
    var moves: [String] = []
    var failsMoves = false
    var failsStart = false
    var failsProcessUpdates = false
    var asyncMoves = false
    var pendingOutputUID: String?
    var routeFailure: String?
    var stalled = false
    var stopped = false
    init(_ ids: [AudioObjectID]) { processIDs = ids }
    func start(outputUID: String?) throws {
        if failsStart { throw SpikeError("Test start failure") }
        self.outputUID = outputUID
        routeGeneration += 1
    }
    func moveOutput(to uid: String) throws {
        if pendingOutputUID == uid { return }
        if pendingOutputUID != nil, outputUID == uid {
            pendingOutputUID = nil
            routeFailure = nil
            return
        }
        moves.append(uid)
        if failsMoves { throw SpikeError("Test route failure") }
        routeFailure = nil
        if asyncMoves {
            pendingOutputUID = uid
            return
        }
        outputUID = uid
        routeGeneration += 1
        stalled = false
    }
    func setProcesses(_ ids: [AudioObjectID]) throws {
        if failsProcessUpdates { throw SpikeError("Test process update failure") }
        processIDs = ids
    }
    func checkStalled() -> Bool { stalled }
    func takeMeters() -> ProcessVolumeTap.Meters { .init() }
    func simulateStall() { stalled = true }
    func stop() { stopped = true; outputUID = nil; pendingOutputUID = nil; routeFailure = nil }
    func completePendingMove() {
        guard let pendingOutputUID else { return }
        outputUID = pendingOutputUID
        self.pendingOutputUID = nil
        routeGeneration += 1
        stalled = false
    }
    func failPendingMove() {
        pendingOutputUID = nil
        routeFailure = "The selected output did not start delivering audio."
    }
}

private final class RoutingEnvironment {
    let speakers = AudioOutputDevice(uid: "speakers", name: "Mac speakers")
    let headphones = AudioOutputDevice(uid: "headphones", name: "Headphones")
    let usb = AudioOutputDevice(uid: "usb", name: "USB audio")
    var devices: [AudioOutputDevice]?
    var system: String? = "speakers"
    var taps: [FakeTap] = []
    var failStart = false
    init() { devices = [speakers, headphones, usb] }
    func runtime() -> MixerRuntime {
        MixerRuntime(outputs: { self.devices }, defaultOutput: { self.system }, makeTap: { ids, _ in
            let tap = FakeTap(ids)
            tap.failsStart = self.failStart
            self.taps.append(tap)
            return tap
        }, observesSystem: false)
    }
}

@MainActor
final class MixerRoutingTests: XCTestCase {
    private let music = AudioProcess(id: 90001, pid: -90001, bundleID: "test.music", isPlaying: true)
    private let chat = AudioProcess(id: 90002, pid: -90002, bundleID: "test.chat", isPlaying: true)

    func testLegacySettingsDecodeAndExplicitUnityRoutePersists() throws {
        let legacy = Data(#"{"test.music":{"volume":0.4,"isMuted":true}}"#.utf8)
        let decoded = try JSONDecoder().decode([String: VolumeSetting].self, from: legacy)
        XCTAssertEqual(decoded["test.music"], VolumeSetting(volume: 0.4, isMuted: true))
        let suite = "WinMixRoutingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let pinned = VolumeSetting(outputUID: "headphones", outputName: "Headphones")
        SavedSettings.save(["test.music": pinned, "pid:42": pinned, "test.default": .init()], to: defaults)
        XCTAssertEqual(SavedSettings.load(from: defaults), ["test.music": pinned])
        let env = RoutingEnvironment()
        let model = MixerModel(defaults: defaults, runtime: env.runtime())
        model.reconcile([music])
        XCTAssertEqual(env.taps.first?.outputUID, "headphones")
        model.setOutput(nil, for: try XCTUnwrap(model.rows.first))
        XCTAssertTrue(SavedSettings.load(from: defaults).isEmpty)
        XCTAssertEqual(model.activeTapCount, 0)
    }

    func testUnityDefaultBypassesButChoosingAnOutputCreatesAndResetStopsTap() throws {
        let env = RoutingEnvironment()
        let model = MixerModel(defaults: nil, runtime: env.runtime())
        model.reconcile([music])
        let row = try XCTUnwrap(model.rows.first)
        XCTAssertEqual(model.activeTapCount, 0)
        model.setOutput("headphones", for: row)
        let tap = try XCTUnwrap(env.taps.first)
        XCTAssertEqual(tap.outputUID, "headphones")
        XCTAssertEqual(tap.gain, 1)
        XCTAssertTrue(tap.holdsMuteWithoutIO)
        model.setOutput(nil, for: row)
        XCTAssertTrue(tap.stopped)
        XCTAssertEqual(model.activeTapCount, 0)
        model.setOutput("missing", for: row)
        XCTAssertNil(model.setting(for: row).outputUID)
    }

    func testIndependentDestinationsAndDefaultChangeOnlyMovesFollowingApp() throws {
        let env = RoutingEnvironment()
        let model = MixerModel(defaults: nil, runtime: env.runtime())
        model.reconcile([music, chat])
        let musicRow = try XCTUnwrap(model.rows.first { $0.key == music.bundleID })
        let chatRow = try XCTUnwrap(model.rows.first { $0.key == chat.bundleID })
        model.setOutput("headphones", for: musicRow)
        model.setVolume(0.4, for: chatRow)
        let pinned = env.taps[0], following = env.taps[1]
        XCTAssertEqual(following.outputUID, "speakers")
        env.system = "usb"
        model.refreshOutputs()
        XCTAssertEqual(pinned.outputUID, "headphones")
        XCTAssertTrue(pinned.moves.isEmpty)
        XCTAssertEqual(following.outputUID, "usb")
        XCTAssertEqual(following.gain, 0.4)
        XCTAssertEqual(model.outputName, "USB audio")
    }

    func testDisconnectFallsBackFollowsSystemThenReturnsWithoutLosingMuteOrChoice() throws {
        let env = RoutingEnvironment()
        let model = MixerModel(defaults: nil, runtime: env.runtime())
        model.reconcile([music])
        let row = try XCTUnwrap(model.rows.first)
        model.setVolume(0.35, for: row)
        model.setOutput("headphones", for: row)
        model.toggleMute(row)
        let tap = try XCTUnwrap(env.taps.first)
        env.devices = [env.speakers, env.usb]
        model.refreshOutputs()
        XCTAssertEqual(tap.outputUID, "speakers")
        XCTAssertTrue(model.outputLabel(for: row).contains("disconnected"))
        XCTAssertEqual(model.setting(for: row).outputUID, "headphones")
        XCTAssertEqual(tap.gain, 0)
        env.system = "usb"
        model.refreshOutputs()
        XCTAssertEqual(tap.outputUID, "usb")
        env.devices?.append(env.headphones)
        model.refreshOutputs()
        XCTAssertEqual(tap.outputUID, "headphones")
        XCTAssertEqual(model.setting(for: row).volume, 0.35)
        XCTAssertTrue(model.setting(for: row).isMuted)
        model.toggleMute(row)
        XCTAssertEqual(tap.gain, 0.35)
    }

    func testFailedMoveRetainsWorkingRouteAndRetriesWithHonestState() throws {
        let env = RoutingEnvironment()
        let model = MixerModel(defaults: nil, runtime: env.runtime())
        model.reconcile([music])
        let row = try XCTUnwrap(model.rows.first)
        model.setVolume(0.6, for: row)
        let tap = try XCTUnwrap(env.taps.first)
        tap.failsMoves = true
        model.setOutput("headphones", for: row)
        XCTAssertEqual(tap.outputUID, "speakers")
        XCTAssertEqual(model.setting(for: row).outputUID, "headphones")
        XCTAssertTrue(model.outputLabel(for: row).contains("retrying"))
        XCTAssertTrue(model.outputHelp(for: row).contains("Still using Mac speakers"))
        tap.failsMoves = false
        model.checkRoutes()
        XCTAssertEqual(tap.outputUID, "headphones")
        XCTAssertNil(model.routingFailures[row.key])
        XCTAssertNil(model.error)
        XCTAssertEqual(tap.gain, 0.6)
    }

    func testReturningToWorkingDestinationClearsFailedMoveWithoutRebuilding() throws {
        let env = RoutingEnvironment()
        let model = MixerModel(defaults: nil, runtime: env.runtime())
        model.reconcile([music])
        let row = try XCTUnwrap(model.rows.first)
        model.setVolume(0.6, for: row)
        let tap = try XCTUnwrap(env.taps.first)
        tap.failsMoves = true
        model.setOutput("headphones", for: row)
        XCTAssertNotNil(model.routingFailures[row.key])
        XCTAssertNotNil(model.error)
        XCTAssertEqual(tap.outputUID, "speakers")
        let generation = tap.routeGeneration
        let moves = tap.moves

        model.setOutput("speakers", for: row)

        XCTAssertNil(model.routingFailures[row.key])
        XCTAssertNil(model.error)
        XCTAssertFalse(model.outputLabel(for: row).contains("retrying"))
        XCTAssertEqual(model.setting(for: row).outputUID, "speakers")
        XCTAssertEqual(tap.outputUID, "speakers")
        XCTAssertEqual(tap.routeGeneration, generation)
        XCTAssertEqual(tap.moves, moves)
        XCTAssertEqual(env.taps.count, 1)
        XCTAssertFalse(tap.stopped)
    }

    func testPendingMoveKeepsEffectiveOutputAndDoesNotRestartBeforeConfirmation() throws {
        let env = RoutingEnvironment()
        let model = MixerModel(defaults: nil, runtime: env.runtime())
        model.reconcile([music])
        let row = try XCTUnwrap(model.rows.first)
        model.setVolume(0.6, for: row)
        let tap = try XCTUnwrap(env.taps.first)
        tap.asyncMoves = true
        model.setOutput("headphones", for: row)

        XCTAssertEqual(tap.outputUID, "speakers")
        XCTAssertEqual(tap.pendingOutputUID, "headphones")
        XCTAssertTrue(model.outputLabel(for: row).contains("connecting"))
        XCTAssertTrue(model.outputHelp(for: row).contains("Still using Mac speakers"))
        XCTAssertEqual(tap.routeGeneration, 1)
        model.checkRoutes()
        model.checkRoutes()
        XCTAssertEqual(tap.moves, ["headphones"])

        tap.completePendingMove()
        model.checkRoutes()

        XCTAssertEqual(tap.outputUID, "headphones")
        XCTAssertNil(model.pendingOutputs[row.key])
        XCTAssertFalse(model.outputLabel(for: row).contains("connecting"))
        XCTAssertNil(model.routingFailures[row.key])
        XCTAssertNil(model.error)
    }

    func testPendingFailureRetriesWithoutClearingErrorUntilOutputIsConfirmed() throws {
        let env = RoutingEnvironment()
        let model = MixerModel(defaults: nil, runtime: env.runtime())
        model.reconcile([music])
        let row = try XCTUnwrap(model.rows.first)
        model.setVolume(0.6, for: row)
        let tap = try XCTUnwrap(env.taps.first)
        tap.asyncMoves = true
        model.setOutput("headphones", for: row)
        tap.failPendingMove()

        model.checkRoutes()

        XCTAssertEqual(tap.outputUID, "speakers")
        XCTAssertEqual(tap.pendingOutputUID, "headphones")
        XCTAssertEqual(tap.moves, ["headphones", "headphones"])
        XCTAssertNotNil(model.routingFailures[row.key])
        XCTAssertNotNil(model.error)
        XCTAssertTrue(model.outputHelp(for: row).contains("Still using Mac speakers"))
        model.checkRoutes()
        XCTAssertEqual(tap.moves.count, 2)
        tap.completePendingMove()
        model.checkRoutes()
        XCTAssertNil(model.routingFailures[row.key])
        XCTAssertNil(model.error)
    }

    func testSelectingEffectiveOutputCancelsAnotherPendingDestination() throws {
        let env = RoutingEnvironment()
        let model = MixerModel(defaults: nil, runtime: env.runtime())
        model.reconcile([music])
        let row = try XCTUnwrap(model.rows.first)
        model.setVolume(0.6, for: row)
        let tap = try XCTUnwrap(env.taps.first)
        tap.asyncMoves = true
        model.setOutput("headphones", for: row)

        model.setOutput("speakers", for: row)

        XCTAssertEqual(tap.outputUID, "speakers")
        XCTAssertNil(tap.pendingOutputUID)
        XCTAssertNil(model.pendingOutputs[row.key])
        XCTAssertEqual(tap.moves, ["headphones"])
        XCTAssertEqual(tap.routeGeneration, 1)
        XCTAssertNil(model.error)
        tap.completePendingMove()
        XCTAssertEqual(tap.outputUID, "speakers", "A canceled move must not later commit")
    }

    func testResetToUnityDefaultStopsAndCancelsPendingDestination() throws {
        let env = RoutingEnvironment()
        let model = MixerModel(defaults: nil, runtime: env.runtime())
        model.reconcile([music])
        let row = try XCTUnwrap(model.rows.first)
        model.setOutput("speakers", for: row)
        let tap = try XCTUnwrap(env.taps.first)
        tap.asyncMoves = true
        model.setOutput("headphones", for: row)
        XCTAssertEqual(tap.pendingOutputUID, "headphones")

        model.setOutput(nil, for: row)

        XCTAssertEqual(model.activeTapCount, 0)
        XCTAssertTrue(tap.stopped)
        XCTAssertNil(tap.pendingOutputUID)
        XCTAssertNil(model.pendingOutputs[row.key])
        XCTAssertNil(model.error)
        tap.completePendingMove()
        XCTAssertNil(tap.outputUID)
    }

    func testExitingAfterFailedStartClearsFailureWithoutAnActiveTap() throws {
        let env = RoutingEnvironment()
        env.failStart = true
        let model = MixerModel(defaults: nil, runtime: env.runtime())
        model.reconcile([music])
        let row = try XCTUnwrap(model.rows.first)
        model.setOutput("headphones", for: row)
        XCTAssertEqual(model.activeTapCount, 0)
        XCTAssertNotNil(model.routingFailures[row.key])
        XCTAssertNotNil(model.error)

        model.reconcile([])

        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertTrue(model.routingFailures.isEmpty)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.activeTapCount, 0)
        XCTAssertEqual(env.taps.count, 1)
    }

    func testFailedStartDoesNotLoopOnUnchangedDeviceEventsAndRecoversOnInventoryChange() throws {
        let env = RoutingEnvironment()
        env.failStart = true
        let model = MixerModel(defaults: nil, runtime: env.runtime())
        model.reconcile([music])
        let row = try XCTUnwrap(model.rows.first)
        model.setOutput("headphones", for: row)
        XCTAssertEqual(env.taps.count, 1)
        model.refreshOutputs()
        model.refreshOutputs()
        XCTAssertEqual(env.taps.count, 1, "Private aggregate events must not loop failed tap creation")
        env.failStart = false
        env.devices = [env.speakers, env.headphones]
        model.refreshOutputs()
        XCTAssertEqual(env.taps.count, 2)
        XCTAssertEqual(model.activeTapCount, 1)
        XCTAssertNil(model.routingFailures[row.key])
    }

    func testHelperChangesAndDeviceReadFailureKeepExistingRoute() throws {
        let env = RoutingEnvironment()
        let model = MixerModel(defaults: nil, runtime: env.runtime())
        model.reconcile([music])
        let row = try XCTUnwrap(model.rows.first)
        model.setOutput("headphones", for: row)
        model.setVolume(0.5, for: row)
        let helper = AudioProcess(id: 90003, pid: -90003, bundleID: music.bundleID, isPlaying: false)
        model.reconcile([music, helper])
        let tap = try XCTUnwrap(env.taps.first)
        XCTAssertEqual(Set(tap.processIDs), [music.id, helper.id])
        XCTAssertEqual(tap.outputUID, "headphones")
        XCTAssertEqual(tap.gain, 0.5)
        env.devices = nil
        model.refreshOutputs()
        XCTAssertEqual(tap.outputUID, "headphones")
        XCTAssertEqual(model.outputDevices.count, 3)
        model.reconcile([])
        XCTAssertTrue(tap.stopped)
        XCTAssertEqual(model.activeTapCount, 0)
    }

    func testFailedHelperUpdateKeepsWorkingTapAndHealthCheckRetries() throws {
        let env = RoutingEnvironment()
        let model = MixerModel(defaults: nil, runtime: env.runtime())
        model.reconcile([music])
        let row = try XCTUnwrap(model.rows.first)
        model.setVolume(0.4, for: row)
        let original = try XCTUnwrap(env.taps.first)
        original.failsProcessUpdates = true
        env.failStart = true
        let helper = AudioProcess(id: 90004, pid: -90004, bundleID: music.bundleID, isPlaying: false)
        model.reconcile([music, helper])
        XCTAssertFalse(original.stopped, "A failed helper update must not discard the working route")
        XCTAssertEqual(model.activeTapCount, 1)
        XCTAssertEqual(env.taps.count, 1)
        XCTAssertEqual(original.outputUID, "speakers")
        XCTAssertEqual(original.gain, 0.4)
        XCTAssertNotNil(model.routingFailures[row.key])
        original.failsProcessUpdates = false
        model.checkRoutes()
        XCTAssertEqual(Set(original.processIDs), [music.id, helper.id])
        XCTAssertNil(model.routingFailures[row.key])
        XCTAssertNil(model.error)
        XCTAssertFalse(original.stopped)
    }

    func testOutputCatalogExcludesPrivateHiddenDeadAndInputOnlyDevices() {
        XCTAssertTrue(AudioOutputDevice.isSelectable(name: "Headphones", alive: true, hidden: false, hasOutput: true))
        for name in ["WinMix (Music)", "MacVolume (Chrome)"] {
            XCTAssertFalse(AudioOutputDevice.isSelectable(name: name, alive: true, hidden: false, hasOutput: true))
        }
        XCTAssertFalse(AudioOutputDevice.isSelectable(name: "Microphone", alive: true, hidden: false, hasOutput: false))
        XCTAssertFalse(AudioOutputDevice.isSelectable(name: "Gone", alive: false, hidden: false, hasOutput: true))
        XCTAssertFalse(AudioOutputDevice.isSelectable(name: "Private", alive: true, hidden: true, hasOutput: true))
    }
}
