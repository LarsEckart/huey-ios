import Foundation
import HueCore

/// UserDefaults-backed adapter for the core's group persistence seam.
///
/// ``UserDefaults`` is thread-safe for the single-key access we perform but is
/// not marked ``Sendable`` in the SDK, so we opt out explicitly for this outer
/// adapter.
struct HueGroupCache: HueGroupCaching, @unchecked Sendable {
    private let key: String
    private let storage: UserDefaults

    init(bridgeIP: String, username: String, storage: UserDefaults = .standard) {
        self.key = "hue.groups.\(bridgeIP).\(username)"
        self.storage = storage
    }

    func load() -> [HueGroup] {
        guard let data = storage.data(forKey: key) else {
            return []
        }

        do {
            return try JSONDecoder().decode([HueGroup].self, from: data)
        } catch {
            storage.removeObject(forKey: key)
            return []
        }
    }

    func save(_ groups: [HueGroup]) {
        do {
            let data = try JSONEncoder().encode(groups)
            storage.set(data, forKey: key)
        } catch {
            storage.removeObject(forKey: key)
        }
    }
}
