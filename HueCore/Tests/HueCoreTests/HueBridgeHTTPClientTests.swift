import Foundation
import XCTest

@testable import HueCore

final class HueBridgeHTTPClientTests: XCTestCase {
    func testFetchGroupsMapsFixtureToDomainValues() async throws {
        let payload = """
            {
                "1": { "name": "Bedroom", "type": "Room",
                       "state": { "any_on": true },
                       "action": { "bri": 142 } },
                "2": { "name": "Office", "type": "Zone",
                       "state": { "any_on": false },
                       "action": { "bri": 200 } }
            }
            """
        let transport = StubHTTPTransport(handlers: [successJSON(payload)])
        let client = HueBridgeHTTPClient(bridgeIP: "192.168.1.2", username: "user", transport: transport)

        let groups = try await client.fetchGroups()

        let byID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        XCTAssertEqual(byID["1"], HueGroup(id: "1", name: "Bedroom", type: "Room", anyOn: true, brightness: 142))
        XCTAssertEqual(byID["2"], HueGroup(id: "2", name: "Office", type: "Zone", anyOn: false, brightness: 200))
        XCTAssertEqual(transport.recordedRequests.first?.httpMethod, "GET")
    }

    func testFetchGroupsReportsBridgeErrorFromResponse() async {
        let payload = """
            [ { "error": { "type": 1, "address": "/groups", "description": "unauthorized user" } } ]
            """
        let transport = StubHTTPTransport(handlers: [successJSON(payload)])
        let client = HueBridgeHTTPClient(bridgeIP: "192.168.1.2", username: "user", transport: transport)

        do {
            _ = try await client.fetchGroups()
            XCTFail("expected fetchGroups to throw")
        } catch let error as HueCoreError {
            XCTAssertEqual(error, .bridgeError("unauthorized user"))
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testRegisterReturnsUsernameOnSuccess() async throws {
        let payload = """
            [ { "success": { "username": "newuser123" } } ]
            """
        let transport = StubHTTPTransport(handlers: [successJSON(payload)])
        let client = HueBridgeHTTPClient(bridgeIP: "192.168.1.2", username: "", transport: transport)

        let username = try await client.register(deviceType: "huey-ios#iphone")

        XCTAssertEqual(username, "newuser123")
        let request = try XCTUnwrap(transport.recordedRequests.first)
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testRegisterThrowsWhenBridgeRejects() async {
        let payload = """
            [ { "error": { "type": 101, "address": "/", "description": "link button not pressed" } } ]
            """
        let transport = StubHTTPTransport(handlers: [successJSON(payload)])
        let client = HueBridgeHTTPClient(bridgeIP: "192.168.1.2", username: "", transport: transport)

        await assertThrowsError(from: {
            _ = try await client.register(deviceType: "huey-ios#iphone")
        })
    }

    func testSetGroupStateSendsExpectedBody() async throws {
        let transport = StubHTTPTransport(handlers: [successJSON("[]")])
        let client = HueBridgeHTTPClient(bridgeIP: "192.168.1.2", username: "user", transport: transport)

        try await client.setGroupState(groupID: "3", on: true)

        let request = try XCTUnwrap(transport.recordedRequests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(try jsonString(body), "{\"on\":true}")
    }

    func testSetGroupBrightnessSendsClampedBody() async throws {
        let transport = StubHTTPTransport(handlers: [successJSON("[]")])
        let client = HueBridgeHTTPClient(bridgeIP: "192.168.1.2", username: "user", transport: transport)

        try await client.setGroupBrightness(groupID: "3", brightness: 200)

        let request = try XCTUnwrap(transport.recordedRequests.first)
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(try jsonString(body), "{\"bri\":200}")
    }

    func testRegisterPostsToUsernameIndependentAPIEndpoint() async throws {
        let payload = """
            [ { "success": { "username": "newuser123" } } ]
            """
        let transport = StubHTTPTransport(handlers: [successJSON(payload)])
        // Username is nonempty to prove registration ignores it and posts to /api.
        let client = HueBridgeHTTPClient(bridgeIP: "192.168.1.2", username: "user", transport: transport)

        let username = try await client.register(deviceType: "huey-ios#iphone")

        XCTAssertEqual(username, "newuser123")
        let request = try XCTUnwrap(transport.recordedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "http://192.168.1.2/api")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testRegisterRequestCarriesBodyHeadersAndTimeout() async throws {
        let payload = """
            [ { "success": { "username": "newuser123" } } ]
            """
        let transport = StubHTTPTransport(handlers: [successJSON(payload)])
        let client = HueBridgeHTTPClient(bridgeIP: "192.168.1.2", username: "", transport: transport)

        _ = try await client.register(deviceType: "huey-ios#iphone")

        let request = try XCTUnwrap(transport.recordedRequests.first)
        XCTAssertEqual(request.timeoutInterval, 2)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(try jsonString(body), "{\"devicetype\":\"huey-ios#iphone\"}")
    }

    func testSetGroupStateSendsExpectedURLBodyHeadersAndTimeout() async throws {
        let transport = StubHTTPTransport(handlers: [successJSON("[]")])
        let client = HueBridgeHTTPClient(bridgeIP: "192.168.1.2", username: "user", transport: transport)

        try await client.setGroupState(groupID: "3", on: true)

        let request = try XCTUnwrap(transport.recordedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "http://192.168.1.2/api/user/groups/3/action")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.timeoutInterval, 2)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(try jsonString(body), "{\"on\":true}")
    }

    func testSetGroupBrightnessSendsExpectedURLAndClampedBody() async throws {
        let transport = StubHTTPTransport(handlers: [successJSON("[]")])
        let client = HueBridgeHTTPClient(bridgeIP: "192.168.1.2", username: "user", transport: transport)

        try await client.setGroupBrightness(groupID: "3", brightness: 200)

        let request = try XCTUnwrap(transport.recordedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "http://192.168.1.2/api/user/groups/3/action")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(try jsonString(body), "{\"bri\":200}")
    }

    func testSetGroupStateReportsBridgeErrorFromResponse() async {
        let payload = """
            [ { "error": { "type": 1, "address": "/groups/3/action", "description": "unauthorized user" } } ]
            """
        let transport = StubHTTPTransport(handlers: [successJSON(payload)])
        let client = HueBridgeHTTPClient(bridgeIP: "192.168.1.2", username: "user", transport: transport)

        do {
            try await client.setGroupState(groupID: "3", on: true)
            XCTFail("expected setGroupState to throw")
        } catch let error as HueCoreError {
            XCTAssertEqual(error, .bridgeError("unauthorized user"))
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testSetGroupBrightnessReportsBridgeErrorFromResponse() async {
        let payload = """
            [ { "error": { "type": 1, "address": "/groups/3/action", "description": "device turned off" } } ]
            """
        let transport = StubHTTPTransport(handlers: [successJSON(payload)])
        let client = HueBridgeHTTPClient(bridgeIP: "192.168.1.2", username: "user", transport: transport)

        do {
            try await client.setGroupBrightness(groupID: "3", brightness: 200)
            XCTFail("expected setGroupBrightness to throw")
        } catch let error as HueCoreError {
            XCTAssertEqual(error, .bridgeError("device turned off"))
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testInvalidBridgeIPTurnsIntoDomainError() async {
        let transport = StubHTTPTransport()
        let client = HueBridgeHTTPClient(bridgeIP: "not a url", username: "user", transport: transport)

        await assertThrowsError(from: {
            _ = try await client.fetchGroups()
        })
    }

    // MARK: Helpers

    private func successJSON(_ string: String) -> (URLRequest) throws -> (Data, URLResponse) {
        { _ in (Data(string.utf8), self.makeResponse()) }
    }

    private func makeResponse() -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "http://bridge/api")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private func jsonString(_ data: Data) throws -> String {
        try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func assertThrowsError(
        from operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("expected the operation to throw", file: file, line: line)
        } catch {
            // Expected.
        }
    }
}
