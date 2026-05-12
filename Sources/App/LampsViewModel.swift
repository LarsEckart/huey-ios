import Foundation

@MainActor
final class LampsViewModel: ObservableObject {
    @Published private(set) var groups: [HueGroup] = []
    @Published private(set) var busyGroupIDs: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?

    private let client: HueBridgeClient

    init(client: HueBridgeClient) {
        self.client = client
    }

    func isBusy(groupID: String) -> Bool {
        busyGroupIDs.contains(groupID)
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let allGroups = try await client.fetchGroups()
            groups =
                allGroups
                .filter { group in
                    let normalizedType = group.type.lowercased()
                    return normalizedType == "room" || normalizedType == "zone"
                }
                .sorted {
                    if $0.name.localizedCaseInsensitiveCompare($1.name) != .orderedSame {
                        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    return $0.id < $1.id
                }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func set(groupID: String, on: Bool) async {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else {
            return
        }

        busyGroupIDs.insert(groupID)
        defer { busyGroupIDs.remove(groupID) }

        let previousState = groups[index].anyOn
        groups[index].anyOn = on

        do {
            try await client.setGroupState(groupID: groupID, on: on)
        } catch {
            groups[index].anyOn = previousState
            errorMessage = error.localizedDescription
        }
    }
}
