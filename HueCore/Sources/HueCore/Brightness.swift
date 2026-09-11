/// The Hue group brightness clamp.
///
/// The bridge reports brightness on a 1...254 scale and rejects values outside
/// it. This is a pure product rule: any raw slider value is clamped to the
/// accepted range before it is sent or stored.
public enum Brightness {
    public static let minimum = 1
    public static let maximum = 254

    public static func clamp(_ rawValue: Int) -> Int {
        min(max(rawValue, minimum), maximum)
    }
}
