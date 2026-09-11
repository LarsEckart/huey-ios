import Foundation
import HueCore

/// Presentation state for the lamps list.
///
/// This is a UI adapter. Product rules (room/zone selection, ordering,
/// brightness clamping, and the optimistic update/rollback decision) live in
/// `HueGroupUpdater`, which also owns the current group list. The updater
/// publishes every optimistic/resolved/refresh snapshot through an
/// `AsyncStream`; this type reflects those snapshots into observable state and
/// keeps busy/refreshing/error flags that are presentation concerns only.
@MainActor
final class LampsViewModel: ObservableObject {
    @Published private(set) var groups: [HueGroup] = []
    @Published private(set) var busyGroupIDs: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?

    private let updater: HueGroupUpdater

    init(updater: HueGroupUpdater) {
        self.updater = updater
        self.groups = updater.currentGroups()
        observeSnapshots()
    }

    func isBusy(groupID: String) -> Bool {
        busyGroupIDs.contains(groupID)
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        switch await updater.refresh() {
        case .succeeded:
            errorMessage = nil
        case .failed(let error):
            errorMessage = error.localizedDescription
        }
    }

    func set(groupID: String, on: Bool) async {
        await setBusy(groupID: groupID) {
            switch await self.updater.setOn(groupID: groupID, on: on) {
            case .notFound, .applied, .superseded:
                break
            case .failed(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func setBrightness(groupID: String, brightness: Int) async {
        await setBusy(groupID: groupID) {
            switch await self.updater.setBrightness(groupID: groupID, to: brightness) {
            case .notFound, .applied, .superseded:
                break
            case .failed(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func observeSnapshots() {
        let updates = updater.snapshotUpdates()
        Task { @MainActor in
            for await snapshot in updates {
                self.groups = snapshot
            }
        }
    }

    private func setBusy(groupID: String, operation: () async -> Void) async {
        busyGroupIDs.insert(groupID)
        defer { busyGroupIDs.remove(groupID) }
        await operation()
    }
}
