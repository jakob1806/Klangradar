import SwiftUI

@main
@MainActor
struct KlangradarNativeApp: App {
    private let environment = AppEnvironment.make()
    @AppStorage(KlangradarTheme.accentStorageKey) private var accentColorHex = KlangradarTheme.defaultAccentHex

    var body: some Scene {
        WindowGroup {
            Group {
                if environment.isUsingPreviewData {
                    SupabaseConfigurationMissingView()
                } else {
                    RootTabView(environment: environment)
                }
            }
            .tint(KlangradarTheme.color(hex: accentColorHex) ?? KlangradarTheme.accent)
            .environment(\.timeZone, KlangradarDateTime.timeZone)
            .environment(\.calendar, KlangradarDateTime.calendar)
        }
    }
}

/// Ein fehlkonfigurierter Geräte-Build darf nicht mehr wie eine zweite,
/// datenlose Klangradar-App aussehen. Preview-Repositories bleiben intern
/// für SwiftUI-Previews verfügbar, der echte App-Einstieg zeigt stattdessen
/// einen eindeutigen Konfigurationsfehler.
private struct SupabaseConfigurationMissingView: View {
    var body: some View {
        ContentUnavailableView {
            Label("App nicht konfiguriert", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text("Dieser Build enthält keine Supabase-Konfiguration und kann deshalb nicht verwendet werden.")
        }
        .padding()
    }
}
