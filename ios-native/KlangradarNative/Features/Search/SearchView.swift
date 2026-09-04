import SwiftUI

private extension InspirationCategory {
    var colors: [Color] {
        switch colorKey {
        case "purple": [.purple, .pink]
        case "pink": [.pink, .red]
        case "orange": [.orange, .red]
        case "teal": [.teal, .blue]
        case "blue": [.blue, .indigo]
        case "indigo": [.indigo, .purple]
        default: [KlangradarTheme.accent, .cyan]
        }
    }
}

struct SearchView: View {
    private enum ResultScope: String, CaseIterable, Identifiable {
        case all, event, person, ensemble, venue
        var id: String { rawValue }
        var title: String { switch self { case .all: "Alle"; case .event: "Veranstaltungen"; case .person: "Personen"; case .ensemble: "Ensembles"; case .venue: "Orte" } }
    }
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
    @EnvironmentObject private var genreFilter: GenreFilterRouter
    @EnvironmentObject private var cityStore: CityStore
    @State private var query = ""
    @State private var events: [ConcertEvent] = []
    @State private var hits: [SearchHit] = []
    @State private var directories: [EntityKind: [DirectoryItem]] = [:]
    @State private var errorMessage: String?
    @State private var activeGenre: GenreFilterRouter.Genre?
    @State private var genreEvents: [ConcertEvent] = []
    @State private var isLoadingGenreEvents = false
    @State private var activeInspiration: InspirationCategory?
    @State private var inspirationEvents: [ConcertEvent] = []
    @State private var isLoadingInspiration = false
    @State private var inspirationCategories: [InspirationCategory] = InspirationCategory.fallback
    @State private var resultScope: ResultScope = .all
    @State private var genreResultCache: [UUID: [ConcertEvent]] = [:]
    @State private var inspirationResultCache: [String: [ConcertEvent]] = [:]
    @State private var activeLoadID = UUID()
    @StateObject private var speechSearch = SpeechSearchController()
    @FocusState private var searchFocused: Bool

    private var visibleHits: [SearchHit] {
        guard resultScope != .all else { return hits }
        if resultScope == .event { return hits.filter { $0.kind == nil } }
        return hits.filter { $0.kind?.rawValue == resultScope.rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KlangradarBackground().ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        searchBar
                        searchContent
                    }
                    .padding(.horizontal, KlangradarTheme.pagePadding)
                    .padding(.bottom, 132)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            // Nutzerwunsch: "Suche" soll wie "Klangradar" auf Home links
            // stehen statt (UIKit-Standard bei .inline) zentriert — deshalb
            // ein eigener .topBarLeading-Titel statt .navigationTitle.
            // .sharedBackgroundVisibility(.hidden) unterdrückt die
            // automatische Liquid-Glass-Kapsel, die iOS 26 sonst um
            // .topBarLeading-Inhalte zeichnet (siehe gleiche Lösung in
            // HomeView).
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .modifier(HiddenScrollEdgeNavigationBar())
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) {
                        Text("Suche").font(.headline.bold()).fixedSize()
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        Text("Suche").font(.headline.bold()).fixedSize()
                    }
                }
                // Nutzerfeedback: Ohne dieses Ausblenden spannt sich das
                // automatische Liquid-Glass des Toolbars auf iOS 26 über die
                // GANZE Zeile (inklusive Titel links) statt nur um diesen
                // Chip — CityCompactMenu bringt bereits sein eigenes,
                // geschlossenes Glas mit (siehe CitySwitcherView.chipLabel).
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        CityCompactMenu(cityStore: cityStore)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        CityCompactMenu(cityStore: cityStore)
                    }
                }
            }
            .navigationDestination(for: ConcertEvent.self) { EventDetailView(event: $0, repository: eventRepository, contentRepository: contentRepository) }
            .navigationDestination(for: EntityKind.self) { DirectoryView(kind: $0, repository: contentRepository) }
            .navigationDestination(for: EntityRoute.self) { EntityDetailView(route: $0, repository: contentRepository) }
            .task { await loadEventsAndCategories() }
            .onChange(of: cityStore.selectedCity) { _, _ in
                Task { await loadEventsAndCategories() }
            }
            .task { await loadDirectory(.person) }
            .task { await loadDirectory(.ensemble) }
            .task { await loadDirectory(.venue) }
            .task { await loadDirectory(.work) }
            .task(id: query) { await search() }
            .onDisappear { speechSearch.stop() }
            // TabView baut den Suche-Tab erst beim ersten Betreten auf — wird
            // genau dieser Tab-Wechsel durch einen Genre-Chip-Tap ausgelöst,
            // existiert SearchView beim Setzen von genreFilter.pending noch
            // nicht, .onChange greift dann nicht (kein "Wechsel" seit dem
            // Erscheinen des Modifiers). .onAppear fängt diesen Fall zusätzlich ab.
            .onChange(of: genreFilter.pending) { _, _ in applyPendingGenreFilter() }
            .onAppear { applyPendingGenreFilter() }
            .overlay { if let errorMessage, events.isEmpty { ContentUnavailableView("Suche nicht verfügbar", systemImage: "wifi.exclamationmark", description: Text(errorMessage)) } }
            .alert("Sprachsuche", isPresented: Binding(get: { speechSearch.errorMessage != nil }, set: { if !$0 { speechSearch.dismissError() } })) {
                Button("OK") { speechSearch.dismissError() }
            } message: { Text(speechSearch.errorMessage ?? "") }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Konzerte, Personen, Ensembles, Orte, Werke", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .accessibilityLabel("Suche löschen")
            }
            Button {
                searchFocused = false
                Task { await speechSearch.toggle(into: $query) }
            } label: {
                Image(systemName: speechSearch.isRecording ? "waveform.circle.fill" : "mic.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(speechSearch.isRecording ? .red : KlangradarTheme.accent)
                    .frame(width: 30, height: 30)
                    .background((speechSearch.isRecording ? Color.red : KlangradarTheme.accent).opacity(0.11), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(speechSearch.isRecording ? "Sprachsuche beenden" : "Sprachsuche starten")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        // Vorher .regularMaterial (durchscheinend) — das native .searchable()
        // hatte vor der Mikrofon-Erweiterung ein blickdichtes, helles Feld
        // (systemGray6, kein Rand). Gleiche Optik jetzt hier nachgebaut, da
        // das Mikrofon ein eigenes HStack statt des nativen Modifiers braucht.
        .background(Color(.systemGray6), in: .rect(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var searchContent: some View {
        if let activeInspiration, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inspirationSection(activeInspiration)
        } else if let activeGenre, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            genreFilterSection(activeGenre)
        } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            discoveryContent
        } else {
            scopePicker
            if visibleHits.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
            } else {
                Text("Ergebnisse")
                    .font(.title2.bold())
                LazyVStack(spacing: 0) {
                    ForEach(visibleHits) { hit in
                        resultRow(hit)
                        if hit.id != visibleHits.last?.id { Divider().padding(.leading, 66) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .background(.regularMaterial, in: .rect(cornerRadius: 24))
            }
        }
    }

    private var discoveryContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Alles entdecken")
                .font(.title2.bold())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(Array(EntityKind.allCases.enumerated()), id: \.element) { index, kind in
                    NavigationLink(value: kind) {
                        DiscoveryTile(
                            kind: kind,
                            featured: featuredItem(for: kind),
                            color: discoveryColors[index % discoveryColors.count]
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if !discoveryEvents.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text("Konzerte entdecken")
                        .font(.title2.bold())
                }
                .padding(.top, 10)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(discoveryEvents) { event in
                            NavigationLink(value: event) {
                                SearchDiscoveryEventCard(event: event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            Text("Lass dich inspirieren")
                .font(.title2.bold())
                .padding(.top, 10)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(inspirationCategories) { category in
                    InspirationTile(title: category.title, symbol: category.symbol ?? "music.note", colors: category.colors) {
                        Task { await loadInspiration(category) }
                    }
                }
            }
        }
    }

    private var discoveryColors: [Color] { [.indigo, .purple, .teal, .orange] }

    /// Kurze, visuelle Auswahl statt einer chronologischen „Nächste
    /// Konzerte“-Liste. Bevorzugt bebilderte Events und vermeidet direkt
    /// nebeneinander dieselbe Spielstätte bzw. dasselbe Genre.
    private var discoveryEvents: [ConcertEvent] {
        let upcoming = events
            .filter { ($0.startDate ?? .distantPast) >= Date() }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        var result: [ConcertEvent] = []
        var venues = Set<String>()
        var genres = Set<String>()

        for event in upcoming where event.primaryImageURL != nil {
            let venue = event.venues?.name ?? ""
            let genre = event.genreLabels.first ?? event.category ?? ""
            guard !venues.contains(venue) || !genres.contains(genre) else { continue }
            result.append(event)
            if !venue.isEmpty { venues.insert(venue) }
            if !genre.isEmpty { genres.insert(genre) }
            if result.count == 8 { break }
        }
        if result.count < 4 {
            for event in upcoming where !result.contains(where: { $0.id == event.id }) {
                result.append(event)
                if result.count == 8 { break }
            }
        }
        return result
    }

    private func featuredItem(for kind: EntityKind) -> DirectoryItem? {
        let preferredTerms: [String] = switch kind {
        case .person: ["Johann Sebastian Bach", "Bach"]
        case .ensemble: ["Symphonieorchester des Bayerischen Rundfunks", "BRSO", "Bayerischen Rundfunks"]
        case .venue: ["Isarphilharmonie"]
        case .work: ["9. Sinfonie", "Matthäus-Passion", "Requiem"]
        }
        let items = directories[kind] ?? []
        for term in preferredTerms {
            if let match = items.first(where: { $0.title.localizedCaseInsensitiveContains(term) }) { return match }
        }
        return items.first(where: { $0.imageURL != nil }) ?? items.first
    }

    private var scopePicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(ResultScope.allCases) { scope in
                Button {
                    withAnimation(.snappy) { resultScope = scope }
                } label: {
                    Text(scope.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .foregroundStyle(resultScope == scope ? Color.white : Color.primary)
                        .background(resultScope == scope ? KlangradarTheme.accent : Color.secondary.opacity(0.12), in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func genreFilterSection(_ genre: GenreFilterRouter.Genre) -> some View {
        filteredEventResults(
            title: "Veranstaltungen · \(genre.label)",
            filterTitle: genre.label,
            symbol: "music.quarternote.3",
            isLoading: isLoadingGenreEvents,
            values: genreEvents,
            emptyMessage: "Keine kommenden Veranstaltungen mit diesem Tag gefunden.",
            close: { activeGenre = nil; genreEvents = [] }
        )
    }

    @ViewBuilder private func inspirationSection(_ category: InspirationCategory) -> some View {
        filteredEventResults(
            title: category.title.replacingOccurrences(of: "\n", with: " "),
            filterTitle: category.title.replacingOccurrences(of: "\n", with: " "),
            symbol: category.symbol ?? "music.note",
            isLoading: isLoadingInspiration,
            values: inspirationEvents,
            emptyMessage: "Keine passenden Termine gefunden.",
            close: { activeInspiration = nil; inspirationEvents = [] }
        )
    }

    @ViewBuilder private func filteredEventResults(
        title: String,
        filterTitle: String,
        symbol: String,
        isLoading: Bool,
        values: [ConcertEvent],
        emptyMessage: String,
        close: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Label(filterTitle, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(KlangradarTheme.accent)
                Spacer(minLength: 8)
                Button("Zurück") { Haptics.light(); close() }
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))

            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isLoading {
                SearchResultsSkeleton()
            } else if values.isEmpty {
                ContentUnavailableView(emptyMessage, systemImage: symbol)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 0) { eventRows(values) }
                    .padding(.horizontal, 14)
                    .background(.regularMaterial, in: .rect(cornerRadius: 24))
            }
        }
    }

    @MainActor private func loadInspiration(_ category: InspirationCategory) async {
        activeGenre = nil
        activeInspiration = category
        if let cached = inspirationResultCache[category.slug] {
            inspirationEvents = cached
            isLoadingInspiration = false
            return
        }
        let loadID = UUID()
        activeLoadID = loadID
        inspirationEvents = []
        isLoadingInspiration = true
        let loaded: [ConcertEvent]
        if let remote = try? await eventRepository.inspirationEvents(attributeSlug: category.slug, limit: 60), !remote.isEmpty {
            loaded = remote
        } else {
            loaded = localInspirationEvents(for: category)
        }
        let final = (try? await eventRepository.enrichingImages(in: loaded)) ?? loaded
        guard activeLoadID == loadID else { return }
        inspirationEvents = final
        inspirationResultCache[category.slug] = final
        isLoadingInspiration = false
    }

    @ViewBuilder private func resultRow(_ hit: SearchHit) -> some View {
        // Generated by Claude Code — kleine Bestätigung beim Öffnen eines
        // Suchtreffers (keine Haptik beim Tippen in die Suchleiste selbst).
        if let kind = hit.kind {
            let item = directoryItem(for: hit, kind: kind)
            NavigationLink(value: EntityRoute(kind: kind, identifier: hit.slug ?? hit.id)) {
                SearchEntityRow(kind: kind, title: kind == .work ? hit.title.cleanedWorkTitle : hit.title, subtitle: item?.subtitle ?? hit.subtitle, imageURL: item?.imageURL, avatarCrop: item?.avatarCrop)
            }
            .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } else if let event = events.first(where: { $0.id.uuidString == hit.id || $0.slug == hit.slug }) {
            NavigationLink(value: event) { SearchEventRow(event: event) }
                .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            resultLabel(title: hit.title, subtitle: hit.subtitle, image: "magnifyingglass")
                .padding(.vertical, 12)
        }
    }

    private func applyPendingGenreFilter() {
        guard let genre = genreFilter.consume() else { return }
        query = ""
        activeGenre = genre
        Task { await loadGenreEvents(genre.id) }
    }

    @MainActor private func loadGenreEvents(_ genreID: UUID) async {
        if let cached = genreResultCache[genreID] {
            genreEvents = cached
            isLoadingGenreEvents = false
            return
        }
        let loadID = UUID()
        activeLoadID = loadID
        genreEvents = []
        isLoadingGenreEvents = true
        var loaded = (try? await eventRepository.events(genreID: genreID, limit: 60)) ?? []
        if let enriched = try? await eventRepository.enrichingImages(in: loaded) { loaded = enriched }
        guard activeLoadID == loadID else { return }
        genreEvents = loaded
        genreResultCache[genreID] = loaded
        isLoadingGenreEvents = false
    }

    @ViewBuilder private func eventRows(_ values: [ConcertEvent]) -> some View {
        ForEach(Array(values.enumerated()), id: \.element.id) { index, event in
            NavigationLink(value: event) { SearchEventRow(event: event) }
                .buttonStyle(.plain)
            if index < values.count - 1 { Divider().padding(.leading, 72) }
        }
    }

    private func resultLabel(title: String, subtitle: String?, image: String) -> some View {
        Label { VStack(alignment: .leading) { Text(title); if let subtitle { Text(subtitle.leadingUppercased).font(.caption).foregroundStyle(.secondary) } } } icon: { Image(systemName: image).frame(width: 30) }
    }

    private func directoryItem(for hit: SearchHit, kind: EntityKind) -> DirectoryItem? {
        directories[kind]?.first {
            $0.id == hit.id || ($0.slug != nil && $0.slug == hit.slug)
        }
    }

    @MainActor private func loadDirectory(_ kind: EntityKind) async {
        guard directories[kind] == nil else { return }
        if let values = try? await contentRepository.directory(kind: kind) {
            directories[kind] = values
        }
    }

    private func loadEventsAndCategories() async {
        do {
            async let loadedEvents = eventRepository.allUpcomingEvents(regionID: cityStore.selectedCity?.id)
            async let categories = try? eventRepository.inspirationCategories()
            let basicEvents = try await loadedEvents
            let remoteCategories = await categories ?? []
            inspirationCategories = remoteCategories.isEmpty ? InspirationCategory.fallback : remoteCategories
            if let enriched = try? await eventRepository.enrichingImages(in: basicEvents) {
                events = enriched
            } else {
                events = basicEvents
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func localInspirationEvents(for category: InspirationCategory) -> [ConcertEvent] {
        let terms = ([category.title, category.slug.replacingOccurrences(of: "_", with: " ")]
            + category.title.components(separatedBy: CharacterSet.alphanumerics.inverted))
            .map { $0.lowercased() }
            .filter { $0.count >= 4 && !["entdecken", "highlights", "konzerte", "musik"].contains($0) }
        return events.filter { event in
            let haystack = ([event.title, event.subtitle ?? "", event.category ?? ""] + event.genreLabels)
                .joined(separator: " ")
                .lowercased()
            return terms.contains { haystack.contains($0) }
                || (category.slug == "kostenlos" && event.isFree == true)
        }
    }

    private func search() async {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { hits = []; resultScope = .all; return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        do { hits = try await contentRepository.search(query: value, limit: 40) }
        catch {
            hits = directories.values.flatMap { $0 }.filter { $0.title.localizedStandardContains(value) }.map { SearchHit(id: $0.id, kind: $0.kind, slug: $0.slug, title: $0.title, subtitle: $0.subtitle) }
        }
    }
}

private struct DiscoveryTile: View {
    let kind: EntityKind
    let featured: DirectoryItem?
    let color: Color

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: [color, color.opacity(0.68)], startPoint: .topLeading, endPoint: .bottomTrailing)
            artwork
                .frame(width: 104, height: 104)
                .clipShape(.rect(cornerRadius: 12))
                .rotationEffect(.degrees(9))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                .offset(x: 17, y: 19)
            Text(kind.title)
                .font(.headline.bold())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(15)
        }
        .frame(height: 132)
        .clipShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var artwork: some View {
        if kind == .work {
            Image("WorkDiscovery")
                .resizable()
                .scaledToFill()
        } else if kind == .person,
                  featured?.title.localizedCaseInsensitiveContains("bach") == true {
            // Für die kuratierte Personen-Kachel immer das verlässliche
            // Bach-Porträt verwenden. Ein veralteter, aber nicht-nil gesetzter
            // photo_url-Wert darf diesen Fallback nicht mehr überspringen.
            CroppedAsyncImage(
                url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/6/6a/Johann_Sebastian_Bach.jpg/330px-Johann_Sebastian_Bach.jpg"),
                crop: nil
            ) {
                artworkPlaceholder
            }
        } else if let featured, featured.imageURL != nil {
            CroppedAsyncImage(url: featured.imageURL, crop: featured.avatarCrop) {
                artworkPlaceholder
            }
        } else {
            artworkPlaceholder
        }
    }

    private var artworkPlaceholder: some View {
        Rectangle()
            .fill(.white.opacity(0.16))
            .overlay {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
    }
}

private struct InspirationTile: View {
    let title: String
    let symbol: String
    let colors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: symbol)
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(.white.opacity(0.22))
                    .rotationEffect(.degrees(-9))
                    .offset(x: 8, y: 8)
                Text(title)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 108)
            .clipShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}

private struct SearchDiscoveryEventCard: View {
    let event: ConcertEvent
    // Nutzerfeedback: "jedes Konzert soll oben rechts noch einen Like-Button
    // haben" — @EnvironmentObject statt eigenem State, damit derselbe
    // FavoriteStore wie überall sonst in der App genutzt wird (inkl. dessen
    // eingebauter Haptik: confirm() beim Hinzufügen, soft() beim Entfernen,
    // siehe FavoriteStore.toggle).
    @EnvironmentObject private var favorites: FavoriteStore

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            EventArtwork(event: event)
                .frame(width: 238, height: 292)
                .clipped()
            LinearGradient(
                colors: [.clear, .black.opacity(0.18), .black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            // Eigener Button statt Teil der NavigationLink-Kachel: SwiftUI
            // behandelt einen Button innerhalb des Labels eines anderen
            // Buttons/NavigationLink als eigenständiges Tap-Ziel (gleiches
            // Muster wie der Herz-Button in coachEventMiniCard), Antippen
            // öffnet also NICHT zusätzlich die Eventdetailseite.
            VStack {
                HStack {
                    Spacer()
                    Button {
                        Task { await favorites.toggle(event.id) }
                    } label: {
                        Image(systemName: favorites.ids.contains(event.id) ? "heart.fill" : "heart")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(.black.opacity(0.32), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(favorites.ids.contains(event.id) ? "Von Favoriten entfernen" : "Zu Favoriten hinzufügen")
                }
                Spacer()
            }
            .padding(10)
            VStack(alignment: .leading, spacing: 6) {
                if let label = event.genreLabels.first ?? event.category {
                    Text(label.uppercased())
                        .font(.caption2.bold())
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.78))
                }
                Text(event.title)
                    .font(.headline.bold())
                    .lineLimit(3)
                Text(event.dateLine)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.white.opacity(0.78))
            }
            .foregroundStyle(.white)
            .padding(16)
        }
        .frame(width: 238, height: 292)
        .clipShape(.rect(cornerRadius: 22))
        .contentShape(.rect(cornerRadius: 22))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
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
                    Text(subtitle.leadingUppercased).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .frame(width: 60, height: 60)
                .clipped()
                .clipShape(.rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(event.dateLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

private struct SearchResultsSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.quaternary)
                        .frame(width: 60, height: 60)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(height: 15)
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 170, height: 11)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                if index < 4 { Divider().padding(.leading, 72) }
            }
        }
        .padding(.horizontal, 14)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .redacted(reason: .placeholder)
        .accessibilityLabel("Veranstaltungen werden geladen")
    }
}

struct DirectoryView: View {
    let kind: EntityKind
    let repository: any ContentRepository
    @State private var items: [DirectoryItem] = []
    @State private var directoryQuery = ""

    private var sections: [DirectorySection] {
        let normalizedQuery = directoryQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredItems = normalizedQuery.isEmpty ? items : items.filter {
            $0.title.localizedStandardContains(normalizedQuery) ||
            ($0.subtitle?.localizedStandardContains(normalizedQuery) ?? false)
        }
        let grouped = Dictionary(grouping: filteredItems) { DirectorySection.indexTitle(for: $0.title) }
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
        let normalizedQuery = directoryQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredItems = normalizedQuery.isEmpty ? items : items.filter {
            $0.title.localizedStandardContains(normalizedQuery) ||
            ($0.subtitle?.localizedStandardContains(normalizedQuery) ?? false) ||
            ($0.composer?.name.localizedStandardContains(normalizedQuery) ?? false)
        }
        let groupedByComposer = Dictionary(grouping: filteredItems) { $0.composer?.id ?? "unbekannt" }
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
                                NavigationLink {
                                    ComposerWorksView(group: group, repository: repository)
                                } label: {
                                    composerHeaderRow(group)
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
        .searchable(
            text: $directoryQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: kind == .work ? "Komponist:in oder Werk" : "Suchen"
        )
        .task { items = (try? await repository.directory(kind: kind)) ?? [] }
    }

    private func composerHeaderRow(_ group: ComposerGroup) -> some View {
        HStack(spacing: 13) {
            CroppedAsyncImage(url: group.imageURL, crop: group.avatarCrop) {
                Color.secondary.opacity(0.1).overlay {
                    Text(group.initials)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KlangradarTheme.accent)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(group.works.count) \(group.works.count == 1 ? "Werk" : "Werke")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
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
                    if let subtitle = item.subtitle { Text(subtitle.leadingUppercased).font(.subheadline).foregroundStyle(.secondary) }
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

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

private struct ComposerWorksView: View {
    let group: ComposerGroup
    let repository: any ContentRepository
    @State private var query = ""
    @State private var sortOrder: WorkSortOrder = .title

    private var visibleWorks: [DirectoryItem] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = value.isEmpty ? group.works : group.works.filter {
            $0.title.localizedStandardContains(value) || ($0.subtitle?.localizedStandardContains(value) ?? false)
        }
        switch sortOrder {
        case .title:
            return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .catalog:
            return filtered.sorted {
                let lhs = workDetailLine($0.subtitle) ?? $0.title
                let rhs = workDetailLine($1.subtitle) ?? $1.title
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
        }
    }

    private var sections: [DirectorySection] {
        let grouped = Dictionary(grouping: visibleWorks) { DirectorySection.indexTitle(for: $0.title) }
        return DirectorySection.indexTitles.compactMap { title in
            guard let works = grouped[title], !works.isEmpty else { return nil }
            return DirectorySection(title: title, items: works)
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    CroppedAsyncImage(url: group.imageURL, crop: group.avatarCrop) {
                        Color.secondary.opacity(0.1).overlay {
                            Text(group.initials).font(.headline).foregroundStyle(KlangradarTheme.accent)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name).font(.title3.weight(.semibold))
                        Text("\(group.works.count) \(group.works.count == 1 ? "Werk" : "Werke")")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                if let slug = group.slug {
                    NavigationLink {
                        EntityDetailView(
                            route: EntityRoute(kind: .person, identifier: slug),
                            repository: repository
                        )
                    } label: {
                        Label("Komponistenprofil öffnen", systemImage: "person.crop.circle")
                    }
                }
            }

            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.items) { work in
                        NavigationLink {
                            EntityDetailView(
                                route: EntityRoute(kind: .work, identifier: work.slug ?? work.id),
                                repository: repository
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(work.title.cleanedWorkTitle)
                                    .font(.headline)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let detail = workDetailLine(work.subtitle) {
                                    Text(detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Werke durchsuchen")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sortierung", selection: $sortOrder) {
                        ForEach(WorkSortOrder.allCases) { option in
                            Label(option.title, systemImage: option.systemImage).tag(option)
                        }
                    }
                } label: {
                    Label("Sortieren", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }

    private func workDetailLine(_ subtitle: String?) -> String? {
        guard var text = subtitle, !text.isEmpty else { return nil }
        if text.hasPrefix(group.name) {
            text.removeFirst(group.name.count)
            if text.hasPrefix(" · ") { text.removeFirst(3) }
        }
        return text.isEmpty ? nil : text
    }
}

private enum WorkSortOrder: String, CaseIterable, Identifiable {
    case title
    case catalog

    var id: String { rawValue }
    var title: String { self == .title ? "Nach Titel" : "Nach Werkangaben" }
    var systemImage: String { self == .title ? "textformat.abc" : "number" }
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
