import Foundation
import HueCore

/// URLSession-backed adapter for the core's HTTP seam.
///
/// This is the only place the app touches URLSession; the core never sees it.
struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
