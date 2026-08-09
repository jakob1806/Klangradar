import SwiftUI

@main
@MainActor
struct KlangradarNativeApp: App {
    private let environment = AppEnvironment.make()

    var body: some Scene {
        WindowGroup {
            RootTabView(environment: environment)
                .tint(KlangradarTheme.accent)
        }
    }
}
