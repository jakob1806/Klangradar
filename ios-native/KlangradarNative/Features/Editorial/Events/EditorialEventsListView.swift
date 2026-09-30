import SwiftUI

/// Events-Tab-Root — Punkt 2 des Redesigns: fester Scope auf Veranstaltungen,
/// kein Scope-Picker mehr nötig. Personen/Ensembles/Venues/Werke leben jetzt
/// im Mehr-Tab, siehe EditorialMoreView.
struct EditorialEventsListView: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository

    @State private var events: [EditorialEvent] = []
    @State private var searchText = ""
    @State private var scope: EditorialEventScope = .upcoming
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                EditorialBackground()
                VStack(spacing: 0) {
                    EditorialEventScopePicker(selection: $scope)
                        .padding(.vertical, 8)

                    Group {
                        if isLoading {
                            ProgressView("Veranstaltungen werden geladen …").tint(KlangradarTheme.accent)
                        } else if let errorMessage {
                            ContentUnavailableView("Redaktion nicht verfügbar", systemImage: "exclamationmark.shield", description: Text(errorMessage))
                        } else {
                            list
                        }
                    }
                }
            }
            .navigationTitle("Events")
            .searchable(text: $searchText, prompt: "Events durchsuchen")
            .editorialGlobalToolbar(auth: auth, repository: repository) { Task { await load() } }
            .task(id: scope) { await load() }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(filteredEvents) { event in
                    NavigationLink {
                        EditorialEventEditorView(auth: auth, repository: repository, initialEvent: event)
                    } label: {
                        EditorialEventRow(event: event)
                    }
                }
            } header: {
                HStack { Text(scope.title); Spacer(); Text("\(filteredEvents.count)").foregroundStyle(.secondary) }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
    }

    private var filteredEvents: [EditorialEvent] {
        guard !searchText.isEmpty else { return events }
        return events.filter {
            $0.title.localizedStandardContains(searchText)
                || ($0.subtitle?.localizedStandardContains(searchText) == true)
                || $0.venueName.localizedStandardContains(searchText)
        }
    }

    @MainActor private func load() async {
        guard let token = auth.accessToken else { errorMessage = "Bitte zuerst anmelden."; isLoading = false; return }
        isLoading = events.isEmpty
        defer { isLoading = false }
        do {
            events = try await repository.events(search: "", scope: scope, token: token)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

/// Nutzerfeedback (2026-09-30): Bearbeitung bereits vergangener Konzerte
/// (z.B. um nachträglich falsch erkannte Besetzung/Programm zu korrigieren)
/// soll auch im Redaktionsmodus möglich sein — vorher zeigte diese Liste
/// (und die darauf aufbauende globale Suche) ausschließlich Events ab heute.
private struct EditorialEventScopePicker: View {
    @Binding var selection: EditorialEventScope

    var body: some View {
        Picker("Zeitraum", selection: $selection) {
            ForEach(EditorialEventScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }
}

/// Aus dem aufgelösten EditorialDashboardView übernommen.
struct EditorialEventRow: View {
    let event: EditorialEvent
    var body: some View {
        HStack(spacing: 13) {
            CachedAsyncImage(url: event.imageURL.flatMap(URL.init(string:))) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.08).overlay { Image(systemName: "photo") }
                }
            }
                .frame(width: 72, height: 72).clipShape(.rect(cornerRadius: 12)).clipped()
            VStack(alignment: .leading, spacing: 5) {
                Text(event.title).font(.headline).lineLimit(2)
                Text(KlangradarDateTime.string(event.startDate, format: "EEE, d. MMM · HH:mm") + " · " + event.venueName).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(); Image(systemName: "pencil.circle.fill").font(.title2).foregroundStyle(KlangradarTheme.accent)
        }
    }
}
