import Foundation

/// Discovery seam so production and tests can vary without hitting the network
public protocol HueDiscovering: Sendable {
    func discover() async throws -> [HueBridge]
}

/// A URLSession-free discovery client backed by Philips's lookup service.
public struct HueDiscoveryClient: HueDiscovering {
    private let discoveryURL: URL
    private let transport: any HTTPTransport

    public static let philipsLookupURL =
        URL(string: "https://discovery.meethue.com/") ?? URL(fileURLWithPath: "/")

    public init(transport: any HTTPTransport, discoveryURL: URL = Self.philipsLookupURL) {
        self.transport = transport
        self.discoveryURL = discoveryURL
    }

    public func discover() async throws -> [HueBridge] {
        var request = URLRequest(url: discoveryURL)
        request.timeoutInterval = 2

        let (data, response) = try await transport.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
            !(200..<300).contains(httpResponse.statusCode)
        {
            throw HueCoreError.httpStatus(httpResponse.statusCode)
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
