import SwiftUI

/// Homescreen-Nachbau für Social-Media-Screenshots: identisches Layout wie
/// `HomeView` (`KlangradarBackground`, Hero + Rails, gleiche Fonts/Abstände/
/// Kartenform), aber mit frei editierbaren Inhalten statt Supabase-Daten —
/// über den Stift-Button oben rechts direkt im Simulator bearbeitbar (Texte,
/// Kategorien, Reihenfolge, Bilder per URL oder aus der Fotomediathek).
/// Kein Netzwerkzugriff außer zum Laden der eingetragenen Bild-URLs. Nur für
/// Marketing-Screenshots gedacht, niemals im echten Nutzerfluss einhängen.
struct MarketingHomeScreenView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var store: MarketingContentStore
    @EnvironmentObject private var cityStore: CityStore
    @Binding var isPresentationMode: Bool
    let availableEvents: [ConcertEvent]
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
    @State private var showsEditor = false

    var body: some View {
        NavigationStack {
            ZStack {
                KlangradarBackground()
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 34) {
                        heroLink

                        ForEach(store.content.modules) { module in
                            MarketingEventRail(
                                title: module.title,
                                events: module.events,
                                availableEvents: availableEvents
                            )
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 110)
                }
                .frame(maxWidth: KlangradarTheme.contentMaxWidth)
            }
            .navigationTitle("Klangradar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CityCompactMenu(cityStore: cityStore)
                }
            }
            .toolbar {
                if !isPresentationMode {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showsEditor = true } label: {
                            Label("Bearbeiten", systemImage: "pencil")
                        }
                    }
                }
            }
            .sheet(isPresented: $showsEditor) {
                MarketingContentEditorView(surface: .home, availableEvents: availableEvents) {
                    isPresentationMode = true
                }
                .environmentObject(store)
            }
            .navigationDestination(for: MarketingEventData.self) { event in
                MarketingEventDetailView(event: event)
            }
            .navigationDestination(for: ConcertEvent.self) { event in
                EventDetailView(event: event, repository: eventRepository, contentRepository: contentRepository)
            }
        }
    }

    @ViewBuilder
    private var heroLink: some View {
        if let event = linkedEvent(for: store.content.hero.sourceEventID) {
            NavigationLink(value: event) { heroView }
                .buttonStyle(.plain)
        } else {
            NavigationLink(value: heroEvent) { heroView }
                .buttonStyle(.plain)
        }
    }

    private var heroView: some View {
        MarketingHeroView(hero: store.content.hero, height: horizontalSizeClass == .regular ? 280 : 224)
    }

    private func linkedEvent(for id: UUID?) -> ConcertEvent? {
        guard let id else { return nil }
        return availableEvents.first(where: { $0.id == id })
    }

    private var heroEvent: MarketingEventData {
        MarketingEventData(
            imagePath: store.content.hero.imagePath,
            title: store.content.hero.title,
            subtitle: "\(store.content.hero.dateLabel) · \(store.content.hero.venue)"
        )
    }
}

// MARK: - Layout (1:1 Nachbau der Darstellung aus HomeView, mit freien Texten/Bildern)

private struct MarketingArtwork: View {
    let imagePath: String?

    var body: some View {
        AsyncImage(url: MarketingContentStore.resolvedURL(for: imagePath)) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFill()
            case .failure:
                placeholder
            case .empty:
                placeholder.overlay { ProgressView().tint(.white) }
            @unknown default:
                placeholder
            }
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [KlangradarTheme.deepInk, KlangradarTheme.accent],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note.list")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}

/// Exakter Nachbau von `HeroEventView` aus `HomeView.swift`.
private struct MarketingHeroView: View {
    let hero: MarketingHeroData
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            MarketingArtwork(imagePath: hero.imagePath)
                .frame(width: proxy.size.width, height: height)
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.16), location: 0.28),
                            .init(color: .black.opacity(0.86), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: min(height * 0.72, 170))
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(hero.dateLabel)
                            .font(.caption.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.9))

                        Text(hero.title)
                            .font(.title3.weight(.bold))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Label(hero.venue, systemImage: "mappin")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.34), radius: 7, y: 2)
                    .padding(18)
                    .frame(width: proxy.size.width, alignment: .leading)
                }
                .clipShape(.rect(cornerRadius: 24))
        }
        .frame(height: height)
        .padding(.horizontal, KlangradarTheme.pagePadding)
        .accessibilityElement(children: .combine)
    }
}

/// Exakter Nachbau von `EventCard` aus DesignSystem/Components/EventCard.swift.
private struct MarketingEventCard: View {
    let event: MarketingEventData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MarketingArtwork(imagePath: event.imagePath)
                .frame(width: 196, height: 110)
                .clipped()
                .clipShape(.rect(cornerRadius: 18))
                .overlay(alignment: .topTrailing) {
                    GlassIconButton(systemImage: "heart", accessibilityLabel: "Zu Favoriten hinzufügen") {}
                        .padding(8)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(event.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 196, height: 192, alignment: .topLeading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Exakter Nachbau von `EventRail` aus `HomeView.swift`.
private struct MarketingEventRail: View {
    let title: String
    let events: [MarketingEventData]
    let availableEvents: [ConcertEvent]

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.title2.bold())
                    .padding(.horizontal, KlangradarTheme.pagePadding)

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(events) { event in
                            if let liveEvent = linkedEvent(for: event) {
                                NavigationLink(value: liveEvent) { MarketingEventCard(event: event) }
                                    .buttonStyle(.plain)
                            } else {
                                NavigationLink(value: event) { MarketingEventCard(event: event) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, KlangradarTheme.pagePadding)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func linkedEvent(for marketingEvent: MarketingEventData) -> ConcertEvent? {
        guard let id = marketingEvent.sourceEventID else { return nil }
        return availableEvents.first(where: { $0.id == id })
    }
}

/// Editierbarer Suche-Tab für Marketing-Aufnahmen. Er verhält sich wie die
/// normale Suche (Eingabe, Filterung, antippbare Details), verwendet aber
/// bewusst den vom Marketing festgelegten Inhalt.
struct MarketingSearchScreenView: View {
    @EnvironmentObject private var store: MarketingContentStore
    @EnvironmentObject private var cityStore: CityStore
    @Binding var isPresentationMode: Bool
    let availableEvents: [ConcertEvent]
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
    @State private var query = ""
    @State private var showsEditor = false

    private var visibleEvents: [MarketingEventData] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.content.search.events }
        return store.content.search.events.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KlangradarBackground().ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            discoveryContent
                        } else {
                            Text("Ergebnisse")
                                .font(.title2.bold())
                                .padding(.horizontal, KlangradarTheme.pagePadding)

                            if visibleEvents.isEmpty {
                                ContentUnavailableView.search(text: query)
                                    .padding(.top, 48)
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(visibleEvents) { event in
                                        marketingEventLink(event) {
                                            MarketingSearchEventRow(event: event)
                                        }
                                        if event.id != visibleEvents.last?.id {
                                            Divider().padding(.leading, 132)
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                .background(.regularMaterial, in: .rect(cornerRadius: 24))
                                .padding(.horizontal, KlangradarTheme.pagePadding)
                            }
                        }
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 116)
                }
            }
            .navigationTitle("Suche")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CityCompactMenu(cityStore: cityStore)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Konzerte, Personen, Ensembles, Orte, Werke")
            .toolbar {
                if !isPresentationMode {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showsEditor = true } label: {
                            Label("Bearbeiten", systemImage: "pencil")
                        }
                    }
                }
            }
            .sheet(isPresented: $showsEditor) {
                MarketingContentEditorView(surface: .search, availableEvents: availableEvents) {
                    isPresentationMode = true
                }
                .environmentObject(store)
            }
            .navigationDestination(for: MarketingEventData.self) { event in
                MarketingEventDetailView(event: event)
            }
            .navigationDestination(for: ConcertEvent.self) { event in
                EventDetailView(event: event, repository: eventRepository, contentRepository: contentRepository)
            }
            .navigationDestination(for: EntityKind.self) { kind in
                DirectoryView(kind: kind, repository: contentRepository)
            }
        }
    }

    private var discoveryContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Alles entdecken")
                .font(.title2.bold())

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 14
            ) {
                ForEach(EntityKind.allCases, id: \.self) { kind in
                    NavigationLink(value: kind) {
                        MarketingDiscoveryTile(kind: kind)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !store.content.search.headline.isEmpty {
                Text(store.content.search.headline)
                    .font(.title2.bold())
                    .padding(.top, 10)
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(store.content.search.events) { event in
                        marketingEventLink(event) {
                            MarketingSearchDiscoveryEventCard(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, KlangradarTheme.pagePadding)
    }

    @ViewBuilder
    private func marketingEventLink<Content: View>(
        _ event: MarketingEventData,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if let liveEvent = linkedEvent(for: event) {
            NavigationLink(value: liveEvent, label: content)
        } else {
            NavigationLink(value: event, label: content)
        }
    }

    private func linkedEvent(for marketingEvent: MarketingEventData) -> ConcertEvent? {
        guard let id = marketingEvent.sourceEventID else { return nil }
        return availableEvents.first(where: { $0.id == id })
    }
}

private struct MarketingSearchEventRow: View {
    let event: MarketingEventData

    var body: some View {
        HStack(spacing: 14) {
            MarketingArtwork(imagePath: event.imagePath)
                .frame(width: 104, height: 76)
                .clipShape(.rect(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 5) {
                Text(event.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                Text(event.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, KlangradarTheme.pagePadding)
        .contentShape(.rect)
    }
}

/// Die vier Entdecken-Einstiege folgen dem Aufbau der echten Suche. Sie
/// bleiben im Aufnahmemodus voll bedienbar und öffnen die normalen Verzeichnisse.
private struct MarketingDiscoveryTile: View {
    let kind: EntityKind

    private var colors: [Color] {
        switch kind {
        case .person: [.indigo, .purple]
        case .ensemble: [.teal, .blue]
        case .venue: [.orange, .red]
        case .work: [.pink, .purple]
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: kind.systemImage)
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(.white.opacity(0.24))
                .rotationEffect(.degrees(-9))
                .offset(x: 12, y: 12)
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
}

private struct MarketingSearchDiscoveryEventCard: View {
    let event: MarketingEventData

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MarketingArtwork(imagePath: event.imagePath)
                .frame(width: 238, height: 292)
                .clipped()
            LinearGradient(
                colors: [.clear, .black.opacity(0.18), .black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 6) {
                Text("KONZERT")
                    .font(.caption2.bold())
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.78))
                Text(event.title)
                    .font(.headline.bold())
                    .lineLimit(3)
                Text(event.subtitle)
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

private struct MarketingEventDetailView: View {
    let event: MarketingEventData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MarketingArtwork(imagePath: event.imagePath)
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .clipped()
                VStack(alignment: .leading, spacing: 10) {
                    Text(event.title).font(.title.bold())
                    Label(event.subtitle, systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Divider().padding(.vertical, 4)
                    Text("Über die Veranstaltung").font(.title3.bold())
                    Text("Alle Angaben, Bilder und Texte wurden für diese Marketing-Aufnahme vorbereitet.")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, KlangradarTheme.pagePadding)
            }
            .padding(.bottom, 40)
        }
        .navigationTitle("Veranstaltung")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    MarketingHomeScreenView(
        isPresentationMode: .constant(false),
        availableEvents: [],
        eventRepository: PreviewEventRepository(),
        contentRepository: PreviewContentRepository()
    )
        .environmentObject(MarketingContentStore())
}
