import Foundation
import HueCore

/// Composition root.
///
/// It owns the single network transport and builds ready-made HueCore
/// clients. Views receive these ready-made dependencies (never the whole
/// factory and never construct a bridge, discovery, or cache client
/// themselves): the concrete URLSession and UserDefaults adapters live here
/// and in `URLSessionHTTPTransport` / `HueGroupCache`. The transport is
/// injectable so tests or a preview can substitute one without touching the
/// concrete adapters.
struct AppDependencies {
    private let transport: any HTTPTransport

    init(transport: any HTTPTransport = URLSessionHTTPTransport()) {
        self.transport = transport
    }

    func bridgeClient(bridgeIP: String, username: String) -> any HueBridgeClient {
        HueBridgeHTTPClient(bridgeIP: bridgeIP, username: username, transport: transport)
    }

    func discoveryClient() -> any HueDiscovering {
        HueDiscoveryClient(transport: transport)
    }

    func groupCache(bridgeIP: String, username: String) -> any HueGroupCaching {
        HueGroupCache(bridgeIP: bridgeIP, username: username)
    }

    /// A ready-made updater that owns the current list and reconciles updates.
    func lampsUpdater(bridgeIP: String, username: String) -> HueGroupUpdater {
        let cache = groupCache(bridgeIP: bridgeIP, username: username)
        return HueGroupUpdater(
            client: bridgeClient(bridgeIP: bridgeIP, username: username),
            cache: cache,
            initialGroups: cache.load()
        )
    }
}
