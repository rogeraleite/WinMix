import XCTest
@testable import WinMix

final class AudioRouteHandoffTests: XCTestCase {
    private final class Route {
        var hasIO = false
        let processIDs: [UInt32]
        init(processIDs: [UInt32] = []) { self.processIDs = processIDs }
    }

    private let now = Date(timeIntervalSince1970: 100)

    func testReplacementDoesNotRetireWorkingRouteUntilFirstIO() throws {
        let handoff = AudioRouteHandoff<Route>(isReady: { $0.hasIO })
        var old: Route? = Route()
        weak var oldReference = old
        handoff.start(old!, outputUID: "speakers")
        old = nil
        let replacement = Route()

        try handoff.move(to: "headphones", now: now) { replacement }
        XCTAssertEqual(handoff.outputUID, "speakers")
        XCTAssertEqual(handoff.pendingOutputUID, "headphones")
        XCTAssertNotNil(oldReference)
        XCTAssertEqual(handoff.poll(now: now.addingTimeInterval(1)), .waiting)

        replacement.hasIO = true
        XCTAssertEqual(handoff.poll(now: now.addingTimeInterval(2)), .activated)
        XCTAssertEqual(handoff.outputUID, "headphones")
        XCTAssertNil(handoff.pendingOutputUID)
        XCTAssertNil(oldReference)
        XCTAssertNil(handoff.routeFailure)
    }

    func testTimeoutDiscardsUnreadReplacementAndKeepsWorkingRoute() throws {
        let handoff = AudioRouteHandoff<Route>(isReady: { $0.hasIO })
        let old = Route()
        handoff.start(old, outputUID: "speakers")
        weak var pendingReference: Route?
        try handoff.move(to: "headphones", now: now) {
            let route = Route()
            pendingReference = route
            return route
        }

        XCTAssertEqual(handoff.poll(now: now.addingTimeInterval(5)), .failed)
        XCTAssertTrue(handoff.activeRoute === old)
        XCTAssertEqual(handoff.outputUID, "speakers")
        XCTAssertNil(pendingReference)
        XCTAssertNil(handoff.pendingOutputUID)
        XCTAssertNotNil(handoff.routeFailure)
        XCTAssertEqual(handoff.poll(now: now.addingTimeInterval(10)), .idle)
        XCTAssertNotNil(handoff.routeFailure, "The model must be able to observe timeout after the polling callback")
    }

    func testRepeatedTargetDoesNotConstructDuplicateAndSelectionCanCancel() throws {
        let handoff = AudioRouteHandoff<Route>(isReady: { $0.hasIO })
        handoff.start(Route(), outputUID: "speakers")
        var creations = 0
        try handoff.move(to: "headphones", now: now) { creations += 1; return Route() }
        try handoff.move(to: "headphones", now: now.addingTimeInterval(1)) { creations += 1; return Route() }
        XCTAssertEqual(creations, 1)
        try handoff.move(to: "speakers", now: now.addingTimeInterval(2)) { creations += 1; return Route() }
        XCTAssertEqual(creations, 1, "Choosing the existing working output cancels the pending destination")
        XCTAssertNil(handoff.pendingOutputUID)
        XCTAssertEqual(handoff.outputUID, "speakers")
        XCTAssertEqual(handoff.poll(now: now.addingTimeInterval(10)), .idle)
    }

    func testCreationFailureAndRetryKeepWorkingRouteUntilRetryIO() throws {
        let handoff = AudioRouteHandoff<Route>(isReady: { $0.hasIO })
        let old = Route()
        handoff.start(old, outputUID: "speakers")
        XCTAssertThrowsError(try handoff.move(to: "headphones", now: now) { throw SpikeError("Unavailable") })
        XCTAssertTrue(handoff.activeRoute === old)
        XCTAssertNotNil(handoff.routeFailure)
        let retry = Route()
        try handoff.move(to: "headphones", now: now.addingTimeInterval(1)) { retry }
        XCTAssertNil(handoff.routeFailure)
        retry.hasIO = true
        XCTAssertEqual(handoff.poll(now: now.addingTimeInterval(2)), .activated)
        XCTAssertTrue(handoff.activeRoute === retry)
    }

    func testNewDestinationSupersedesPendingWithoutRetiringActive() throws {
        let handoff = AudioRouteHandoff<Route>(isReady: { $0.hasIO })
        let active = Route()
        handoff.start(active, outputUID: "speakers")
        weak var abandonedReference: Route?
        try handoff.move(to: "headphones", now: now) {
            let abandoned = Route()
            abandonedReference = abandoned
            return abandoned
        }
        let replacement = Route()
        try handoff.move(to: "usb", now: now.addingTimeInterval(1)) { replacement }
        XCTAssertNil(abandonedReference)
        XCTAssertTrue(handoff.activeRoute === active)
        XCTAssertEqual(handoff.outputUID, "speakers")
        XCTAssertEqual(handoff.pendingOutputUID, "usb")
        replacement.hasIO = true
        XCTAssertEqual(handoff.poll(now: now.addingTimeInterval(2)), .activated)
        XCTAssertEqual(handoff.outputUID, "usb")
    }

    func testSelectingWorkingOutputAcknowledgesFailedOtherTargetWithoutRebuild() throws {
        let handoff = AudioRouteHandoff<Route>(isReady: { $0.hasIO })
        let active = Route()
        handoff.start(active, outputUID: "speakers")
        XCTAssertThrowsError(try handoff.move(to: "headphones", now: now) { throw SpikeError("Unavailable") })
        var creations = 0
        try handoff.move(to: "speakers", now: now.addingTimeInterval(1)) {
            creations += 1
            return Route()
        }
        XCTAssertEqual(creations, 0)
        XCTAssertTrue(handoff.activeRoute === active)
        XCTAssertNil(handoff.pendingOutputUID)
        XCTAssertNil(handoff.routeFailure)
    }

    func testFailedSameDeviceRebuildCanRetrySameDevice() throws {
        let handoff = AudioRouteHandoff<Route>(isReady: { $0.hasIO })
        let active = Route()
        handoff.start(active, outputUID: "speakers")
        try handoff.move(to: "speakers", now: now) { Route() }
        XCTAssertEqual(handoff.poll(now: now.addingTimeInterval(5)), .failed)
        XCTAssertNotNil(handoff.routeFailure)
        let retry = Route()
        try handoff.move(to: "speakers", now: now.addingTimeInterval(6)) { retry }
        XCTAssertTrue(handoff.pendingRoute === retry)
        XCTAssertTrue(handoff.activeRoute === active)
        XCTAssertNil(handoff.routeFailure)
    }

    func testCancelBeforeForcedSameDeviceRebuildCreatesFreshPendingRoute() throws {
        let handoff = AudioRouteHandoff<Route>(isReady: { $0.hasIO })
        let active = Route()
        handoff.start(active, outputUID: "speakers")
        weak var obsoletePending: Route?
        try handoff.move(to: "speakers", now: now) {
            let obsolete = Route()
            obsoletePending = obsolete
            return obsolete
        }

        // A helper update needs new membership even if its target UID has not
        // changed, so discard the candidate with obsolete membership first.
        handoff.cancelPending()
        let updated = Route()
        try handoff.move(to: "speakers", now: now.addingTimeInterval(1)) { updated }

        XCTAssertNil(obsoletePending)
        XCTAssertTrue(handoff.activeRoute === active)
        XCTAssertTrue(handoff.pendingRoute === updated)
        updated.hasIO = true
        XCTAssertEqual(handoff.poll(now: now.addingTimeInterval(2)), .activated)
        XCTAssertTrue(handoff.activeRoute === updated)
    }

    func testCancelRetainsEffectiveMembershipUntilFreshReplacementIsConfirmed() throws {
        let handoff = AudioRouteHandoff<Route>(isReady: { $0.hasIO })
        handoff.start(Route(processIDs: [1]), outputUID: "speakers")
        let desiredIDs: [UInt32] = [1, 2]
        try handoff.move(to: "headphones", now: now) { Route(processIDs: desiredIDs) }
        XCTAssertEqual(handoff.activeRoute?.processIDs, [1])
        XCTAssertEqual(handoff.pendingRoute?.processIDs, desiredIDs)

        try handoff.move(to: "speakers", now: now.addingTimeInterval(1)) {
            XCTFail("Canceling a destination should not construct a route")
            return Route()
        }
        XCTAssertNil(handoff.pendingRoute)
        XCTAssertEqual(handoff.activeRoute?.processIDs, [1],
                       "Canceled membership must not be reported as effective")

        let retry = Route(processIDs: desiredIDs)
        try handoff.move(to: "speakers", now: now.addingTimeInterval(2)) { retry }
        XCTAssertEqual(handoff.activeRoute?.processIDs, [1])
        retry.hasIO = true
        XCTAssertEqual(handoff.poll(now: now.addingTimeInterval(3)), .activated)
        XCTAssertEqual(handoff.activeRoute?.processIDs, desiredIDs)
    }

    func testStopReleasesBothRoutesAndMakesLaterPollIdle() throws {
        let handoff = AudioRouteHandoff<Route>(isReady: { $0.hasIO })
        weak var activeReference: Route?
        weak var pendingReference: Route?
        do {
            let active = Route()
            activeReference = active
            handoff.start(active, outputUID: "speakers")
            try handoff.move(to: "headphones", now: now) {
                let pending = Route()
                pendingReference = pending
                return pending
            }
        }
        handoff.stop()
        XCTAssertNil(activeReference)
        XCTAssertNil(pendingReference)
        XCTAssertNil(handoff.outputUID)
        XCTAssertNil(handoff.pendingOutputUID)
        XCTAssertNil(handoff.routeFailure)
        XCTAssertEqual(handoff.poll(now: now.addingTimeInterval(10)), .idle)
    }
}
