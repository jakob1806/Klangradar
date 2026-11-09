// Aus ProfileView.swift ausgelagert (09.11.2026): Merkliste, geplante Konzerte, eigene Listen.
import SwiftUI
import UIKit

struct FavoriteEventsView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
    var initial: [ConcertEvent] = []
    @State private var events: [ConcertEvent] = []
    @State private var loaded = false

    var body: some View {
        List(events) { event in
            NavigationLink {
                EventDetailView(
                    event: event,
                    repository: eventRepository,
                    contentRepository: contentRepository
                )
            } label: {
                FavoriteEventRow(event: event)
            }
        }
            .overlay { if events.isEmpty && loaded { ContentUnavailableView("Noch keine Favoriten", systemImage: "heart", description: Text("Markierte Veranstaltungen erscheinen hier.")) } }
            .overlay { if events.isEmpty && !loaded { ProgressView() } }
            .navigationTitle("Gemerkt")
            .task {
                // 07.11.2026: sofort die schon bekannten Einträge zeigen; ein
                // Fehler beim Nachladen leert die Liste nicht.
                if events.isEmpty { events = initial }
                defer { loaded = true }
                guard let repository, let id = auth.userID, let token = auth.accessToken else { return }
                guard let fresh = try? await repository.favoriteEvents(userID: id, token: token), !Task.isCancelled else { return }
                let merged = fresh.isEmpty && !initial.isEmpty ? initial : fresh
                events = (try? await eventRepository.enrichingImages(in: merged)) ?? merged
            }
    }
}

/// Für die "Geplant"-Kachel unter "Mein Klangradar" -- Events, die per
/// favorites.status='attending' als geplant markiert sind (siehe
/// UserRepository.plannedEvents), mit derselben Miniaturbild-Zeile wie
/// FavoriteEventsView.
struct PlannedEventsListView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
    @State private var events: [ConcertEvent] = []

    var body: some View {
        List(events) { event in
            NavigationLink {
                EventDetailView(event: event, repository: eventRepository, contentRepository: contentRepository)
            } label: {
                FavoriteEventRow(event: event)
            }
        }
        .overlay { if events.isEmpty { ContentUnavailableView("Noch nichts geplant", systemImage: "calendar.badge.checkmark", description: Text("Als \"Geplant\" markierte Veranstaltungen erscheinen hier.")) } }
        .navigationTitle("Geplant")
        .task {
            guard let repository, let id = auth.userID, let token = auth.accessToken else { return }
            let loaded = (try? await repository.plannedEvents(userID: id, token: token)) ?? []
            events = (try? await eventRepository.enrichingImages(in: loaded)) ?? loaded
        }
    }
}

struct FavoriteEventRow: View {
    let event: ConcertEvent
    // Einheitliche Konzertzeile (02.11.2026).
    var body: some View { ConcertRow(event: event, horizontalPadding: 0) }
}

struct UserEventListsView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository

    @State private var lists: [UserEventList] = []
    @State private var showsCreate = false
    @State private var showsPlusPaywall = false
    @State private var newName = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if auth.userID == nil {
                ContentUnavailableView(
                    "Anmeldung erforderlich",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("Melde dich im Profil an, um persönliche Konzertlisten zu erstellen und zu synchronisieren.")
                )
            } else if isLoading {
                ProgressView("Listen werden geladen …")
            } else if lists.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Listen", systemImage: "rectangle.stack")
                } description: {
                    Text("Erstelle eine Liste und füge anschließend beliebige kommende Konzerte hinzu.")
                } actions: {
                    Button("Neue Liste") { showsCreate = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(lists) { list in
                        NavigationLink {
                            UserEventListDetailView(
                                initialList: list,
                                auth: auth,
                                repository: repository,
                                eventRepository: eventRepository,
                                contentRepository: contentRepository
                            )
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: list.isOwned ? "music.note.list" : "person.2.fill")
                                    .font(.title3)
                                    .foregroundStyle(KlangradarTheme.accent)
                                    .frame(width: 44, height: 44)
                                    .background(KlangradarTheme.accent.opacity(0.1), in: .rect(cornerRadius: 13))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(list.name).font(.headline)
                                    Text("\(list.events.count) \(list.events.count == 1 ? "Konzert" : "Konzerte")\(list.isOwned ? "" : " · mit dir geteilt")")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Meine Listen")
        .sheet(isPresented: $showsPlusPaywall) {
            PlusPaywallView(feature: .lists)
        }
        .toolbar {
            if auth.userID != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Neue Liste", systemImage: "plus") {
                        if PlusStore.shared.enforcesLimits && lists.filter(\.isOwned).count >= PlusLimits.freeLists { showsPlusPaywall = true } else { showsCreate = true }
                    }
                }
            }
        }
        .alert("Neue Konzertliste", isPresented: $showsCreate) {
            TextField("Name der Liste", text: $newName)
            Button("Abbrechen", role: .cancel) { newName = "" }
            Button("Erstellen") { Task { await create() } }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Du kannst den Namen später jederzeit ändern.")
        }
        .alert("Listen konnten nicht aktualisiert werden", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "Unbekannter Fehler") }
        .task { await load() }
        .onAppear { if !isLoading { Task { await load() } } }
    }

    private func load() async {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else {
            isLoading = false
            return
        }
        do {
            lists = try await repository.eventLists(userID: userID, token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func create() async {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        do {
            if let list = try await repository.createEventList(name: newName, userID: userID, token: token) {
                lists.insert(list, at: 0)
                Haptics.confirm()
            }
            newName = ""
        } catch { errorMessage = error.localizedDescription }
    }

    private func delete(at offsets: IndexSet) {
        guard let repository, let token = auth.accessToken else { return }
        let deleted = offsets.map { lists[$0] }
        lists.remove(atOffsets: offsets)
        Task {
            do {
                for list in deleted {
                    if list.isOwned {
                        try await repository.deleteEventList(id: list.id, token: token)
                    } else if let userID = auth.userID {
                        // Geteilte Liste: nur selbst austreten.
                        try await repository.removeListMember(list.id, userID: userID, token: token)
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
                await load()
            }
        }
    }
}

struct UserEventListDetailView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
    @State private var list: UserEventList
    @State private var showsPicker = false
    @State private var showsRename = false
    @State private var editedName: String
    @State private var showsShare = false
    @State private var shareSelection: Set<UUID> = []
    @State private var members: [SocialPerson] = []

    init(
        initialList: UserEventList,
        auth: AuthStore,
        repository: UserRepository?,
        eventRepository: any EventRepository,
        contentRepository: any ContentRepository
    ) {
        _list = State(initialValue: initialList)
        _editedName = State(initialValue: initialList.name)
        self.auth = auth
        self.repository = repository
        self.eventRepository = eventRepository
        self.contentRepository = contentRepository
    }

    var body: some View {
        Group {
            if list.events.isEmpty {
                ContentUnavailableView {
                    Label("Liste ist leer", systemImage: "music.note.list")
                } description: {
                    Text("Wähle Konzerte aus dem gesamten kommenden Programm aus.")
                } actions: {
                    Button("Konzerte auswählen") { showsPicker = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(list.events) { event in
                        NavigationLink(value: event) { UserListEventRow(event: event) }
                            .swipeActions {
                                Button("Entfernen", role: .destructive) { Task { await remove(event) } }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Konzerte auswählen", systemImage: "plus") { showsPicker = true }
                Menu {
                    if list.isOwned {
                        Button("Mit Freunden teilen", systemImage: "person.2.badge.plus") { showsShare = true }
                        Button("Umbenennen", systemImage: "pencil") {
                            editedName = list.name
                            showsRename = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(!list.isOwned)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if members.count > 1 {
                HStack(spacing: 10) {
                    AvatarStack(people: members, size: 26)
                    Text("Gemeinsam mit \(AvatarStack.names(members.filter { $0.id != auth.userID }))")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.bar)
            }
        }
        .sheet(isPresented: $showsShare, onDismiss: { Task { await loadMembers() } }) {
            NavigationStack {
                List {
                    Section {
                        FriendPicker(selection: $shareSelection, excluded: Set(members.map(\.id)))
                    } footer: {
                        Text("Geteilte Listen könnt ihr gemeinsam bearbeiten.")
                    }
                }
                .navigationTitle("Liste teilen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { showsShare = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Teilen") { Task { await share() } }.disabled(shareSelection.isEmpty)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .task { await loadMembers() }
        .sheet(isPresented: $showsPicker, onDismiss: { Task { await reload() } }) {
            EventListPicker(
                list: list,
                auth: auth,
                repository: repository,
                eventRepository: eventRepository
            )
        }
        .alert("Liste umbenennen", isPresented: $showsRename) {
            TextField("Name", text: $editedName)
            Button("Abbrechen", role: .cancel) {}
            Button("Sichern") { Task { await rename() } }
                .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func loadMembers() async {
        guard let repository, let token = auth.accessToken else { return }
        members = (try? await repository.listMembers(list.id, token: token)) ?? []
    }

    private func share() async {
        guard let repository, let token = auth.accessToken else { return }
        try? await repository.shareList(list.id, with: Array(shareSelection), token: token)
        Haptics.confirm()
        shareSelection = []
        showsShare = false
        await loadMembers()
    }

    private func reload() async {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        if let updated = try? await repository.eventLists(userID: userID, token: token).first(where: { $0.id == list.id }) {
            list = updated
            editedName = updated.name
        }
    }

    private func rename() async {
        guard let repository, let token = auth.accessToken else { return }
        try? await repository.renameEventList(id: list.id, name: editedName, token: token)
        await reload()
    }

    private func remove(_ event: ConcertEvent) async {
        guard let repository, let token = auth.accessToken else { return }
        let previous = Set(list.events.map(\.id))
        try? await repository.replaceEvents(in: list.id, selected: previous.subtracting([event.id]), previous: previous, token: token)
        Haptics.soft()
        await reload()
    }
}

struct EventListPicker: View {
    let list: UserEventList
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let eventRepository: any EventRepository
    @Environment(\.dismiss) private var dismiss
    @State private var events: [ConcertEvent] = []
    @State private var selected: Set<UUID>
    @State private var searchText = ""
    @State private var isSaving = false

    init(list: UserEventList, auth: AuthStore, repository: UserRepository?, eventRepository: any EventRepository) {
        self.list = list
        self.auth = auth
        self.repository = repository
        self.eventRepository = eventRepository
        _selected = State(initialValue: Set(list.events.map(\.id)))
    }

    private var filtered: [ConcertEvent] {
        searchText.isEmpty ? events : events.filter {
            $0.title.localizedStandardContains(searchText) || $0.venueName.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { event in
                Button { toggle(event.id) } label: {
                    HStack(spacing: 12) {
                        EventArtwork(event: event)
                            .frame(width: 64, height: 54)
                            .clipped()
                            .clipShape(.rect(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                            Text(event.dateLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: selected.contains(event.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(event.id) ? KlangradarTheme.accent : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay { if events.isEmpty { ProgressView("Konzerte werden geladen …") } }
            .navigationTitle("Konzerte auswählen")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Titel oder Ort")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Speichert …" : "Fertig") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .task {
                let loaded = (try? await eventRepository.allUpcomingEvents()) ?? []
                events = (try? await eventRepository.enrichingImages(in: loaded)) ?? loaded
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func save() async {
        guard let repository, let token = auth.accessToken else { return }
        isSaving = true
        let previous = Set(list.events.map(\.id))
        try? await repository.replaceEvents(in: list.id, selected: selected, previous: previous, token: token)
        Haptics.confirm() // Generated by Claude Code — beim finalen Speichern, nicht beim Öffnen des Dialogs
        isSaving = false
        dismiss()
    }
}

struct UserListEventRow: View {
    let event: ConcertEvent
    // Einheitliche Konzertzeile (02.11.2026).
    var body: some View { ConcertRow(event: event, horizontalPadding: 0) }
}


// MARK: - Bausteine der Profil-Übersicht
