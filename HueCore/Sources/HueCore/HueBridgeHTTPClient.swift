import Foundation

/// A URLSession-free Hue bridge client.
///
/// This is the deep implementation behind `HueBridgeClient`: it builds
/// requests, decodes the bridge's JSON, checks for bridge errors, and maps the
/// response into `HueGroup` values. The only effect it performs is through the
/// injected `HTTPTransport`, so request/response mapping is fully testable with
/// a stub and fixture data.
public struct HueBridgeHTTPClient: HueBridgeClient {
    private let bridgeIP: String
    private let username: String
    private let transport: any HTTPTransport

    public init(bridgeIP: String, username: String, transport: any HTTPTransport) {
        self.bridgeIP = bridgeIP
        self.username = username
        self.transport = transport
    }

    public func register(deviceType: String) async throws -> String {
        // Registration is username-independent: it posts to the root `/api`
        // endpoint, which creates a new username. It must not use
        // `/api/<username>` (that is only valid once a user exists).
        var request = try makeRequest(to: registerURL(), method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["devicetype": deviceType])

        let (data, _) = try await transport.data(for: request)
        let results = try JSONDecoder().decode([RegisterResult].self, from: data)

        guard let first = results.first else {
            throw HueCoreError.malformedResponse("empty register result")
        }
        if let bridgeError = first.error {
            throw HueCoreError.bridgeError(bridgeError.description)
        }
        guard let username = first.success?.username, !username.isEmpty else {
            throw HueCoreError.malformedResponse("missing username in register result")
        }
        return username
    }

    public func fetchGroups() async throws -> [HueGroup] {
        let request = try makeRequest(to: authedAPIURL(path: "groups"), method: "GET")
        let (data, _) = try await transport.data(for: request)
        try checkForBridgeError(in: data)

        let groupsByID = try JSONDecoder().decode([String: GroupResponse].self, from: data)
        return groupsByID.map { id, response in
            HueGroup(
                id: id,
                name: response.name,
                type: response.type,
                anyOn: response.state.anyOn,
                brightness: response.action?.brightness
            )
        }
    }

    public func setGroupState(groupID: String, on: Bool) async throws {
        var request = try makeRequest(to: authedAPIURL(path: "groups/\(groupID)/action"), method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["on": on])
        try await sendAndExpectNoBridgeError(request)
    }

    public func setGroupBrightness(groupID: String, brightness: Int) async throws {
        var request = try makeRequest(to: authedAPIURL(path: "groups/\(groupID)/action"), method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["bri": brightness])
        try await sendAndExpectNoBridgeError(request)
    }

    private func sendAndExpectNoBridgeError(_ request: URLRequest) async throws {
        let (data, _) = try await transport.data(for: request)
        try checkForBridgeError(in: data)
    }

    private func registerURL() throws -> URL {
        guard let url = URL(string: "http://\(bridgeIP)/api") else {
            throw HueCoreError.invalidBridgeIP
        }
        return url
    }

    private func authedAPIURL(path: String) throws -> URL {
        guard let url = URL(string: "http://\(bridgeIP)/api/\(username)") else {
            throw HueCoreError.invalidBridgeIP
        }
        return url.appendingPathComponent(path)
    }

    private func makeRequest(to url: URL, method: String) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 2
        return request
    }

    private func checkForBridgeError(in data: Data) throws {
        guard
            let results = try? JSONDecoder().decode([BridgeResult].self, from: data),
            let first = results.first,
            let bridgeError = first.error
        else {
            return
        }
        throw HueCoreError.bridgeError(bridgeError.description)
    }
}

private struct GroupResponse: Decodable {
    let name: String
    let type: String
    let state: GroupStateResponse
    let action: GroupActionResponse?
}

private struct GroupStateResponse: Decodable {
    let anyOn: Bool

    enum CodingKeys: String, CodingKey {
        case anyOn = "any_on"
    }
}

private struct GroupActionResponse: Decodable {
    let brightness: Int

    enum CodingKeys: String, CodingKey {
        case brightness = "bri"
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
