/// Persistence seam for the group listing.
///
/// The workflow persists the authoritative group list through this interface so
/// a test can substitute an in-memory store and never touch `UserDefaults`.
public protocol HueGroupCaching: Sendable {
    func load() -> [HueGroup]
    func save(_ groups: [HueGroup])
}
