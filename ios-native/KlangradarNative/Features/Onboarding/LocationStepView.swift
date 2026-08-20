import SwiftUI

/// Schritt "Standort". Bei Erlaubnis wird die echte Position per
/// `update_home_location`-RPC gespeichert; bei Ablehnung oder manuellem
/// Fallback wird stattdessen die (aktuell einzige) aktive Region aus
/// `activeRegions()` gesetzt — passt zu `regions.is_active`
/// (20260819000005_regions.sql), das bewusst nur München enthält.
struct LocationStepView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let onFinished: () -> Void

    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var activeRegionName: String?

    var body: some View {
        OnboardingStepScaffold(
            title: "Dein Standort",
            subtitle: "Für Veranstaltungen in deiner Nähe.",
            systemImage: "location.circle",
            content: {
                if let activeRegionName {
                    Text("Klangradar deckt aktuell nur \(activeRegionName) ab.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            },
            primaryTitle: "Standort erlauben",
            onPrimary: { Task { await requestLocation() } },
            secondaryTitle: manualFallbackTitle,
            onSecondary: { Task { await useManualFallback() } },
            errorMessage: errorMessage,
            isWorking: isWorking
        )
        .task { await loadActiveRegion() }
    }

    private var manualFallbackTitle: String {
        activeRegionName.map { "Ohne Standort fortfahren — \($0) verwenden" } ?? "Ohne Standort fortfahren"
    }

    private func loadActiveRegion() async {
        activeRegionName = (try? await repository?.activeRegions())?.first?.name
    }

    private func requestLocation() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let coordinate = try await LocationRequester().requestOnce()
            if let token = auth.accessToken {
                try? await repository?.updateHomeLocation(latitude: coordinate.latitude, longitude: coordinate.longitude, token: token)
            }
            onFinished()
        } catch {
            // Ablehnung ist kein technischer Fehler, der den Nutzer
            // blockieren soll — direkt auf den manuellen Fallback zeigen
            // statt eine rote Fehlermeldung zu präsentieren.
            await useManualFallback()
        }
    }

    private func useManualFallback() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        guard let repository, let userID = auth.userID, let token = auth.accessToken,
              let region = try? await repository.activeRegions().first else {
            onFinished()
            return
        }
        try? await repository.setPreferredRegion(regionID: region.id, userID: userID, token: token)
        onFinished()
    }
}
