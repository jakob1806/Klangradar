import SwiftUI

/// Globale Suche über Events, Personen, Ensembles, Venues und Werke —
/// Punkt 2 des Redesigns. Fasst die frühere pro-Scope-Suche aus dem
/// aufgelösten EditorialDashboardView in einer kombinierten Ergebnisliste
/// zusammen.
struct EditorialSearchView: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var events: [EditorialEvent] = []
    @State private var entities: [EditorialEntityKind: [EditorialEntity]] = [:]
    @State private var isLoading = false
    @State private var loadedOnce = false

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if query.isEmpty {
                    ContentUnavailableView(
                        "Redaktion durchsuchen",
                        systemImage: "magnifyingglass",
                        description: Text("Suche nach Veranstaltung, Person, Ensemble, Venue oder Werk.")
                    )
                } else {
                    resultSections
                }
            }
            .navigationTitle("Suche")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Events, Personen, Ensembles, Venues, Werke"
            )
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } } }
            .task { await loadAll() }
        }
    }

    @ViewBuilder
    private var resultSections: some View {
        if !filteredEvents.isEmpty {
            Section("Veranstaltungen") {
                ForEach(filteredEvents) { event in
                    NavigationLink {
                        EditorialEventEditorView(auth: auth, repository: repository, initialEvent: event)
                    } label: {
                        Text(event.title)
                    }
                }
            }
        }
        ForEach(EditorialEntityKind.allCases) { kind in
            let matches = filteredEntities(kind)
            if !matches.isEmpty {
                Section(kind.title) {
                    ForEach(matches) { entity in
                        NavigationLink {
                            EditorialEntityEditorView(auth: auth, repository: repository, entity: entity)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entity.title)
                                if let subtitle = entity.subtitle {
                                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        if filteredEvents.isEmpty, EditorialEntityKind.allCases.allSatisfy({ filteredEntities($0).isEmpty }) {
            ContentUnavailableView.search(text: query)
        }
    }

    private var filteredEvents: [EditorialEvent] {
        events.filter {
            $0.title.localizedStandardContains(query)
                || ($0.subtitle?.localizedStandardContains(query) == true)
                || $0.venueName.localizedStandardContains(query)
        }
    }

    private func filteredEntities(_ kind: EditorialEntityKind) -> [EditorialEntity] {
        (entities[kind] ?? []).filter {
            $0.title.localizedStandardContains(query) || ($0.subtitle?.localizedStandardContains(query) == true)
        }
    }

    @MainActor private func loadAll() async {
        guard !loadedOnce, let token = auth.accessToken else { return }
        loadedOnce = true
        isLoading = true
        defer { isLoading = false }
        async let loadedEvents = try? repository.events(search: "", token: token)
        async let person = try? repository.entities(kind: .person, token: token)
        async let ensemble = try? repository.entities(kind: .ensemble, token: token)
        async let venue = try? repository.entities(kind: .venue, token: token)
        async let work = try? repository.entities(kind: .work, token: token)
        events = (await loadedEvents) ?? []
        entities[.person] = (await person) ?? []
        entities[.ensemble] = (await ensemble) ?? []
        entities[.venue] = (await venue) ?? []
        entities[.work] = (await work) ?? []
    }
}
