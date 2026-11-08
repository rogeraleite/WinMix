import Foundation

/// Owns the working route until a replacement proves it is delivering IO.
/// The caller polls on its control thread; readiness never blocks that thread.
final class AudioRouteHandoff<Route: AnyObject> {
    enum PollResult: Equatable { case idle, waiting, activated, failed }

    private struct Destination {
        let uid: String
        let route: Route
    }

    private var active: Destination?
    private var pending: Destination?
    private var deadline: Date?
    private var failedOutputUID: String?
    private let isReady: (Route) -> Bool
    private(set) var routeFailure: String?

    var activeRoute: Route? { active?.route }
    var pendingRoute: Route? { pending?.route }
    var outputUID: String? { active?.uid }
    var pendingOutputUID: String? { pending?.uid }

    init(isReady: @escaping (Route) -> Bool) { self.isReady = isReady }

    func start(_ route: Route, outputUID: String) {
        cancelPending()
        active = Destination(uid: outputUID, route: route)
    }

    /// Repeating a pending target is a no-op. Choosing the still-working output
    /// during a move cancels that move without creating a replacement.
    /// With no pending move, the same UID intentionally rebuilds a stalled route.
    func move(to uid: String, now: Date = Date(), timeout: TimeInterval = 5,
              makeRoute: () throws -> Route) throws {
        guard pendingOutputUID != uid else { return }
        let wasPending = pending != nil
        let acknowledgingOtherFailure = failedOutputUID != nil && failedOutputUID != uid
        cancelPending()
        if outputUID == uid && (wasPending || acknowledgingOtherFailure) { return }
        do {
            let route = try makeRoute()
            pending = Destination(uid: uid, route: route)
            deadline = now.addingTimeInterval(timeout)
        } catch {
            failedOutputUID = uid
            routeFailure = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func poll(now: Date = Date()) -> PollResult {
        guard let pending else { return .idle }
        if isReady(pending.route) {
            active = pending
            cancelPending()
            return .activated
        }
        guard let deadline, now >= deadline else { return .waiting }
        failPending("The selected output did not start delivering audio. The previous output is still active.")
        return .failed
    }

    func cancelPending() {
        pending = nil
        deadline = nil
        failedOutputUID = nil
        routeFailure = nil
    }

    func failPending(_ message: String) {
        let failedUID = pending?.uid
        cancelPending()
        failedOutputUID = failedUID
        routeFailure = message
    }

    func stop() {
        cancelPending()
        active = nil
    }
}
