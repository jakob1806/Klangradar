import SwiftUI

/// Letzter Schritt: Zusammenfassung der gewählten Stadt, Interessen,
/// gefolgten Profile und Benachrichtigungseinstellungen, jede Zeile mit
/// "Bearbeiten"-Sprung zurück zum jeweiligen Schritt, dann Übergang in den
/// personalisierten Home-Feed.
struct OnboardingSummaryView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    var onEditCity: () -> Void = {}
    var onEditFollows: () -> Void = {}
    var onEditNotifications: () -> Void = {}
    let onFinished: () -> Void

    @State private var cityName: String?
    @State private var interestCounts: [InterestCategory: Int] = [:]
    @State private var followedCount = 0
    @State private var activeNotificationCount = 0
    @State private var isLoading = true

    private var totalInterestCount: Int { interestCounts.values.reduce(0, +) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(KlangradarTheme.accent)
                Text("Dein Profil ist eingerichtet")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Du kannst jede Einstellung unten jederzeit im Profil ändern.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                List {
                    Section {
                        summaryRow(
                            systemImage: "map",
                            title: "Stadt",
                            value: cityName ?? "Keine ausgewählt",
                            action: onEditCity
                        )
                        summaryRow(
                            systemImage: "music.quarternote.3",
                            title: "Interessen",
                            value: totalInterestCount > 0 ? "\(totalInterestCount) ausgewählt" : "Noch keine",
                            action: nil
                        )
                        summaryRow(
                            systemImage: "person.2",
                            title: "Gefolgte Profile",
                            value: followedCount > 0 ? "\(followedCount) Personen, Ensembles & Orte" : "Noch keine",
                            action: onEditFollows
                        )
                        summaryRow(
                            systemImage: "bell",
                            title: "Benachrichtigungen",
                            value: activeNotificationCount > 0 ? "\(activeNotificationCount) Kategorien aktiv" : "Alle deaktiviert",
                            action: onEditNotifications
                        )
                    }
                }
                .listStyle(.insetGrouped)
            }

            Button(action: onFinished) {
                Text("Konzerte für dich entdecken").frame(maxWidth: .infinity)
            }
            .authPrimaryButtonStyle()
            .controlSize(.large)
            .authBottomActionLayout()
        }
        .task { await loadSummary() }
    }

    @ViewBuilder
    private func summaryRow(systemImage: String, title: String, value: String, action: (() -> Void)?) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
            if let action {
                Button("Bearbeiten", action: action)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(KlangradarTheme.accent)
            }
        }
    }

    private func loadSummary() async {
        isLoading = true
        defer { isLoading = false }
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }

        async let regionsTask = repository.allCityRegions()
        async let preferredIDTask = repository.preferredRegionID(userID: userID, token: token)
        async let preferencesTask = repository.preferences(userID: userID, token: token)

        for category in InterestCategory.allCases {
            let count = ((try? await repository.selectedInterests(category, userID: userID, token: token)) ?? []).count
            interestCounts[category] = count
        }
        followedCount = (interestCounts[.person] ?? 0) + (interestCounts[.ensemble] ?? 0) + (interestCounts[.venue] ?? 0)
        interestCounts[.person] = nil
        interestCounts[.ensemble] = nil
        interestCounts[.venue] = nil

        if let preferredID = try? await preferredIDTask, let regions = try? await regionsTask {
            cityName = regions.first(where: { $0.id == preferredID })?.nameDE
        }
        if let preferences = try? await preferencesTask {
            activeNotificationCount = [
                preferences.newMatchingEvents, preferences.priceChanges, preferences.almostSoldOut,
                preferences.reminderDayBefore, preferences.followedEnsembleNewEvent
            ].filter { $0 }.count
        }
    }
}
