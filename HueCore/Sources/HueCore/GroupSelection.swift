/// The rule that decides which groups are shown and in what order.
///
/// Only Hue rooms and zones are togglable. They are sorted by name, case
/// insensitively, with the bridge's numeric id as a stable tie-breaker so the
/// listing does not reorder nondeterministically.
public enum GroupSelection {
    public static func visible(in groups: [HueGroup]) -> [HueGroup] {
        groups
            .filter { group in
                let normalizedType = group.type.lowercased()
                return normalizedType == "room" || normalizedType == "zone"
            }
            .sorted { lhs, rhs in
                let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                return lhs.id < rhs.id
            }
    }
}
