// Erstellt von Claude Code (Nutzerwunsch 26.10.2026): Konzerttagebuch –
// Notiz, Bewertung, Fotos, Begleitung, Restaurant und weitere Orte des Abends.
// Fotos liegen im privaten Bucket diary-photos (nur für den Nutzer selbst).
import PhotosUI
import SwiftUI

/// Karte auf der Konzertseite (nur für begonnene Konzerte).
struct DiaryEntryCard: View {
    let event: ConcertEvent
    @State private var entry: DiaryEntry?
    @State private var showsEditor = false

    private var hasStarted: Bool { (event.startDate ?? .distantFuture) <= .now }

    var body: some View {
        Group {
            if hasStarted && SocialStore.shared.isSignedIn {
                Button { showsEditor = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "book.closed.fill").font(.title3).foregroundStyle(KlangradarTheme.accent)
                            .frame(width: 44, height: 44)
                            .background(KlangradarTheme.accent.opacity(0.1), in: .rect(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry?.isEmpty == false ? "Dein Tagebucheintrag" : "Ins Konzerttagebuch").font(.headline)
                            Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: entry?.isEmpty == false ? "pencil" : "plus").font(.subheadline.weight(.semibold)).foregroundStyle(KlangradarTheme.accent)
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showsEditor) {
                    NavigationStack { DiaryEditorView(event: event) { entry = $0 } }
                }
            }
        }
        .task(id: event.id) { if hasStarted { entry = await PlannerAPI.diaryEntry(eventID: event.id) } }
    }

    private var summary: String {
        guard let entry, !entry.isEmpty else { return "Notiz, Fotos, mit wem du dort warst und wo ihr gegessen habt." }
        let parts = [entry.note.isEmpty ? nil : entry.note,
                     entry.restaurant.isEmpty ? nil : "Essen: \(entry.restaurant)",
                     entry.photoPaths.isEmpty ? nil : "\(entry.photoPaths.count) Foto\(entry.photoPaths.count == 1 ? "" : "s")"]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

struct DiaryEditorView: View {
    let event: ConcertEvent
    var onSave: (DiaryEntry) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var entry = DiaryEntry()
    @State private var stars = 0
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photoURLs: [String: URL] = [:]
    @State private var isSaving = false
    @State private var isUploading = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(.headline)
                    Text(event.dateLine).font(.caption).foregroundStyle(.secondary)
                }
                StarRating(stars: $stars)
            } footer: { Text("Deine Bewertung sehen nur deine Freunde, das Tagebuch nur du.") }

            Section("Notiz") {
                TextField("Was ist dir in Erinnerung geblieben?", text: $entry.note, axis: .vertical).lineLimit(4...12)
            }
            Section("Der Abend") {
                Label { TextField("Mit wem warst du dort?", text: $entry.companions) } icon: { Image(systemName: "person.2") }
                Label { TextField("Wo habt ihr gegessen?", text: $entry.restaurant) } icon: { Image(systemName: "fork.knife") }
                Label { TextField("Wo wart ihr sonst noch? (Bar, Spaziergang …)", text: $entry.otherPlaces, axis: .vertical) } icon: { Image(systemName: "mappin.and.ellipse") }
            }
            Section("Fotos") {
                if !entry.photoPaths.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(entry.photoPaths, id: \.self) { path in
                                ZStack(alignment: .topTrailing) {
                                    CachedAsyncImage(url: photoURLs[path]) { phase in
                                        if let image = phase.image { image.resizable().scaledToFill() } else { Color.secondary.opacity(0.15) }
                                    }
                                    .frame(width: 96, height: 96).clipShape(.rect(cornerRadius: 12))
                                    Button { remove(path) } label: {
                                        Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .padding(4)
                                    .accessibilityLabel("Foto entfernen")
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                PhotosPicker(selection: $photoItems, maxSelectionCount: 6, matching: .images) {
                    Label(isUploading ? "Wird hochgeladen …" : "Fotos hinzufügen", systemImage: "photo.badge.plus")
                }
                .disabled(isUploading || entry.photoPaths.count >= 12)
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle("Konzerttagebuch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Sichern …" : "Sichern") { Task { await save() } }.disabled(isSaving || isUploading)
            }
        }
        .task { await load() }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await upload(items) }
        }
    }

    private func load() async {
        if let existing = await PlannerAPI.diaryEntry(eventID: event.id) { entry = existing }
        if let repository = SocialStore.shared.repository, let token = SocialStore.shared.token,
           let ratings = try? await repository.eventRatings(event.id, token: token) {
            stars = ratings.mine?.stars ?? 0
        }
        await resolvePhotoURLs()
    }

    private func resolvePhotoURLs() async {
        for path in entry.photoPaths where photoURLs[path] == nil {
            photoURLs[path] = await PlannerAPI.signedPhotoURL(path)
        }
    }

    private func upload(_ items: [PhotosPickerItem]) async {
        isUploading = true
        defer { isUploading = false; photoItems = [] }
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = image.preparingThumbnail(of: fittedSize(image.size, maxSide: 2000))?.jpegData(compressionQuality: 0.82) ?? image.jpegData(compressionQuality: 0.82) else { continue }
            do {
                if let path = try await PlannerAPI.uploadDiaryPhoto(jpeg, eventID: event.id) { entry.photoPaths.append(path) }
            } catch { errorMessage = "Foto konnte nicht hochgeladen werden." }
        }
        await resolvePhotoURLs()
    }

    private func fittedSize(_ size: CGSize, maxSide: CGFloat) -> CGSize {
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func remove(_ path: String) {
        entry.photoPaths.removeAll { $0 == path }
        Task { await PlannerAPI.deleteDiaryPhoto(path) }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await PlannerAPI.saveDiary(entry, eventID: event.id)
            if stars > 0, let repository = SocialStore.shared.repository, let token = SocialStore.shared.token {
                try? await repository.rateEvent(event.id, stars: stars, comment: nil, token: token)
            }
            Haptics.confirm()
            onSave(entry)
            dismiss()
        } catch {
            errorMessage = "Eintrag konnte nicht gesichert werden. Bitte versuche es erneut."
        }
    }
}

/// Alle Tagebucheinträge, neueste zuerst (aus Mein Klangradar).
struct ConcertDiaryListView: View {
    @State private var items: [(event: ConcertEvent, entry: DiaryEntry)] = []
    @State private var isLoading = true
    @State private var editing: ConcertEvent?
    @State private var covers: [UUID: URL] = [:]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if items.isEmpty {
                    ContentUnavailableView("Noch keine Einträge", systemImage: "book.closed",
                                           description: Text("Nach einem Konzert kannst du auf der Konzertseite Notizen, Fotos und den Abend festhalten."))
                }
                ForEach(items, id: \.event.id) { item in
                    Button { editing = item.event } label: { card(item.event, item.entry) }.buttonStyle(.plain)
                }
            }
            .padding(KlangradarTheme.pagePadding)
        }
        .background { KlangradarBackground().ignoresSafeArea() }
        .navigationTitle("Konzerttagebuch")
        .task { await load() }
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { event in
            NavigationStack { DiaryEditorView(event: event) }
        }
    }

    private func card(_ event: ConcertEvent, _ entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let cover = covers[event.id] {
                CachedAsyncImage(url: cover) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { Color.secondary.opacity(0.12) }
                }
                .frame(height: 160).frame(maxWidth: .infinity).clipped()
                .clipShape(.rect(cornerRadius: 16))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(event.startDate.map { $0.formatted(.dateTime.day().month(.wide).year()) } ?? "").font(.caption.weight(.semibold)).foregroundStyle(KlangradarTheme.accent)
                Text(event.title).font(.headline).lineLimit(2)
            }
            if !entry.note.isEmpty { Text(entry.note).font(.subheadline).lineLimit(4) }
            let facts = [entry.companions.isEmpty ? nil : ("person.2", entry.companions),
                         entry.restaurant.isEmpty ? nil : ("fork.knife", entry.restaurant),
                         entry.otherPlaces.isEmpty ? nil : ("mappin.and.ellipse", entry.otherPlaces)].compactMap { $0 }
            ForEach(facts, id: \.1) { fact in
                Label(fact.1, systemImage: fact.0).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground).opacity(0.9), in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func load() async {
        defer { isLoading = false }
        let entries = await PlannerAPI.diaryEntries()
        let events = Dictionary(await PlannerAPI.events(ids: entries.map(\.eventID)).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        items = entries.compactMap { pair in events[pair.eventID].map { ($0, pair.entry) } }
        for item in items where covers[item.event.id] == nil {
            if let first = item.entry.photoPaths.first { covers[item.event.id] = await PlannerAPI.signedPhotoURL(first) }
        }
    }
}
