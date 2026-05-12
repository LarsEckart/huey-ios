import SwiftUI

struct RootView: View {
    @AppStorage("hue.bridgeIP") private var bridgeIP = ""
    @AppStorage("hue.username") private var username = ""

    var body: some View {
        if bridgeIP.isEmpty || username.isEmpty {
            SetupView(bridgeIP: $bridgeIP, username: $username)
        } else {
            LampsView(
                bridgeIP: bridgeIP,
                username: username,
                onResetPairing: {
                    bridgeIP = ""
                    username = ""
                }
            )
        }
    }
}

#Preview {
    RootView()
}
