/// Domain-shaped interface for reading and changing Hue group state.
///
/// It is named after the capability it provides, not after URLSession. The
/// production adapter (in the app target) and the test stubs both satisfy this
/// interface; each method accepts domain input and returns domain output, so
/// the rest of the core never sees transport details.
public protocol HueBridgeClient: Sendable {
    func register(deviceType: String) async throws -> String
    func fetchGroups() async throws -> [HueGroup]
    func setGroupState(groupID: String, on: Bool) async throws
    func setGroupBrightness(groupID: String, brightness: Int) async throws
}
