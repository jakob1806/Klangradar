// Erstellt von Claude Code (Nutzerwunsch 26.10.2026): Konzert eintragen, das
// nicht in Klangradar steht – angelehnt an Apple Journal: großes Bild oben,
// ruhige Karten, Serifen-Titel, alles optional bis auf das Datum.
import PhotosUI
import SwiftUI

struct ConcertJournalEditor: View {
    var existing: ConcertJournalEntry? = nil
    var onSave: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var entry = ConcertJournalEntry()
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photoURLs: [String: URL] = [:]
    @State private var picker: EntityKind?
    @State private var isSaving = false
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var showsDuration = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                photoHeader
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.startsAt.formatted(.dateTime.weekday(.wide).day().month(.wide).year()).uppercased())
                        .font(.caption.weight(.semibold)).tracking(1).foregroundStyle(KlangradarTheme.accent)
                    TextField("Titel des Abends", text: $entry.title, axis: .vertical)
                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                        .lineLimit(1...3)
                }

                card {
                    HStack(spacing: 12) {
                        icon("calendar")
                        DatePicker("Wann", selection: $entry.startsAt, in: ...Date.now.addingTimeInterval(365 * 86_400))
                            .datePickerStyle(.compact)
                    }
                    Divider().padding(.leading, 44)
                    Button { showsDuration.toggle() } label: {
                        row(icon: "hourglass", title: "Dauer", value: entry.durationMinutes.map { "\($0) Min." } ?? "Hinzufügen")
                    }
                    .buttonStyle(.plain)
                    if showsDuration {
                        Stepper(value: Binding(get: { entry.durationMinutes ?? 120 }, set: { entry.durationMinutes = $0 }), in: 10...480, step: 5) {
                            Text("\(entry.durationMinutes ?? 120) Minuten").font(.subheadline)
                        }
                        .padding(.leading, 44)
                    }
                }

                card {
                    Button { picker = .venue } label: {
                        row(icon: "building.columns", title: "Ort", value: entry.venue?.name ?? "Konzertort wählen", detail: entry.venue?.detail)
                    }
                    .buttonStyle(.plain)
                }

                section("Programm", add: { picker = .work }) {
                    ForEach(entry.program) { work in
                        chipRow(icon: "music.note", title: work.name, detail: work.detail) { entry.program.removeAll { $0.id == work.id } }
                    }
                }

                section("Mitwirkende", add: { picker = .person }) {
                    ForEach(entry.participants) { person in
                        chipRow(icon: person.kind == .ensemble ? "person.3" : "person", title: person.name, detail: person.role ?? person.detail, photo: person.photoURL) {
                            entry.participants.removeAll { $0.id == person.id }
                        }
                    }
                    Button { picker = .ensemble } label: {
                        Label("Ensemble hinzufügen", systemImage: "plus.circle").font(.subheadline.weight(.semibold))
                    }
                    .tint(KlangradarTheme.accent)
                    .padding(.top, 2)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Gedanken").font(.headline)
                    TextField("Was hat dich an diesem Abend bewegt?", text: $entry.note, axis: .vertical)
                        .font(.system(.body, design: .serif))
                        .lineLimit(5...20)
                        .padding(16)
                        .background(Color(uiColor: .systemBackground).opacity(0.9), in: .rect(cornerRadius: 20, style: .continuous))
                }

                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            }
            .padding(KlangradarTheme.pagePadding)
        }
        .background { journalBackground.ignoresSafeArea() }
        .navigationTitle(existing == nil ? "Neuer Eintrag" : "Eintrag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Sichern …" : "Fertig") { Task { await save() } }
                    .fontWeight(.semibold)
                    .disabled(isSaving || isUploading)
            }
        }
        .sheet(item: $picker) { kind in
            NavigationStack {
                JournalEntityPicker(kind: kind, contextHint: kind == .work ? entry.program.last?.detail : nil) { pick in
                    switch pick.kind {
                    case .venue: entry.venue = pick
                    case .work: if !entry.program.contains(pick) { entry.program.append(pick) }
                    default: if !entry.participants.contains(pick) { entry.participants.append(pick) }
                    }
                }
            }
            .presentationDetents([.large])
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await upload(items) }
        }
        .task {
            if let existing { entry = existing }
            for path in entry.photoPaths where photoURLs[path] == nil { photoURLs[path] = await PlannerAPI.signedPhotoURL(path) }
        }
    }

    private var journalBackground: some View {
        LinearGradient(colors: [Color(red: 0.98, green: 0.96, blue: 0.93), Color(uiColor: .systemGroupedBackground)], startPoint: .top, endPoint: .bottom)
    }

    @ViewBuilder private var photoHeader: some View {
        PhotosPicker(selection: $photoItems, maxSelectionCount: 6, matching: .images) {
            if let first = entry.photoPaths.first, let url = photoURLs[first] {
                ZStack(alignment: .bottomTrailing) {
                    CachedAsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() } else { Color.secondary.opacity(0.1) }
                    }
                    .frame(height: 240).frame(maxWidth: .infinity).clipped()
                    .clipShape(.rect(cornerRadius: 24, style: .continuous))
                    if entry.photoPaths.count > 1 {
                        Text("+\(entry.photoPaths.count - 1)").font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: .capsule).padding(12)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: isUploading ? "arrow.up.circle" : "photo.on.rectangle.angled").font(.system(size: 34, weight: .light))
                    Text(isUploading ? "Wird hochgeladen …" : "Foto vom Abend hinzufügen").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(KlangradarTheme.accent)
                .frame(height: 180).frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [KlangradarTheme.accent.opacity(0.14), Color.orange.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 24, style: .continuous)
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fotos hinzufügen")
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .systemBackground).opacity(0.9), in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func section<Content: View>(_ title: String, add: @escaping () -> Void, @ViewBuilder _ content: () -> Content) -> some View {
        card {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button(action: add) { Image(systemName: "plus").font(.subheadline.weight(.bold)).frame(width: 30, height: 30).background(KlangradarTheme.accent.opacity(0.12), in: .circle) }
                    .tint(KlangradarTheme.accent)
                    .accessibilityLabel("\(title) hinzufügen")
            }
            content()
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name).font(.subheadline.weight(.semibold)).foregroundStyle(KlangradarTheme.accent)
            .frame(width: 32, height: 32).background(KlangradarTheme.accent.opacity(0.1), in: .rect(cornerRadius: 9, style: .continuous))
    }

    private func row(icon name: String, title: String, value: String, detail: String? = nil) -> some View {
        HStack(spacing: 12) {
            icon(name)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.body.weight(.medium)).foregroundStyle(.primary)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }

    private func chipRow(icon name: String, title: String, detail: String?, photo: URL? = nil, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            if let photo {
                CachedAsyncImage(url: photo) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { Color.secondary.opacity(0.12) }
                }
                .frame(width: 32, height: 32).clipShape(.circle)
            } else {
                icon(name)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
            Button(action: onRemove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                .buttonStyle(.plain).accessibilityLabel("\(title) entfernen")
        }
    }

    private func upload(_ items: [PhotosPickerItem]) async {
        isUploading = true
        defer { isUploading = false; photoItems = [] }
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { continue }
            let scale = min(1, 2000 / max(image.size.width, image.size.height, 1))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            guard let jpeg = (image.preparingThumbnail(of: size) ?? image).jpegData(compressionQuality: 0.82) else { continue }
            do {
                if let path = try await JournalAPI.uploadPhoto(jpeg, entryID: entry.id) {
                    entry.photoPaths.append(path)
                    photoURLs[path] = await PlannerAPI.signedPhotoURL(path)
                }
            } catch { errorMessage = "Foto konnte nicht hochgeladen werden." }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await JournalAPI.save(entry)
            Haptics.confirm()
            onSave()
            dismiss()
        } catch {
            errorMessage = "Eintrag konnte nicht gesichert werden. Bitte versuche es erneut."
        }
    }
}

extension EntityKind: Identifiable {
    var id: String { rawValue }
}

/// Suche in den Stammdaten; fehlt etwas, reicht der Name.
struct JournalEntityPicker: View {
    let kind: EntityKind
    var contextHint: String? = nil
    let onPick: (JournalPick) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [JournalPick] = []
    @State private var isSearching = false
    @State private var showsAddForm = false
    @State private var context = ""
    @State private var role = ""
    @State private var isRequesting = false
    @State private var errorMessage: String?

    private var title: String {
        switch kind {
        case .venue: "Konzertort"
        case .work: "Werk"
        case .ensemble: "Ensemble"
        default: "Person"
        }
    }

    private var contextPlaceholder: String? {
        switch kind {
        case .work: "Komponist:in (empfohlen)"
        case .venue: "Stadt (empfohlen)"
        default: nil
        }
    }

    var body: some View {
        List {
            if kind == .person {
                Section {
                    TextField("Rolle, z. B. Dirigent, Violine", text: $role)
                } footer: { Text("Optional – erscheint in deinem Eintrag.") }
            }
            Section {
                ForEach(results) { pick in
                    Button { choose(pick) } label: {
                        HStack(spacing: 12) {
                            CachedAsyncImage(url: pick.photoURL) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() }
                                else { Image(systemName: symbol).foregroundStyle(KlangradarTheme.accent).frame(maxWidth: .infinity, maxHeight: .infinity).background(KlangradarTheme.accent.opacity(0.1)) }
                            }
                            .frame(width: 36, height: 36).clipShape(kind == .person ? AnyShape(.circle) : AnyShape(.rect(cornerRadius: 9)))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(pick.name).foregroundStyle(.primary).lineLimit(2)
                                if let detail = pick.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                if query.trimmingCharacters(in: .whitespaces).count >= 2 && !isSearching {
                    Button { context = contextHint ?? ""; showsAddForm = true } label: {
                        Label("„\(query.trimmingCharacters(in: .whitespaces))“ hinzufügen", systemImage: "plus.circle.fill")
                            .fontWeight(.semibold)
                    }
                    .tint(KlangradarTheme.accent)
                }
            } footer: {
                if query.count >= 2 && results.isEmpty && !isSearching {
                    Text("Nicht dabei? Füge es mit dem Namen hinzu – Klangradar ergänzt Bild, Lebensdaten und Infos automatisch, die Redaktion prüft nach.")
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "\(title) suchen")
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            isSearching = true
            results = await JournalAPI.search(kind, query)
            isSearching = false
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        .alert("\(title) hinzufügen", isPresented: $showsAddForm) {
            if let contextPlaceholder { TextField(contextPlaceholder, text: $context) }
            Button("Abbrechen", role: .cancel) {}
            Button(isRequesting ? "Wird angelegt …" : "Hinzufügen") { Task { await request() } }
        } message: {
            Text("„\(query.trimmingCharacters(in: .whitespaces))“ wird angelegt und automatisch mit Infos ergänzt.")
        }
        .overlay(alignment: .bottom) {
            if let errorMessage {
                Text(errorMessage).font(.footnote).padding(12).background(.regularMaterial, in: .capsule).padding()
            }
        }
    }

    private var symbol: String {
        switch kind {
        case .venue: "building.columns"
        case .work: "music.note"
        case .ensemble: "person.3"
        default: "person"
        }
    }

    private func choose(_ pick: JournalPick) {
        var chosen = pick
        if kind == .person, !role.trimmingCharacters(in: .whitespaces).isEmpty { chosen.role = role.trimmingCharacters(in: .whitespaces) }
        onPick(chosen)
        Haptics.light()
        dismiss()
    }

    private func request() async {
        isRequesting = true
        defer { isRequesting = false }
        do {
            let pick = try await JournalAPI.request(kind, name: query.trimmingCharacters(in: .whitespaces), context: context.trimmingCharacters(in: .whitespaces))
            choose(pick)
        } catch {
            errorMessage = "Konnte nicht angelegt werden. Bitte später erneut versuchen."
        }
    }
}
