import SwiftUI

/// Redaktionsmodus-Shell — Punkt 2 des Redesigns: fünf Hauptbereiche
/// (Heute/Events/Meldungen/Medien/Mehr) statt eines tief verschachtelten
/// Profile-Links. Wird per .fullScreenCover aus ProfileView präsentiert statt
/// gepusht, weil eine eigene Tab-Bar innerhalb eines fremden
/// Navigation-Stacks kein sauberes Apple-Pattern ist.
struct EditorialShellView: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository
    @Environment(\.dismiss) private var dismiss

    @State private var selection: EditorialTab = .today

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                EditorialTodayView(auth: auth, repository: repository)
                    .editorialGlobalToolbar(auth: auth, repository: repository)
            }
            .tag(EditorialTab.today)
            .tabItem { Label("Heute", systemImage: "sun.max.fill") }

            EditorialEventsListView(auth: auth, repository: repository)
                .tag(EditorialTab.events)
                .tabItem { Label("Events", systemImage: "calendar") }

            EditorialReportsTabView(auth: auth, repository: repository)
                .tag(EditorialTab.reports)
                .tabItem { Label("Meldungen", systemImage: "flag.fill") }

            EditorialMediaTabView(auth: auth, repository: repository)
                .tag(EditorialTab.media)
                .tabItem { Label("Medien", systemImage: "photo.stack.fill") }

            EditorialMoreView(auth: auth, repository: repository) { dismiss() }
                .tag(EditorialTab.more)
                .tabItem { Label("Mehr", systemImage: "ellipsis.circle.fill") }
        }
        .tint(KlangradarTheme.accent)
    }
}

private enum EditorialTab: Hashable {
    case today, events, reports, media, more
}
