import SwiftUI

struct SearchView: View {
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
    @EnvironmentObject private var genreFilter: GenreFilterRouter
    @State private var query = ""
    @State private var events: [ConcertEvent] = []
    @State private var hits: [SearchHit] = []
    @State private var directories: [EntityKind: [DirectoryItem]] = [:]
    @State private var errorMessage: String?
    @State private var activeGenre: GenreFilterRouter.Genre?
    @State private var genreEvents: [ConcertEvent] = []
    @State private var isLoadingGenreEvents = false

    var body: some View {
        NavigationStack {
            List {
                if let activeGenre, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    genreFilterSection(activeGenre)
                } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section("Entdecken") {
                        ForEach(EntityKind.allCases, id: \.self) { kind in
                            NavigationLink(value: kind) {
                                Label(kind.title, systemImage: kind.systemImage)
                            }
                            .badge(directories[kind]?.count ?? 0)
                        }
                    }
                    Section("Nächste Konzerte") { eventRows(events) }
                } else if hits.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    Section("Ergebnisse") {
                        ForEach(hits) { hit in
                            if let kind = hit.kind {
                                let item = directoryItem(for: hit, kind: kind)
                                NavigationLink(value: EntityRoute(kind: kind, identifier: hit.slug ?? hit.id)) {
                                    SearchEntityRow(
                                        kind: kind,
                                        title: kind == .work ? hit.title.cleanedWorkTitle : hit.title,
                                        subtitle: item?.subtitle ?? hit.subtitle,
                                        imageURL: item?.imageURL,
                                        avatarCrop: item?.avatarCrop
                                    )
                                }
                            } else if let event = events.first(where: { $0.id.uuidString == hit.id || $0.slug == hit.slug }) {
                                NavigationLink(value: event) { SearchEventRow(event: event) }
                            } else {
                                resultLabel(title: hit.title, subtitle: hit.subtitle, image: "magnifyingglass")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Suche")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Konzerte, Personen, Ensembles, Orte, Werke")
            .navigationDestination(for: ConcertEvent.self) { EventDetailView(event: $0, repository: eventRepository, contentRepository: contentRepository) }
            .navigationDestination(for: EntityKind.self) { DirectoryView(kind: $0, repository: contentRepository) }
            .navigationDestination(for: EntityRoute.self) { EntityDetailView(route: $0, repository: contentRepository) }
            .task { await load() }
            .task(id: query) { await search() }
            // TabView baut den Suche-Tab erst beim ersten Betreten auf — wird
            // genau dieser Tab-Wechsel durch einen Genre-Chip-Tap ausgelöst,
            // existiert SearchView beim Setzen von genreFilter.pending noch
            // nicht, .onChange greift dann nicht (kein "Wechsel" seit dem
            // Erscheinen des Modifiers). .onAppear fängt diesen Fall zusätzlich ab.
            .onChange(of: genreFilter.pending) { _, _ in applyPendingGenreFilter() }
            .onAppear { applyPendingGenreFilter() }
            .overlay { if let errorMessage, events.isEmpty { ContentUnavailableView("Suche nicht verfügbar", systemImage: "wifi.exclamationmark", description: Text(errorMessage)) } }
        }
    }

    @ViewBuilder private func genreFilterSection(_ genre: GenreFilterRouter.Genre) -> some View {
        Section {
            HStack {
                Label(genre.label, systemImage: "music.quarternote.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KlangradarTheme.accent)
                Spacer()
                Button("Filter entfernen") { activeGenre = nil; genreEvents = [] }
                    .font(.caption)
            }
        }
        Section("Veranstaltungen · \(genre.label)") {
            if isLoadingGenreEvents {
                ProgressView().frame(maxWidth: .infinity)
            } else if genreEvents.isEmpty {
                Text("Keine kommenden Veranstaltungen mit diesem Tag gefunden.")
                    .foregroundStyle(.secondary)
            } else {
                eventRows(genreEvents)
            }
        }
    }

    private func applyPendingGenreFilter() {
        guard let genre = genreFilter.consume() else { return }
        query = ""
        activeGenre = genre
        Task { await loadGenreEvents(genre.id) }
    }

    @MainActor private func loadGenreEvents(_ genreID: UUID) async {
        isLoadingGenreEvents = true
        defer { isLoadingGenreEvents = false }
        genreEvents = (try? await eventRepository.events(genreID: genreID, limit: 60)) ?? []
    }

    @ViewBuilder private func eventRows(_ values: [ConcertEvent]) -> some View {
        ForEach(values) { event in
            NavigationLink(value: event) { SearchEventRow(event: event) }
        }
    }

    private func resultLabel(title: String, subtitle: String?, image: String) -> some View {
        Label { VStack(alignment: .leading) { Text(title); if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) } } } icon: { Image(systemName: image).frame(width: 30) }
    }

    private func directoryItem(for hit: SearchHit, kind: EntityKind) -> DirectoryItem? {
        directories[kind]?.first {
            $0.id == hit.id || ($0.slug != nil && $0.slug == hit.slug)
        }
    }

    private func load() async {
        do {
            async let loadedEvents = eventRepository.allUpcomingEvents()
            var loadedDirectories: [EntityKind: [DirectoryItem]] = [:]
            for kind in EntityKind.allCases { loadedDirectories[kind] = try await contentRepository.directory(kind: kind) }
            let basicEvents = try await loadedEvents
            events = basicEvents
            if let enriched = try? await eventRepository.enrichingImages(in: basicEvents) {
                events = enriched
            }
            directories = loadedDirectories
        } catch { errorMessage = error.localizedDescription }
    }

    private func search() async {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { hits = []; return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        do { hits = try await contentRepository.search(query: value, limit: 40) }
        catch {
            hits = directories.values.flatMap { $0 }.filter { $0.title.localizedStandardContains(value) }.map { SearchHit(id: $0.id, kind: $0.kind, slug: $0.slug, title: $0.title, subtitle: $0.subtitle) }
        }
    }
}

private struct SearchEntityRow: View {
    let kind: EntityKind
    let title: String
    let subtitle: String?
    let imageURL: URL?
    var avatarCrop: CropRect? = nil

    var body: some View {
        HStack(spacing: 12) {
            if kind == .work {
                Image(systemName: kind.systemImage)
                    .foregroundStyle(KlangradarTheme.accent)
                    .frame(width: 54, height: 54)
            } else {
                CroppedAsyncImage(url: imageURL, crop: avatarCrop) {
                    thumbnailShape
                        .fill(.quaternary)
                        .overlay {
                            if kind == .person || kind == .ensemble {
                                Text(initials).font(.caption.bold()).foregroundStyle(KlangradarTheme.accent)
                            } else {
                                Image(systemName: kind.systemImage).foregroundStyle(KlangradarTheme.accent)
                            }
                        }
                }
                .frame(width: 54, height: 54)
                .clipShape(thumbnailShape)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var thumbnailShape: AnyShape {
        kind == .person || kind == .ensemble
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }


    private var initials: String {
        title.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

private struct SearchEventRow: View {
    let event: ConcertEvent

    var body: some View {
        HStack(spacing: 12) {
            EventArtwork(event: event)
                .frame(width: 54, height: 54)
                .clipped()
                .clipShape(.rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.headline).lineLimit(2)
                Text(event.dateLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

struct DirectoryView: View {
    let kind: EntityKind
    let repository: any ContentRepository
    @State private var items: [DirectoryItem] = []

    private var sections: [DirectorySection] {
        let grouped = Dictionary(grouping: items) { DirectorySection.indexTitle(for: $0.title) }
        return DirectorySection.indexTitles.compactMap { title in
            guard let values = grouped[title], !values.isEmpty else { return nil }
            return DirectorySection(
                title: title,
                items: values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            )
        }
    }

    // Nutzeranfrage: "Werke sollen nach Komponist sortiert werden. Dabei
    // soll jeder Komponist alphabetisch sortiert werden und wie in der
    // Liste der Personen ein Miniaturbild erhalten." — Werke gruppieren sich
    // deshalb nicht wie die übrigen Directory-Kinds nach dem eigenen Titel,
    // sondern nach Komponist; die A-Z-Schnellsprungleiste bleibt dasselbe
    // Muster, springt jetzt aber zu Komponisten-Anfangsbuchstaben.
    private var composerSections: [ComposerSection] {
        let groupedByComposer = Dictionary(grouping: items) { $0.composer?.id ?? "unbekannt" }
        let composerGroups = groupedByComposer.map { _, works -> ComposerGroup in
            let composer = works.first?.composer
            return ComposerGroup(
                id: composer?.id ?? "unbekannt",
                name: composer?.name ?? "Unbekannter Komponist",
                slug: composer?.slug,
                imageURL: composer?.imageURL,
                avatarCrop: composer?.avatarCrop,
                works: works.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let bucketed = Dictionary(grouping: composerGroups) { DirectorySection.indexTitle(for: $0.name) }
        return DirectorySection.indexTitles.compactMap { letter in
            guard let groups = bucketed[letter], !groups.isEmpty else { return nil }
            return ComposerSection(title: letter, groups: groups)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if kind == .work {
                    ForEach(composerSections) { section in
                        Section {
                            ForEach(section.groups) { group in
                                composerHeaderRow(group)
                                ForEach(group.works) { work in
                                    workRow(work, composerName: group.name)
                                }
                            }
                        } header: {
                            Text(section.title)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .id(section.title)
                        }
                    }
                } else {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.items) { item in
                                directoryRow(item)
                            }
                        } header: {
                            Text(section.title)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .id(section.title)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .contentMargins(.trailing, 18, for: .scrollContent)
            .overlay(alignment: .trailing) {
                AlphabetIndexRail(
                    availableTitles: Set((kind == .work ? composerSections.map(\.title) : sections.map(\.title))),
                    onSelect: { requested in
                        let available = kind == .work ? composerSections.map(\.title) : sections.map(\.title)
                        guard let target = sectionTarget(for: requested, available: available) else { return }
                        withAnimation(.snappy(duration: 0.2)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                    }
                )
                .padding(.trailing, 2)
                .padding(.vertical, 10)
            }
        }
        .navigationTitle(kind.title)
        .task { items = (try? await repository.directory(kind: kind)) ?? [] }
    }

    @ViewBuilder
    private func composerHeaderRow(_ group: ComposerGroup) -> some View {
        let label = HStack(spacing: 12) {
            CroppedAsyncImage(url: group.imageURL, crop: group.avatarCrop) {
                Color.secondary.opacity(0.12).overlay { Image(systemName: "person") }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            Text(group.name).font(.headline)
            Spacer(minLength: 0)
        }
        if let slug = group.slug {
            NavigationLink(value: EntityRoute(kind: .person, identifier: slug)) { label }
        } else {
            label
        }
    }

    /// Werk-Zeile innerhalb einer Komponisten-Gruppe — die Komponist-Angabe
    /// steht bereits im Gruppen-Header (composerHeaderRow), wird deshalb aus
    /// dem sonst geteilten item.subtitle (Komponist · Opus · Tonart · Jahr ·
    /// Dauer, siehe ContentRepository.subtitle) entfernt, um sie nicht doppelt
    /// zu zeigen.
    @ViewBuilder
    private func workRow(_ item: DirectoryItem, composerName: String) -> some View {
        NavigationLink(value: EntityRoute(kind: kind, identifier: item.slug ?? item.id)) {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title.cleanedWorkTitle).font(.headline).fixedSize(horizontal: false, vertical: true)
                if let detail = workDetailLine(item.subtitle, composerName: composerName) {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(.vertical, 6)
            .padding(.leading, 56)
        }
    }

    private func workDetailLine(_ subtitle: String?, composerName: String) -> String? {
        guard var text = subtitle, !text.isEmpty else { return nil }
        if text.hasPrefix(composerName) {
            text.removeFirst(composerName.count)
            if text.hasPrefix(" · ") { text.removeFirst(3) }
        }
        return text.isEmpty ? nil : text
    }

    @ViewBuilder
    private func directoryRow(_ item: DirectoryItem) -> some View {
        NavigationLink(value: EntityRoute(kind: kind, identifier: item.slug ?? item.id)) {
            HStack(spacing: 12) {
                CroppedAsyncImage(url: item.imageURL, crop: item.avatarCrop) {
                    Color.secondary.opacity(0.12).overlay { Image(systemName: kind.systemImage) }
                }
                .frame(width: 54, height: 54)
                .clipShape(kind == .person || kind == .ensemble ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
                VStack(alignment: .leading) {
                    Text(item.title).font(.headline)
                    if let subtitle = item.subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
                }
            }
        }
    }

    private func sectionTarget(for requested: String, available: [String]) -> String? {
        guard !available.isEmpty else { return nil }
        if available.contains(requested) { return requested }
        guard let requestedIndex = DirectorySection.indexTitles.firstIndex(of: requested) else { return available.first }
        return DirectorySection.indexTitles.dropFirst(requestedIndex + 1).first(where: available.contains)
            ?? DirectorySection.indexTitles.prefix(requestedIndex).reversed().first(where: available.contains)
            ?? available.first
    }
}

private struct ComposerGroup: Identifiable {
    let id: String
    let name: String
    let slug: String?
    let imageURL: URL?
    let avatarCrop: CropRect?
    let works: [DirectoryItem]
}

private struct ComposerSection: Identifiable {
    let title: String
    let groups: [ComposerGroup]
    var id: String { title }
}

private struct DirectorySection: Identifiable {
    static let indexTitles = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init) + ["#"]

    let title: String
    let items: [DirectoryItem]
    var id: String { title }

    static func indexTitle(for value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
        guard let first = folded.first else { return "#" }
        let candidate = String(first).uppercased()
        return indexTitles.contains(candidate) ? candidate : "#"
    }
}

private struct AlphabetIndexRail: View {
    let availableTitles: Set<String>
    let onSelect: (String) -> Void
    @State private var lastSelection: String?

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ForEach(DirectorySection.indexTitles, id: \.self) { title in
                    Text(title)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(availableTitles.contains(title) ? KlangradarTheme.accent : Color.secondary.opacity(0.35))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let height = max(proxy.size.height, 1)
                        let progress = min(max(value.location.y / height, 0), 0.999)
                        let index = min(Int(progress * CGFloat(DirectorySection.indexTitles.count)), DirectorySection.indexTitles.count - 1)
                        let title = DirectorySection.indexTitles[index]
                        guard title != lastSelection else { return }
                        lastSelection = title
                        onSelect(title)
                    }
                    .onEnded { _ in lastSelection = nil }
            )
        }
        .frame(width: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Alphabetische Navigation")
        .accessibilityHint("Über die Buchstaben streichen, um in der Liste zu springen")
    }
}
