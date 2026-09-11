import Foundation

/// Errors the core can produce, from bridge responses or the transport itself.
///
/// Being a fixed enum keeps workflow outcomes equatable so tests can assert on
/// them precisely instead of on formatted strings.
public enum HueCoreError: LocalizedError, Equatable, Sendable {
    case invalidBridgeIP
    case malformedResponse(String)
    case bridgeError(String)
    case httpStatus(Int)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBridgeIP:
            "Bridge IP is invalid."
        case .malformedResponse(let message):
            "Unexpected bridge response: \(message)"
        case .bridgeError(let message):
            message
        case .httpStatus(let statusCode):
            "Discovery service returned HTTP \(statusCode)."
        case .transport(let message):
            message
        }
    }

    /// Coerces an arbitrary thrown error into a stable domain error.
    ///
    /// User-facing message is preserved: a `LocalizedError` keeps its
    /// `localizedDescription`, so network failures do not degrade into Swift/
    /// debug representations on screen.
    public static func normalizing(_ error: any Error) -> Self {
        if let error = error as? Self {
            return error
        }
        if let localized = error as? any LocalizedError,
            let message = localized.errorDescription
        {
            return .transport(message)
        }
        return .transport(String(describing: error))
    }
}
