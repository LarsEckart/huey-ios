import Foundation

struct HueBridge: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let internalIPAddress: String

    var displayName: String {
        if id == internalIPAddress {
            return internalIPAddress
        }
        return "\(internalIPAddress) (\(id))"
    }

    enum CodingKeys: String, CodingKey {
        case bridgeID = "id"
        case internalIPAddress = "internalipaddress"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let bridgeID = try container.decodeIfPresent(String.self, forKey: .bridgeID) ?? ""
        let ipAddress = try container.decode(String.self, forKey: .internalIPAddress)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        internalIPAddress = ipAddress
        id = bridgeID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? ipAddress
    }
}

struct HueBridgeDiscoveryClient: Sendable {
    private static let defaultDiscoveryURL = URL(string: "https://discovery.meethue.com/")

    private let discoveryURL: URL
    private let session: URLSession

    init(
        discoveryURL: URL? = Self.defaultDiscoveryURL,
        session: URLSession = .shared
    ) {
        self.discoveryURL = discoveryURL ?? URL(fileURLWithPath: "/")
        self.session = session
    }

    func discover() async throws -> [HueBridge] {
        var request = URLRequest(url: discoveryURL)
        request.timeoutInterval = 2

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
            !(200..<300).contains(httpResponse.statusCode)
        {
            throw HueBridgeDiscoveryError.httpStatus(httpResponse.statusCode)
        }

        let bridges = try JSONDecoder().decode([HueBridge].self, from: data)
        return normalize(bridges)
    }

    private func normalize(_ bridges: [HueBridge]) -> [HueBridge] {
        var uniqueByID: [String: HueBridge] = [:]
        for bridge in bridges where !bridge.internalIPAddress.isEmpty {
            uniqueByID[bridge.id] = bridge
        }

        return uniqueByID.values.sorted { lhs, rhs in
            if lhs.id != rhs.id {
                return lhs.id < rhs.id
            }
            return lhs.internalIPAddress < rhs.internalIPAddress
        }
    }
}

enum HueBridgeDiscoveryError: LocalizedError, Sendable {
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let statusCode):
            "Discovery service returned HTTP \(statusCode)."
        }
    }
}

extension String {
    fileprivate var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
