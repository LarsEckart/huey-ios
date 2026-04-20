import Foundation

struct HueGroup: Identifiable, Equatable {
    let id: String
    let name: String
    let type: String
    var anyOn: Bool
}

enum HueBridgeClientError: LocalizedError {
    case invalidBridgeIP
    case malformedResponse(String)
    case bridgeError(String)

    var errorDescription: String? {
        switch self {
        case .invalidBridgeIP:
            "Bridge IP is invalid."
        case let .malformedResponse(message):
            "Unexpected bridge response: \(message)"
        case let .bridgeError(message):
            message
        }
    }
}

final class HueBridgeClient {
    private let bridgeIP: String
    private let username: String
    private let session: URLSession

    init(bridgeIP: String, username: String, session: URLSession = .shared) {
        self.bridgeIP = bridgeIP
        self.username = username
        self.session = session
    }

    func register(deviceType: String) async throws -> String {
        var request = try makeRequest(url: bridgeAPIURL, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["devicetype": deviceType])

        let (data, _) = try await session.data(for: request)
        let results = try JSONDecoder().decode([RegisterResult].self, from: data)

        guard let first = results.first else {
            throw HueBridgeClientError.malformedResponse("empty register result")
        }

        if let error = first.error {
            throw HueBridgeClientError.bridgeError(error.description)
        }

        guard let username = first.success?.username, !username.isEmpty else {
            throw HueBridgeClientError.malformedResponse("missing username in register result")
        }

        return username
    }

    func fetchGroups() async throws -> [HueGroup] {
        let request = try makeRequest(url: authedAPIURL.appendingPathComponent("groups"), method: "GET")
        let (data, _) = try await session.data(for: request)

        try checkBridgeError(in: data)

        let groupsByID = try JSONDecoder().decode([String: GroupResponse].self, from: data)
        let groups = groupsByID.map { id, response in
            HueGroup(id: id, name: response.name, type: response.type, anyOn: response.state.anyOn)
        }

        return groups.sorted { lhs, rhs in
            let leftKey = Self.sortKey(forHueID: lhs.id)
            let rightKey = Self.sortKey(forHueID: rhs.id)
            if leftKey != rightKey {
                return leftKey < rightKey
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func setGroupState(groupID: String, on: Bool) async throws {
        var request = try makeRequest(
            url: authedAPIURL.appendingPathComponent("groups").appendingPathComponent(groupID).appendingPathComponent("action"),
            method: "PUT"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["on": on])

        let (data, _) = try await session.data(for: request)
        try checkBridgeError(in: data)
    }

    private var bridgeAPIURL: URL {
        get throws {
            guard let url = URL(string: "http://\(bridgeIP)/api") else {
                throw HueBridgeClientError.invalidBridgeIP
            }
            return url
        }
    }

    private var authedAPIURL: URL {
        get throws {
            guard let url = URL(string: "http://\(bridgeIP)/api/\(username)") else {
                throw HueBridgeClientError.invalidBridgeIP
            }
            return url
        }
    }

    private func makeRequest(url: URL, method: String) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 2
        return request
    }

    private func checkBridgeError(in data: Data) throws {
        guard
            let results = try? JSONDecoder().decode([BridgeResult].self, from: data),
            let first = results.first,
            let error = first.error
        else {
            return
        }

        throw HueBridgeClientError.bridgeError(error.description)
    }

    private static func sortKey(forHueID id: String) -> (Int, Int, String) {
        if let numericID = Int(id) {
            return (0, numericID, "")
        }
        return (1, 0, id)
    }
}

private struct GroupResponse: Decodable {
    let name: String
    let type: String
    let state: GroupStateResponse
}

private struct GroupStateResponse: Decodable {
    let anyOn: Bool

    enum CodingKeys: String, CodingKey {
        case anyOn = "any_on"
    }
}

private struct RegisterResult: Decodable {
    let error: BridgeErrorResponse?
    let success: RegisterSuccessResponse?
}

private struct RegisterSuccessResponse: Decodable {
    let username: String
}

private struct BridgeResult: Decodable {
    let error: BridgeErrorResponse?
}

private struct BridgeErrorResponse: Decodable {
    let description: String
}
