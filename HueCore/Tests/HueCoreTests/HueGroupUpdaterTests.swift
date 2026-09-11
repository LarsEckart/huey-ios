import XCTest

@testable import HueCore

final class HueGroupUpdaterTests: XCTestCase {
    // MARK: State ownership

    func testUpdaterExposesInitialGroups() {
        let updater = makeUpdater(
            client: StubHueBridgeClient(),
            cache: StubGroupCache(),
            groups: makeGroups(["1", "2"])
        )

        XCTAssertEqual(updater.currentGroups().map(\.id), ["1", "2"])
    }

    // MARK: Refresh

    func testRefreshMergesVisibleOrderedListAndPersistsIt() async throws {
        let client = StubHueBridgeClient()
        client.fetchResult = .success([
            makeGroup(id: "2", name: "Office"),
            makeGroup(id: "1", name: "Lamp", type: "Entertainment"),
            makeGroup(id: "3", name: "bedroom", type: "Room"),
        ])
        let cache = StubGroupCache()
        let updater = makeUpdater(client: client, cache: cache)

        let outcome = await updater.refresh()

        XCTAssertEqual(outcome, .succeeded)
        XCTAssertEqual(updater.currentGroups().map(\.id), ["3", "2"])
        XCTAssertEqual(cache.savedLists.last?.map(\.id), ["3", "2"])
    }

    func testRefreshFailureDoesNotTouchCacheOrState() async throws {
        let client = StubHueBridgeClient()
        client.fetchResult = .failure(URLError(.notConnectedToInternet))
        let cache = StubGroupCache()
        let groups = makeGroups(["1"])
        let updater = makeUpdater(client: client, cache: cache, groups: groups)

        let outcome = await updater.refresh()

        guard case .failed(let error) = outcome else {
            return XCTFail("expected failed, got \(outcome)")
        }
        XCTAssertEqual(error, .transport(error.localizedDescription))
        XCTAssertEqual(updater.currentGroups(), groups)
        XCTAssertTrue(cache.savedLists.isEmpty)
    }

    // MARK: Toggle

    func testToggleSuccessAppliesOptimisticStateAndPersists() async throws {
        let client = StubHueBridgeClient()
        let cache = StubGroupCache()
        let groups = [
            makeGroup(id: "1", name: "Bedroom", anyOn: false),
            makeGroup(id: "2", name: "Office", anyOn: false),
        ]
        let updater = makeUpdater(client: client, cache: cache, groups: groups)

        let outcome = await updater.setOn(groupID: "2", on: true)

        XCTAssertEqual(outcome, .applied)
        let updated = updater.currentGroups()
        XCTAssertEqual(updated[1].anyOn, true)
        XCTAssertEqual(updated[0].anyOn, false)
        XCTAssertEqual(client.setStateCalls.map(\.on), [true])
        XCTAssertEqual(client.setStateCalls.map(\.groupID), ["2"])
        XCTAssertEqual(cache.savedLists.last?.map(\.anyOn), [false, true])
    }

    func testToggleFailureRollsBackAndReportsError() async throws {
        let client = StubHueBridgeClient()
        client.setStateFailure = HueCoreError.bridgeError("link button not pressed")
        let cache = StubGroupCache()
        let groups = [
            makeGroup(id: "1", name: "Bedroom", anyOn: false),
            makeGroup(id: "2", name: "Office", anyOn: true),
        ]
        let updater = makeUpdater(client: client, cache: cache, groups: groups)

        let outcome = await updater.setOn(groupID: "2", on: false)

        guard case .failed(let error) = outcome else {
            return XCTFail("expected failed, got \(outcome)")
        }
        XCTAssertEqual(error, .bridgeError("link button not pressed"))
        XCTAssertEqual(updater.currentGroups()[1].anyOn, true, "must keep the prior value")
        XCTAssertEqual(cache.savedLists.last, groups)
    }

    func testToggleUnknownGroupIsNoOp() async throws {
        let client = StubHueBridgeClient()
        let cache = StubGroupCache()
        let updater = makeUpdater(
            client: client, cache: cache, groups: [makeGroup(id: "1", name: "Bedroom")]
        )

        let outcome = await updater.setOn(groupID: "999", on: true)

        XCTAssertEqual(outcome, .notFound)
        XCTAssertTrue(client.setStateCalls.isEmpty)
        XCTAssertTrue(cache.savedLists.isEmpty)
    }

    // MARK: Brightness

    func testSetBrightnessClampsToAcceptedRangeBeforeSending() async throws {
        let client = StubHueBridgeClient()
        let cache = StubGroupCache()
        let updater = makeUpdater(
            client: client,
            cache: cache,
            groups: [makeGroup(id: "1", name: "Bedroom", brightness: 100)]
        )

        let outcome = await updater.setBrightness(groupID: "1", to: 1000)

        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(client.setBrightnessCalls.map(\.brightness), [254])
        XCTAssertEqual(updater.currentGroups()[0].brightness, 254)
    }

    func testSetBrightnessFailureRestoresPriorBrightness() async throws {
        let client = StubHueBridgeClient()
        client.setBrightnessFailure = URLError(.timedOut)
        let cache = StubGroupCache()
        let groups = [makeGroup(id: "1", name: "Bedroom", brightness: 40)]
        let updater = makeUpdater(client: client, cache: cache, groups: groups)

        let outcome = await updater.setBrightness(groupID: "1", to: 999)

        guard case .failed(let error) = outcome else {
            return XCTFail("expected failed, got \(outcome)")
        }
        XCTAssertEqual(updater.currentGroups()[0].brightness, 40, "must restore the prior brightness")
        XCTAssertEqual(client.setBrightnessCalls.map(\.brightness), [254])
        guard case .transport = error else {
            return XCTFail("expected a transport error, got \(error)")
        }
    }

    // MARK: Optimistic state visible while a request is pending

    func testOptimisticToggleStateVisibleWhileRequestPending() async throws {
        let client = SuspendingBridgeClient()
        let cache = StubGroupCache()
        let groups = [makeGroup(id: "1", name: "Bedroom", anyOn: false)]
        let updater = makeUpdater(client: client, cache: cache, groups: groups)

        let task = Task { await updater.setOn(groupID: "1", on: true) }
        await client.waitUntilStatePending(groupID: "1")

        // While the request waits, the intended value is already visible.
        XCTAssertEqual(updater.currentGroups()[0].anyOn, true)

        client.resolveState(groupID: "1", result: .success(()))
        let outcome = await task.value
        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(updater.currentGroups()[0].anyOn, true)
    }

    func testOptimisticBrightnessStateVisibleWhileRequestPending() async throws {
        let client = SuspendingBridgeClient()
        let cache = StubGroupCache()
        let groups = [makeGroup(id: "1", name: "Bedroom", brightness: 40)]
        let updater = makeUpdater(client: client, cache: cache, groups: groups)

        let task = Task { await updater.setBrightness(groupID: "1", to: 200) }
        await client.waitUntilBrightnessPending(groupID: "1")

        XCTAssertEqual(updater.currentGroups()[0].brightness, 200)

        client.resolveBrightness(groupID: "1", result: .success(()))
        let outcome = await task.value
        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(updater.currentGroups()[0].brightness, 200)
    }

    func testRollbackPublishesRestorationSnapshot() async throws {
        let client = SuspendingBridgeClient()
        let cache = StubGroupCache()
        let groups = [makeGroup(id: "1", name: "Bedroom", brightness: 40)]
        let updater = makeUpdater(client: client, cache: cache, groups: groups)

        let task = Task {
            await updater.setBrightness(groupID: "1", to: 200)
        }
        await client.waitUntilBrightnessPending(groupID: "1")
        XCTAssertEqual(updater.currentGroups()[0].brightness, 200)

        // A single iterator observes the stream in order: the optimistic
        // snapshot first, then the rollback that restores the prior value.
        var iterator = updater.snapshotUpdates().makeAsyncIterator()
        let optimistic = await nextSnapshot(from: &iterator)
        XCTAssertEqual(optimistic[0].brightness, 200)

        client.resolveBrightness(groupID: "1", result: .failure(URLError(.timedOut)))
        let outcome = await task.value
        guard case .failed = outcome else {
            return XCTFail("expected a failed outcome, got \(outcome)")
        }

        let rolledBack = await nextSnapshot(from: &iterator)
        XCTAssertEqual(rolledBack[0].brightness, 40, "rollback must re-publish the prior value")
    }

    func testSnapshotsPublishOptimisticValueOnSuccess() async throws {
        let client = SuspendingBridgeClient()
        let cache = StubGroupCache()
        let groups = [makeGroup(id: "1", name: "Bedroom", anyOn: false)]
        let updater = makeUpdater(client: client, cache: cache, groups: groups)

        let task = Task { await updater.setOn(groupID: "1", on: true) }
        await client.waitUntilStatePending(groupID: "1")
        client.resolveState(groupID: "1", result: .success(()))
        let outcome = await task.value
        XCTAssertEqual(outcome, .applied)

        var iterator = updater.snapshotUpdates().makeAsyncIterator()
        let first = await nextSnapshot(from: &iterator)
        XCTAssertEqual(first[0].anyOn, true)
    }

    // MARK: Overlapping concurrent updates (both completion orders)

    func testConcurrentTogglesDifferentGroupsBothSucceed() async throws {
        let client = SuspendingBridgeClient()
        let cache = StubGroupCache()
        let groups = makeGroups(["1", "2"])
        let updater = makeUpdater(client: client, cache: cache, groups: groups)

        let taskA = Task { await updater.setOn(groupID: "1", on: true) }
        let taskB = Task { await updater.setOn(groupID: "2", on: true) }
        await client.waitUntilStatePending(groupID: "1")
        await client.waitUntilStatePending(groupID: "2")

        // A then B succeed; neither overwrites the other's change.
        client.resolveState(groupID: "1", result: .success(()))
        client.resolveState(groupID: "2", result: .success(()))
        let outcomeA = await taskA.value
        let outcomeB = await taskB.value
        XCTAssertEqual(outcomeA, .applied)
        XCTAssertEqual(outcomeB, .applied)

        XCTAssertEqual(updater.currentGroups().map(\.anyOn), [true, true])
        XCTAssertEqual(cache.savedLists.last?.map(\.anyOn), [true, true])
    }

    func testSecondFailureRollsBackOnlyItsOwnGroupAndKeepsSuccess() async throws {
        let client = SuspendingBridgeClient()
        let cache = StubGroupCache()
        let groups = makeGroups(["1", "2"])
        let updater = makeUpdater(client: client, cache: cache, groups: groups)

        let taskA = Task { await updater.setOn(groupID: "1", on: true) }
        let taskB = Task { await updater.setOn(groupID: "2", on: true) }
        await client.waitUntilStatePending(groupID: "1")
        await client.waitUntilStatePending(groupID: "2")

        // A succeeds first, then B fails: B rolls back only itself.
        client.resolveState(groupID: "1", result: .success(()))
        client.resolveState(groupID: "2", result: .failure(URLError(.timedOut)))
        let outcomeA = await taskA.value
        XCTAssertEqual(outcomeA, .applied)
        guard case .failed = await taskB.value else {
            return XCTFail("expected B to fail")
        }

        XCTAssertEqual(updater.currentGroups()[0].anyOn, true, "A's success must survive B's failure")
        XCTAssertEqual(updater.currentGroups()[1].anyOn, false, "B must roll back to its prior value")
        XCTAssertEqual(cache.savedLists.last?.map(\.anyOn), [true, false])
    }

    func testFirstFailureRollsBackOnlyItsOwnGroupPreservesLaterSuccess() async throws {
        let client = SuspendingBridgeClient()
        let cache = StubGroupCache()
        let groups = makeGroups(["1", "2"])
        let updater = makeUpdater(client: client, cache: cache, groups: groups)

        let taskA = Task { await updater.setOn(groupID: "1", on: true) }
        let taskB = Task { await updater.setOn(groupID: "2", on: true) }
        await client.waitUntilStatePending(groupID: "1")
        await client.waitUntilStatePending(groupID: "2")

        // A fails first, then B succeeds: A's rollback does not erase B.
        client.resolveState(groupID: "1", result: .failure(URLError(.timedOut)))
        client.resolveState(groupID: "2", result: .success(()))
        guard case .failed = await taskA.value else {
            return XCTFail("expected A to fail")
        }
        let outcomeB = await taskB.value
        XCTAssertEqual(outcomeB, .applied)

        XCTAssertEqual(updater.currentGroups()[0].anyOn, false, "A must roll back to its prior value")
        XCTAssertEqual(updater.currentGroups()[1].anyOn, true, "B's success must survive A's rollback")
        XCTAssertEqual(cache.savedLists.last?.map(\.anyOn), [false, true])
    }

    // MARK: Refresh overlap

    func testRefreshPreservesPendingOptimisticChange() async throws {
        let client = SuspendingBridgeClient()
        client.fetchResult = .success([
            makeGroup(id: "1", name: "Bedroom", anyOn: false),
        ])
        let cache = StubGroupCache()
        let groups = [makeGroup(id: "1", name: "Bedroom", anyOn: false)]
        let updater = makeUpdater(client: client, cache: cache, groups: groups)

        let task = Task { await updater.setOn(groupID: "1", on: true) }
        await client.waitUntilStatePending(groupID: "1")

        // A refresh lands while the toggle is still in flight; the server still
        // says off, but the pending optimistic intent must be preserved.
        _ = await updater.refresh()
        XCTAssertEqual(updater.currentGroups()[0].anyOn, true, "refresh must not clobber a pending change")

        client.resolveState(groupID: "1", result: .success(()))
        let outcome = await task.value
        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(updater.currentGroups()[0].anyOn, true)
        XCTAssertEqual(cache.savedLists.last?.map(\.anyOn), [true])
    }

    func testFailedUpdateDoesNotEraseNewerRefresh() async throws {
        let client = SuspendingBridgeClient()
        client.fetchResult = .success([makeGroup(id: "1", name: "Bedroom", anyOn: true)])
        let cache = StubGroupCache()
        let groups = [makeGroup(id: "1", name: "Bedroom", anyOn: false)]
        let updater = makeUpdater(client: client, cache: cache, groups: groups)

        let task = Task { await updater.setOn(groupID: "1", on: true) }
        await client.waitUntilStatePending(groupID: "1")

        client.resolveState(groupID: "1", result: .failure(URLError(.timedOut)))
        guard case .failed = await task.value else {
            return XCTFail("expected the update to fail")
        }
        // This refresh happened after the failed update resolved; it carries the
        // newer server truth (on) and must not be rolled back to the stale off.
        _ = await updater.refresh()
        XCTAssertEqual(updater.currentGroups()[0].anyOn, true)
    }

    // MARK: Same-group handling

    func testSameGroupRapidTogglesMakeOlderOperationSuperseded() async throws {
        let client = SuspendingBridgeClient()
        let cache = StubGroupCache()
        let groups = [makeGroup(id: "1", name: "Bedroom", anyOn: false)]
        let updater = makeUpdater(client: client, cache: cache, groups: groups)

        // Toggle on, then toggle off again before the first request resolves.
        let taskOn = Task { await updater.setOn(groupID: "1", on: true) }
        await client.waitUntilStatePending(groupID: "1", count: 1)
        let taskOff = Task { await updater.setOn(groupID: "1", on: false) }
        await client.waitUntilStatePending(groupID: "1", count: 2)

        // The first (on) request resolves success, but a newer (off) change owns
        // the group now, so it must not clobber state.
        client.resolveState(groupID: "1", result: .success(()))
        client.resolveState(groupID: "1", result: .success(()))
        let outcomeOn = await taskOn.value
        let outcomeOff = await taskOff.value
        XCTAssertEqual(outcomeOn, .superseded)
        XCTAssertEqual(outcomeOff, .applied)

        XCTAssertEqual(updater.currentGroups()[0].anyOn, false, "final state follows the last intent")
    }

    // MARK: Cache consistency

    func testCacheMatchesFinalCommittedStateAfterOverlap() async throws {
        let client = SuspendingBridgeClient()
        let cache = StubGroupCache()
        let groups = makeGroups(["1", "2"])
        let updater = makeUpdater(client: client, cache: cache, groups: groups)

        let taskA = Task { await updater.setOn(groupID: "1", on: true) }
        let taskB = Task { await updater.setOn(groupID: "2", on: true) }
        await client.waitUntilStatePending(groupID: "1")
        await client.waitUntilStatePending(groupID: "2")
        client.resolveState(groupID: "1", result: .failure(URLError(.timedOut)))
        client.resolveState(groupID: "2", result: .success(()))
        _ = await taskA.value
        _ = await taskB.value

        XCTAssertEqual(cache.savedLists.last, updater.currentGroups())
    }

    // MARK: Error normalization

    func testUpdateFailurePreservesLocalizedErrorDescription() async throws {
        let client = StubHueBridgeClient()
        client.setStateFailure = DistinctLocalizedError("Link button not pressed")
        let cache = StubGroupCache()
        let updater = makeUpdater(
            client: client, cache: cache, groups: [makeGroup(id: "1", name: "Bedroom")]
        )

        let outcome = await updater.setOn(groupID: "1", on: true)

        guard case .failed(let error) = outcome else {
            return XCTFail("expected failed, got \(outcome)")
        }
        XCTAssertEqual(error, .transport("Link button not pressed"))
        XCTAssertEqual(error.localizedDescription, "Link button not pressed")
        let debug = String(describing: DistinctLocalizedError("Link button not pressed"))
        XCTAssertNotEqual(error.localizedDescription, debug, "must not degrade into the debug form")
    }

    func testRefreshFailurePreservesLocalizedErrorDescription() async throws {
        let client = StubHueBridgeClient()
        client.fetchResult = .failure(DistinctLocalizedError("Bridge unreachable"))
        let cache = StubGroupCache()
        let updater = makeUpdater(client: client, cache: cache)

        let outcome = await updater.refresh()

        guard case .failed(let error) = outcome else {
            return XCTFail("expected failed, got \(outcome)")
        }
        XCTAssertEqual(error.localizedDescription, "Bridge unreachable")
    }

    // MARK: Helpers

    private func makeUpdater(
        client: any HueBridgeClient,
        cache: StubGroupCache,
        groups: [HueGroup] = []
    ) -> HueGroupUpdater {
        HueGroupUpdater(client: client, cache: cache, initialGroups: groups)
    }

    private func nextSnapshot(
        from iterator: inout AsyncStream<[HueGroup]>.Iterator
    ) async -> [HueGroup] {
        guard let snapshot = await iterator.next() else {
            XCTFail("expected a snapshot from the updater stream")
            return []
        }
        return snapshot
    }

    private func makeGroup(
        id: String,
        name: String,
        type: String = "room",
        anyOn: Bool = false,
        brightness: Int? = nil
    ) -> HueGroup {
        HueGroup(id: id, name: name, type: type, anyOn: anyOn, brightness: brightness)
    }
}
