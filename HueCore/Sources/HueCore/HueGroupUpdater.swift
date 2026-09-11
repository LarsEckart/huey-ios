import Foundation

/// The outcome of refreshing the group list.
public enum GroupRefreshOutcome: Equatable, Sendable {
    case succeeded  // fetched and merged into current state
    case failed(HueCoreError)  // no list change applied
}

/// The outcome of one optimistic group change.
public enum GroupUpdateOutcome: Equatable, Sendable {
    case notFound  // group not in the current list
    case applied  // succeeded; the value is committed
    case superseded  // a newer change owns this group; untouched
    case failed(HueCoreError)  // rolled back (unless superseded); surfaced
}

/// The headless workflow that owns the current group list and the product
/// rules the view model previously held: room/zone selection and ordering,
/// brightness clamping, optimistic change, and rollback.
///
/// It owns `current` and refines it per group; each in-flight change carries a
/// revision, so a completion only rolls back or caches its own group and only
/// if nothing newer replaced it. Changes publish optimistically (via an
/// `AsyncStream`) before the network suspends, so the UI shows intent
/// immediately and can restore an edited slider on rollback. The lock is only
/// touched from synchronous helpers so `NSLock` stays out of async contexts.
public final class HueGroupUpdater: @unchecked Sendable {
    private let client: any HueBridgeClient
    private let cache: any HueGroupCaching
    private let lock = NSLock()

    private var current: [HueGroup]
    private var generation: UInt = 0
    private var groupRevision: [String: UInt] = [:]
    private var pending: [String: PendingOp] = [:]

    private struct PendingOp {
        let token: UUID
        let appliedRevision: UInt
        let prior: HueGroup
    }

    private let stream: AsyncStream<[HueGroup]>
    private let continuation: AsyncStream<[HueGroup]>.Continuation

    public init(
        client: any HueBridgeClient,
        cache: any HueGroupCaching,
        initialGroups: [HueGroup]
    ) {
        self.client = client
        self.cache = cache
        let pair = AsyncStream.makeStream(of: [HueGroup].self)
        self.stream = pair.stream
        self.continuation = pair.continuation
        self.current = initialGroups
        for group in initialGroups {
            groupRevision[group.id] = generation
        }
    }

    public func currentGroups() -> [HueGroup] {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func snapshotUpdates() -> AsyncStream<[HueGroup]> {
        stream
    }

    public func refresh() async -> GroupRefreshOutcome {
        do {
            let visible = GroupSelection.visible(in: try await client.fetchGroups())
            mergeRefresh(visible)
            return .succeeded
        } catch {
            return .failed(HueCoreError.normalizing(error))
        }
    }

    public func setOn(groupID: String, on: Bool) async -> GroupUpdateOutcome {
        await change(groupID: groupID) {
            HueGroup(
                id: $0.id, name: $0.name, type: $0.type, anyOn: on,
                brightness: $0.brightness)
        } network: {
            try await client.setGroupState(groupID: groupID, on: on)
        }
    }

    public func setBrightness(groupID: String, to raw: Int) async -> GroupUpdateOutcome {
        let clamped = Brightness.clamp(raw)
        return await change(groupID: groupID) {
            HueGroup(
                id: $0.id, name: $0.name, type: $0.type, anyOn: $0.anyOn,
                brightness: clamped)
        } network: {
            try await client.setGroupBrightness(groupID: groupID, brightness: clamped)
        }
    }

    private func change(
        groupID: String,
        transform: (HueGroup) -> HueGroup,
        network: () async throws -> Void
    ) async -> GroupUpdateOutcome {
        guard let op = applyOptimistic(groupID: groupID, transform: transform) else {
            return .notFound
        }
        do {
            try await network()
            return resolveSuccess(groupID: groupID, token: op.token)
        } catch {
            return resolveFailure(
                groupID: groupID, token: op.token,
                error: HueCoreError.normalizing(error))
        }
    }

    // MARK: Synchronous, lock-holding helpers (never await)

    private func applyOptimistic(groupID: String, transform: (HueGroup) -> HueGroup) -> AppliedOp? {
        lock.lock()
        defer { lock.unlock() }
        guard let index = current.firstIndex(where: { $0.id == groupID }) else {
            return nil
        }
        let group = current[index]
        current[index] = transform(group)
        let revision = nextGenerationLocked()
        groupRevision[groupID] = revision
        let token = UUID()
        pending[groupID] = PendingOp(token: token, appliedRevision: revision, prior: group)
        continuation.yield(current)
        return AppliedOp(token: token)
    }

    private func resolveSuccess(groupID: String, token: UUID) -> GroupUpdateOutcome {
        lock.lock()
        defer { lock.unlock() }
        guard pending[groupID]?.token == token else {
            return .superseded
        }
        pending.removeValue(forKey: groupID)
        cache.save(current)
        return .applied
    }

    private func resolveFailure(groupID: String, token: UUID, error: HueCoreError) -> GroupUpdateOutcome {
        lock.lock()
        defer { lock.unlock() }
        guard let op = pending[groupID], op.token == token else {
            return .superseded
        }
        pending.removeValue(forKey: groupID)
        guard let index = current.firstIndex(where: { $0.id == groupID }),
            groupRevision[groupID] == op.appliedRevision
        else {
            // A newer success or refresh owns the group; don't undo it.
            cache.save(current)
            return .failed(error)
        }
        current[index] = op.prior
        groupRevision[groupID] = nextGenerationLocked()
        continuation.yield(current)
        cache.save(current)
        return .failed(error)
    }

    /// Merges a fresh fetch into current state, preserving in-flight optimistic
    /// changes so a concurrent refresh cannot clobber a pending intent.
    private func mergeRefresh(_ visible: [HueGroup]) {
        lock.lock()
        defer { lock.unlock() }
        var merged = visible
        for groupID in pending.keys {
            if let currentIndex = current.firstIndex(where: { $0.id == groupID }),
                let mergedIndex = merged.firstIndex(where: { $0.id == groupID })
            {
                merged[mergedIndex] = current[currentIndex]
            }
        }
        current = GroupSelection.visible(in: merged)
        for group in current {
            groupRevision[group.id] = nextGenerationLocked()
        }
        continuation.yield(current)
        cache.save(current)
    }

    private func nextGenerationLocked() -> UInt {
        generation += 1
        return generation
    }

    private struct AppliedOp {
        let token: UUID
    }
}
