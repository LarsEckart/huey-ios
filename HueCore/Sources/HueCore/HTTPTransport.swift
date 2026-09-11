import Foundation

/// The only network seam the core needs.
///
/// The core's bridge and discovery clients build `URLRequest`s and assemble
/// results from the response data; they never touch `URLSession`. URLSession
/// stays behind a thin outer adapter, and tests substitute a stub that returns
/// fixture data, so response mapping can run with no live network.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
