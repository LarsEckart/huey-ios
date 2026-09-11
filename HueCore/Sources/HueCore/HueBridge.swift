/// A discovered Hue bridge, as returned by the bridge discovery service.
public struct HueBridge: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let internalIPAddress: String

    public var displayName: String {
        if id == internalIPAddress {
            return internalIPAddress
        }
        return "\(internalIPAddress) (\(id))"
    }

    enum CodingKeys: String, CodingKey {
        case bridgeID = "id"
        case internalIPAddress = "internalipaddress"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let bridgeID = try container.decodeIfPresent(String.self, forKey: .bridgeID) ?? ""
        let ipAddress =
            try container.decode(String.self, forKey: .internalIPAddress)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        internalIPAddress = ipAddress
        id = bridgeID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? ipAddress
    }

    public init(id: String, internalIPAddress: String) {
        self.id = id
        self.internalIPAddress = internalIPAddress
    }
}

extension String {
    fileprivate var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
