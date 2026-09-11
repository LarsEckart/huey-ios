import SwiftUI

@main
struct HueyIOSApp: App {
    private let dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}
