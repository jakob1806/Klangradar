import SwiftUI

/// Mehr-Tab — Punkt 2 des Redesigns: Personen/Ensembles/Venues/Werke (vorher
/// im aufgelösten EditorialDashboardView per Scope-Picker), Schnellkorrektur,
/// "zuletzt bearbeitet" (RecentlyEditedStore) und der Ausstieg aus dem
/// Redaktionsmodus.
struct EditorialMoreView: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository
    let onExit: () -> Void

    @ObservedObject private var recents = RecentlyEditedStore.shared

    var body: some View {
        NavigationStack {
            List {
                if !recents.items.isEmpty {
                    Section("Zuletzt bearbeitet") {
                        ForEach(recents.items) { item in
                            NavigationLink {
                                destination(for: item)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                    Text(item.kind.title).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Werkzeuge") {
                    NavigationLink {
                        EditorialQuickFixView(auth: auth, repository: repository)
                    } label: {
                        Label("Schnellkorrektur", systemImage: "bolt.fill")
                    }
                }

                Section("Stammdaten") {
                    ForEach(EditorialEntityKind.allCases) { kind in
                        NavigationLink {
                            EditorialEntityListView(auth: auth, repository: repository, kind: kind)
                        } label: {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                }

                Section {
                    Button("Redaktionsmodus verlassen", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        onExit()
                    }
                }
            }
            .navigationTitle("Mehr")
            .editorialGlobalToolbar(auth: auth, repository: repository)
        }
    }

    @ViewBuilder
    private func destination(for item: RecentlyEditedItem) -> some View {
        if item.kind == .event {
            EditorialRecentEventLoader(auth: auth, repository: repository, eventID: item.id)
        } else if let entityKind = item.kind.entityKind {
            EditorialRecentEntityLoader(auth: auth, repository: repository, kind: entityKind, entityID: item.id)
        }
    }
}

/// Liste je Entity-Kind — aus dem aufgelösten EditorialDashboardView
/// übernommen (dort war es der Nicht-Events-Zweig des Scope-Pickers).
struct EditorialEntityListView: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository
    let kind: EditorialEntityKind

    @State private var entities: [EditorialEntity] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("\(kind.title) werden geladen …")
            } else if let errorMessage {
                ContentUnavailableView("Nicht verfügbar", systemImage: "exclamationmark.shield", description: Text(errorMessage))
            } else {
                List(filtered) { entity in
                    NavigationLink {
                        EditorialEntityEditorView(auth: auth, repository: repository, entity: entity)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entity.title)
                                if let subtitle = entity.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                            }
                        } icon: {
                            EditorialThumbnail(url: entity.imageURL, symbol: kind.symbol)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await load() }
            }
        }
        .navigationTitle(kind.title)
        .searchable(text: $searchText, prompt: "\(kind.title) durchsuchen")
        .task { await load() }
    }

    private var filtered: [EditorialEntity] {
        guard !searchText.isEmpty else { return entities }
        return entities.filter { $0.title.localizedStandardContains(searchText) || ($0.subtitle?.localizedStandardContains(searchText) == true) }
    }

    @MainActor private func load() async {
        guard let token = auth.accessToken else { errorMessage = "Bitte zuerst anmelden."; isLoading = false; return }
        isLoading = entities.isEmpty
        defer { isLoading = false }
        do {
            entities = try await repository.entities(kind: kind, token: token)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct EditorialThumbnail: View {
    let url: String?
    let symbol: String
    var body: some View {
        CachedAsyncImage(url: url.flatMap(URL.init(string:))) { phase in
            if case let .success(image) = phase {
                image.resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.1).overlay { Image(systemName: symbol).foregroundStyle(.secondary) }
            }
        }
        .frame(width: 42, height: 42).clipShape(.rect(cornerRadius: 9)).clipped()
    }
}

private struct EditorialRecentEventLoader: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository
    let eventID: UUID
    @State private var event: EditorialEvent?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let event {
                EditorialEventEditorView(auth: auth, repository: repository, initialEvent: event)
            } else if let errorMessage {
                ContentUnavailableView("Nicht gefunden", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ProgressView().task { await load() }
            }
        }
    }

    private func load() async {
        guard let token = auth.accessToken else { return }
        do { event = try await repository.detail(eventID: eventID, token: token).event }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct EditorialRecentEntityLoader: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository
    let kind: EditorialEntityKind
    let entityID: UUID
    @State private var entity: EditorialEntity?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let entity {
                EditorialEntityEditorView(auth: auth, repository: repository, entity: entity)
            } else if let errorMessage {
                ContentUnavailableView("Nicht gefunden", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ProgressView().task { await load() }
            }
        }
    }

    private func load() async {
        guard let token = auth.accessToken else { return }
        do {
            let all = try await repository.entities(kind: kind, token: token)
            guard let match = all.first(where: { $0.id == entityID }) else {
                errorMessage = "Eintrag wurde inzwischen gelöscht."
                return
            }
            entity = match
        } catch { errorMessage = error.localizedDescription }
    }
}
