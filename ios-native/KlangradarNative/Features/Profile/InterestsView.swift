import SwiftUI

/// Aus ProfileView.swift extrahiert, damit dieselbe Ansicht sowohl von
/// Profil → Interessen (per NavigationLink, mit eigenem Navigationstitel)
/// als auch als eingebetteter Onboarding-Schritt (ohne umgebenden
/// NavigationStack — `.navigationTitle` bleibt dort einfach wirkungslos)
/// verwendet werden kann, ohne die Interessen-Logik zu duplizieren.
struct InterestsView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    /// Onboarding-Schritt "Interessen" zeigt bewusst nur Genres — Werke
    /// entfallen dort komplett, Personen/Ensembles/Venues bekommen eigene
    /// Folgen-Schritte (siehe FollowCategoryStepView). Ohne Vorgabe (Profil
    /// → Interessen) bleibt der volle Kategorie-Umschalter wie bisher.
    var fixedCategory: InterestCategory? = nil
    @State private var category: InterestCategory = .genre
    @State private var options: [InterestOption] = []
    @State private var selected: Set<String> = []
    @State private var searchText = ""

    private var filteredOptions: [InterestOption] {
        searchText.isEmpty ? options : options.filter { $0.label.localizedStandardContains(searchText) }
    }

    /// Als Onboarding-Schritt (fixedCategory gesetzt) gibt es keinen
    /// umgebenden NavigationStack, also kein valides Andockziel für
    /// `.searchable()` — dort ein eigenes, inline gerendertes Suchfeld
    /// statt des System-Modifiers (siehe OnboardingSearchField).
    private var usesInlineSearch: Bool { fixedCategory != nil }

    private var showsThumbnails: Bool {
        category == .person || category == .ensemble || category == .venue
    }

    private var entityKind: EntityKind {
        switch category {
        case .person: .person
        case .ensemble: .ensemble
        case .venue: .venue
        case .genre, .work: .work
        }
    }

    var body: some View {
        List {
            if fixedCategory == nil {
                Section {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(InterestCategory.allCases, id: \.self) { item in
                                Button { category = item } label: {
                                    Label(item.title, systemImage: item.systemImage)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(category == item ? KlangradarTheme.accent : Color.secondary.opacity(0.12), in: .capsule)
                                        .foregroundStyle(category == item ? .white : .primary)
                                }.buttonStyle(.plain)
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
            }
            if usesInlineSearch {
                Section {
                    OnboardingSearchField(prompt: "\(category.title) durchsuchen", text: $searchText)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 4)
                }
            }
            Section("\(category.title) · \(selected.count) ausgewählt") {
                ForEach(filteredOptions) { option in
                    Button { toggle(option.id) } label: {
                        HStack(spacing: 12) {
                            if showsThumbnails { InterestOptionThumbnail(option: option, kind: entityKind) }
                            Text(option.label).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: selected.contains(option.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 28, weight: .regular))
                                .frame(width: 44, height: 44)
                                .foregroundStyle(selected.contains(option.id) ? KlangradarTheme.accent : .secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Interessen")
        .if(!usesInlineSearch) { view in
            view.searchable(text: $searchText, prompt: "\(category.title) durchsuchen")
        }
        .onAppear {
            if let fixedCategory { category = fixedCategory }
        }
        .task(id: category) { searchText = ""; await load() }
    }

    private func load() async {
        guard let repository else { return }
        options = (try? await repository.interestOptions(category)) ?? []
        guard let id = auth.userID, let token = auth.accessToken else { return }
        selected = (try? await repository.selectedInterests(category, userID: id, token: token)) ?? []
    }

    private func toggle(_ id: String) {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        let newValue = !selected.contains(id)
        if newValue { selected.insert(id) } else { selected.remove(id) }
        Task { try? await repository.setInterest(category, id: id, selected: newValue, userID: userID, token: token) }
    }
}
