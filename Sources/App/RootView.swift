import HueCore
import SwiftUI

struct RootView: View {
    @AppStorage("hue.bridgeIP") private var bridgeIP = ""
    @AppStorage("hue.username") private var username = ""

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    var body: some View {
        if bridgeIP.isEmpty || username.isEmpty {
            SetupView(
                discovery: dependencies.discoveryClient(),
                makeBridgeClient: dependencies.bridgeClient(bridgeIP:username:),
                bridgeIP: $bridgeIP,
                username: $username
            )
        } else {
            // Ready-made dependencies from the composition root; the view never
            // constructs a bridge or cache client.
            LampsView(
                updater: dependencies.lampsUpdater(bridgeIP: bridgeIP, username: username),
                onResetPairing: {
                    bridgeIP = ""
                    username = ""
                }
            )
        }
    }
}

#Preview {
    RootView(dependencies: AppDependencies())
}
