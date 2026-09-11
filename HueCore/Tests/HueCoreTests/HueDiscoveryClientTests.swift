import Foundation
import XCTest

@testable import HueCore

final class HueDiscoveryClientTests: XCTestCase {
    func testDiscoverDecodesAndNormalizes() async throws {
        let payload = """
            [
                { "id": "2", "internalipaddress": "192.168.1.3" },
                { "id": "1", "internalipaddress": "192.168.1.2" },
                { "id": "1", "internalipaddress": "192.168.1.2" }
            ]
            """
        let transport = StubHTTPTransport(handlers: [successJSON(payload)])
        let client = HueDiscoveryClient(transport: transport, discoveryURL: URL(string: "http://discover.test")!)

        let bridges = try await client.discover()

        XCTAssertEqual(
            bridges,
            [
                HueBridge(id: "1", internalIPAddress: "192.168.1.2"),
                HueBridge(id: "2", internalIPAddress: "192.168.1.3"),
            ])
    }

    func testDiscoverFallsBackToIPWhenIDMissing() async throws {
        let payload = """
            [ { "internalipaddress": "192.168.1.2" } ]
            """
        let transport = StubHTTPTransport(handlers: [successJSON(payload)])
        let client = HueDiscoveryClient(transport: transport, discoveryURL: URL(string: "http://discover.test")!)

        let bridges = try await client.discover()

        XCTAssertEqual(bridges.first?.id, "192.168.1.2")
        XCTAssertEqual(bridges.first?.displayName, "192.168.1.2")
    }

    func testDiscoverThrowsOnNonSuccessHTTPStatus() async {
        let transport = StubHTTPTransport(handlers: [
            { _ in
                let response = HTTPURLResponse(
                    url: URL(string: "http://discover.test")!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(), response)
            }
        ])
        let client = HueDiscoveryClient(transport: transport, discoveryURL: URL(string: "http://discover.test")!)

        do {
            _ = try await client.discover()
            XCTFail("expected discover to throw")
        } catch let error as HueCoreError {
            XCTAssertEqual(error, .httpStatus(500))
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    private func successJSON(_ string: String) -> (URLRequest) throws -> (Data, URLResponse) {
        { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://discover.test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(string.utf8), response)
        }
    }
}
