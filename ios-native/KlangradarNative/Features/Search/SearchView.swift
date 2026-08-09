import SwiftUI

struct SearchView: View {
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
    @State private var query = ""
    @State private var events: [ConcertEvent] = []
    @State private var hits: [SearchHit] = []
    @State private var directories: [EntityKind: [DirectoryItem]] = [:]
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            .overlay { if let errorMessage, events.isEmpty { ContentUnavailableView("Suche nicht verfügbar", systemImage: "wifi.exclamationmark", description: Text(errorMessage)) } }
        }
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

    var body: some View {
        ScrollViewReader { proxy in
            List {
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
            .listStyle(.plain)
            .contentMargins(.trailing, 18, for: .scrollContent)
            .overlay(alignment: .trailing) {
                AlphabetIndexRail(
                    availableTitles: Set(sections.map(\.title)),
                    onSelect: { requested in
                        guard let target = sectionTarget(for: requested) else { return }
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
    private func directoryRow(_ item: DirectoryItem) -> some View {
        NavigationLink(value: EntityRoute(kind: kind, identifier: item.slug ?? item.id)) {
            if kind == .work {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title.cleanedWorkTitle).font(.headline).fixedSize(horizontal: false, vertical: true)
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .padding(.vertical, 6)
            } else {
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
    }

    private func sectionTarget(for requested: String) -> String? {
        let available = sections.map(\.title)
        guard !available.isEmpty else { return nil }
        if available.contains(requested) { return requested }
        guard let requestedIndex = DirectorySection.indexTitles.firstIndex(of: requested) else { return available.first }
        return DirectorySection.indexTitles.dropFirst(requestedIndex + 1).first(where: available.contains)
            ?? DirectorySection.indexTitles.prefix(requestedIndex).reversed().first(where: available.contains)
            ?? available.first
    }
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
