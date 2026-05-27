import Foundation

@MainActor
final class LampsViewModel: ObservableObject {
    @Published private(set) var groups: [HueGroup] = []
    @Published private(set) var busyGroupIDs: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?

    private let client: HueBridgeClient
    private let cache: HueGroupCache?

    init(client: HueBridgeClient, cache: HueGroupCache? = nil) {
        self.client = client
        self.cache = cache
        self.groups = cache?.load() ?? []
    }

    func isBusy(groupID: String) -> Bool {
        busyGroupIDs.contains(groupID)
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let allGroups = try await client.fetchGroups()
            let visibleGroups =
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
            groups = visibleGroups
            cache?.save(visibleGroups)
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
            cache?.save(groups)
        } catch {
            if let currentIndex = groups.firstIndex(where: { $0.id == groupID }) {
                groups[currentIndex].anyOn = previousState
            }
            cache?.save(groups)
            errorMessage = error.localizedDescription
        }
    }

    func setBrightness(groupID: String, brightness: Int) async {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else {
            return
        }

        let clampedBrightness = min(max(brightness, 1), 254)
        busyGroupIDs.insert(groupID)
        defer { busyGroupIDs.remove(groupID) }

        let previousBrightness = groups[index].brightness
        groups[index].brightness = clampedBrightness

        do {
            try await client.setGroupBrightness(groupID: groupID, brightness: clampedBrightness)
            cache?.save(groups)
        } catch {
            if let currentIndex = groups.firstIndex(where: { $0.id == groupID }) {
                groups[currentIndex].brightness = previousBrightness
            }
            cache?.save(groups)
            errorMessage = error.localizedDescription
        }
    }
}
