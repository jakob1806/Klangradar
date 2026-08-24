import SwiftUI

/// Letzter Schritt: kurze Zusammenfassung der gewählten Interessen, dann
/// Übergang in den personalisierten Home-Feed.
struct OnboardingSummaryView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let onFinished: () -> Void

    @State private var selectedCount = 0

    var body: some View {
        OnboardingStepScaffold(
            title: "Dein Profil ist eingerichtet",
            subtitle: selectedCount > 0
                ? "\(selectedCount) Interessen gespeichert — deine Empfehlungen richten sich ab jetzt danach."
                : "Du kannst deine Interessen jederzeit im Profil ergänzen.",
            systemImage: "checkmark.circle.fill",
            content: { EmptyView() },
            primaryTitle: "Konzerte für dich entdecken",
            onPrimary: { onFinished() }
        )
        .task { await loadSummary() }
    }

    private func loadSummary() async {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        var total = 0
        for category in InterestCategory.allCases {
            total += ((try? await repository.selectedInterests(category, userID: userID, token: token)) ?? []).count
        }
        selectedCount = total
    }
}
