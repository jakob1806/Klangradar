import SwiftUI

/// Medien-Tab — Punkt 7 des Redesigns. Phase 1 zeigt bereits echten Inhalt
/// (Events/Entitäten ohne Bild); reichere Funktionen (Lizenz/Credit-Felder,
/// Galerie-Crop, Fokuspunkt) folgen in Phase 6.
struct EditorialMediaTabView: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository

    @State private var eventsWithoutImage: [EditorialEvent] = []
    @State private var entitiesWithoutImage: [EditorialEntity] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                EditorialBackground()
                Group {
                    if isLoading {
                        ProgressView("Wird geprüft …").tint(KlangradarTheme.accent)
                    } else if let errorMessage {
                        ContentUnavailableView("Nicht verfügbar", systemImage: "exclamationmark.shield", description: Text(errorMessage))
                    } else if eventsWithoutImage.isEmpty, entitiesWithoutImage.isEmpty {
                        ContentUnavailableView("Alles hat ein Bild", systemImage: "checkmark.circle", description: Text("Aktuell fehlt bei keiner Veranstaltung oder Entität ein Bild."))
                    } else {
                        list
                    }
                }
            }
            .navigationTitle("Medien")
            .editorialGlobalToolbar(auth: auth, repository: repository)
            .task { await load() }
        }
    }

    private var list: some View {
        List {
            if !eventsWithoutImage.isEmpty {
                Section("Veranstaltungen ohne Bild") {
                    ForEach(eventsWithoutImage) { event in
                        NavigationLink {
                            EditorialEventEditorView(auth: auth, repository: repository, initialEvent: event)
                        } label: {
                            Text(event.title)
                        }
                    }
                }
            }
            if !entitiesWithoutImage.isEmpty {
                Section("Ohne Bild") {
                    ForEach(entitiesWithoutImage) { entity in
                        NavigationLink {
                            EditorialEntityEditorView(auth: auth, repository: repository, entity: entity)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entity.title)
                                Text(entity.kind.title).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
    }

    @MainActor private func load() async {
        guard let token = auth.accessToken else { errorMessage = "Bitte zuerst anmelden."; isLoading = false; return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let events = repository.events(search: "", token: token)
            async let persons = repository.entities(kind: .person, token: token)
            async let ensembles = repository.entities(kind: .ensemble, token: token)
            async let venues = repository.entities(kind: .venue, token: token)
            let loadedEvents = try await events
            let loadedPersons = try await persons
            let loadedEnsembles = try await ensembles
            let loadedVenues = try await venues
            eventsWithoutImage = loadedEvents.filter { ($0.imageURL ?? "").isEmpty }
            entitiesWithoutImage = (loadedPersons + loadedEnsembles + loadedVenues).filter { ($0.imageURL ?? "").isEmpty }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}
