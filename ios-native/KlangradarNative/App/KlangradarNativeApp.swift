import SwiftUI

@main
@MainActor
struct KlangradarNativeApp: App {
    private let environment = AppEnvironment.make()
    @AppStorage(KlangradarTheme.accentStorageKey) private var accentColorHex = KlangradarTheme.defaultAccentHex

    var body: some Scene {
        WindowGroup {
            RootTabView(environment: environment)
                .tint(KlangradarTheme.color(hex: accentColorHex) ?? KlangradarTheme.accent)
                .environment(\.timeZone, KlangradarDateTime.timeZone)
                .environment(\.calendar, KlangradarDateTime.calendar)
        }
    }
}
