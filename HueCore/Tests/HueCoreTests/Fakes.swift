import Foundation
import HueCore

/// Stubbed network seam: returns queued fixture responses and records requests.
final class StubHTTPTransport: HTTPTransport, @unchecked Sendable {
    private(set) var recordedRequests: [URLRequest] = []
    private var handlers: [(URLRequest) throws -> (Data, URLResponse)]

    init(handlers: [(URLRequest) throws -> (Data, URLResponse)] = []) {
        self.handlers = handlers
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        recordedRequests.append(request)
        guard !handlers.isEmpty else {
            throw URLError(.badServerResponse)
        }
        let handler = handlers.removeFirst()
        return try handler(request)
    }
}

/// Stub bridge whose outcomes and recorded calls are driven by the test.
final class StubHueBridgeClient: HueBridgeClient, @unchecked Sendable {
    var fetchResult: Result<[HueGroup], Error> = .success([])
    var setStateFailure: Error?
    var setBrightnessFailure: Error?

    private(set) var setStateCalls: [(groupID: String, on: Bool)] = []
    private(set) var setBrightnessCalls: [(groupID: String, brightness: Int)] = []
    private(set) var registerCalls: [String] = []

    func register(deviceType: String) async throws -> String {
        registerCalls.append(deviceType)
        return "registered-user"
    }

    func fetchGroups() async throws -> [HueGroup] {
        try fetchResult.get()
    }

    func setGroupState(groupID: String, on: Bool) async throws {
        setStateCalls.append((groupID, on))
        if let setStateFailure {
            throw setStateFailure
        }
    }

    func setGroupBrightness(groupID: String, brightness: Int) async throws {
        setBrightnessCalls.append((groupID, brightness))
        if let setBrightnessFailure {
            throw setBrightnessFailure
        }
    }
}

/// A bridge client whose per-group calls suspend until the test resolves them.
///
/// Lets a test drive two concurrent updates or an update plus a refresh, and
/// inspect the updater's optimistic state *while* a request is still pending,
/// then complete those requests in a chosen order.
final class SuspendingBridgeClient: HueBridgeClient, @unchecked Sendable {
    private struct SuspendedCall {
        let continuation: CheckedContinuation<Void, any Error>
    }

    var fetchResult: Result<[HueGroup], Error> = .success([])
    private(set) var setStateCalls: [(groupID: String, on: Bool)] = []
    private(set) var setBrightnessCalls: [(groupID: String, brightness: Int)] = []
    private(set) var registerCalls: [String] = []

    private let lock = NSLock()
    private var pendingState: [String: [SuspendedCall]] = [:]
    private var pendingBrightness: [String: [SuspendedCall]] = [:]
    /// Continuations parked while waiting for a target number of pending calls.
    private var stateWaiters: [String: [Waiter]] = [:]
    private var brightnessWaiters: [String: [Waiter]] = [:]

    private struct Waiter {
        let targetCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    func register(deviceType: String) async throws -> String {
        registerCalls.append(deviceType)
        return "registered-user"
    }

    func fetchGroups() async throws -> [HueGroup] {
        try fetchResult.get()
    }

    func setGroupState(groupID: String, on: Bool) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let toResume: [Waiter]
            lock.lock()
            setStateCalls.append((groupID, on))
            pendingState[groupID, default: []].append(
                SuspendedCall(continuation: continuation)
            )
            toResume = takeSatisfiedWaiters(
                for: groupID, pendingCount: pendingState[groupID]?.count ?? 0,
                waiters: &stateWaiters
            )
            lock.unlock()
            for waiter in toResume {
                waiter.continuation.resume()
            }
        }
    }

    func setGroupBrightness(groupID: String, brightness: Int) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let toResume: [Waiter]
            lock.lock()
            setBrightnessCalls.append((groupID, brightness))
            pendingBrightness[groupID, default: []].append(
                SuspendedCall(continuation: continuation)
            )
            toResume = takeSatisfiedWaiters(
                for: groupID, pendingCount: pendingBrightness[groupID]?.count ?? 0,
                waiters: &brightnessWaiters
            )
            lock.unlock()
            for waiter in toResume {
                waiter.continuation.resume()
            }
        }
    }

    /// Resolves the earliest suspended `setGroupState` call for a group.
    func resolveState(groupID: String, result: Result<Void, any Error>) {
        lock.lock()
        guard var calls = pendingState[groupID], !calls.isEmpty else {
            lock.unlock()
            return
        }
        let call = calls.removeFirst()
        pendingState[groupID] = calls.isEmpty ? nil : calls
        lock.unlock()
        call.continuation.resume(with: result)
    }

    /// Resolves the earliest suspended `setGroupBrightness` call for a group.
    func resolveBrightness(groupID: String, result: Result<Void, any Error>) {
        lock.lock()
        guard var calls = pendingBrightness[groupID], !calls.isEmpty else {
            lock.unlock()
            return
        }
        let call = calls.removeFirst()
        pendingBrightness[groupID] = calls.isEmpty ? nil : calls
        lock.unlock()
        call.continuation.resume(with: result)
    }

    /// Awaits until `count` `setGroupState` calls for the group are pending.
    func waitUntilStatePending(groupID: String, count: Int = 1) async {
        await withCheckedContinuation { outer in
            lock.lock()
            let reached = (pendingState[groupID]?.count ?? 0) >= count
            if reached {
                lock.unlock()
                outer.resume()
            } else {
                stateWaiters[groupID, default: []].append(
                    Waiter(targetCount: count, continuation: outer)
                )
                lock.unlock()
            }
        }
    }

    /// Awaits until `count` `setGroupBrightness` calls for the group are pending.
    func waitUntilBrightnessPending(groupID: String, count: Int = 1) async {
        await withCheckedContinuation { outer in
            lock.lock()
            let reached = (pendingBrightness[groupID]?.count ?? 0) >= count
            if reached {
                lock.unlock()
                outer.resume()
            } else {
                brightnessWaiters[groupID, default: []].append(
                    Waiter(targetCount: count, continuation: outer)
                )
                lock.unlock()
            }
        }
    }

    var pendingStateCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pendingState.values.reduce(0) { $0 + $1.count }
    }

    var pendingBrightnessCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pendingBrightness.values.reduce(0) { $0 + $1.count }
    }

    // MARK: Helpers

    private func takeSatisfiedWaiters(
        for groupID: String,
        pendingCount: Int,
        waiters: inout [String: [Waiter]]
    ) -> [Waiter] {
        guard let group = waiters[groupID], !group.isEmpty else { return [] }
        var satisfied: [Waiter] = []
        var remaining: [Waiter] = []
        for waiter in group {
            if waiter.targetCount <= pendingCount {
                satisfied.append(waiter)
            } else {
                remaining.append(waiter)
            }
        }
        waiters[groupID] = remaining.isEmpty ? nil : remaining
        return satisfied
    }
}

/// A localized error whose debug and localized descriptions differ, so tests
/// can prove the updater preserves the user-facing description.
struct DistinctLocalizedError: LocalizedError, Error {
    let errorDescription: String?

    init(_ description: String) {
        self.errorDescription = description
    }
}

/// In-memory cache that records every write.
final class StubGroupCache: HueGroupCaching, @unchecked Sendable {
    private(set) var savedLists: [[HueGroup]] = []
    var loadedGroups: [HueGroup] = []

    func load() -> [HueGroup] {
        loadedGroups
    }

    func save(_ groups: [HueGroup]) {
        savedLists.append(groups)
    }
}

func makeGroups(_ ids: [String]) -> [HueGroup] {
    ids.map { id in
        HueGroup(id: id, name: "Group \(id)", type: "room", anyOn: false, brightness: nil)
    }
}
