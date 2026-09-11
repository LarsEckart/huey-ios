/// A Hue room or zone as shown by the app.
///
/// This is a plain domain value. It carries the fields the UI renders today
/// (`anyOn`, `brightness`) plus the identity and kind fields every rule needs
/// to filter and order groups.
public struct HueGroup: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let type: String
    public var anyOn: Bool
    public var brightness: Int?

    public init(id: String, name: String, type: String, anyOn: Bool, brightness: Int? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.anyOn = anyOn
        self.brightness = brightness
    }
}
