import SwiftUI

struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var model: HomeViewModel
    private let contentRepository: any ContentRepository
    private let usesPreviewData: Bool
    @State private var collections: [EditorialCollection] = []

    init(
        repository: any EventRepository,
        contentRepository: any ContentRepository,
        usesPreviewData: Bool,
        auth: AuthStore? = nil,
        userRepository: UserRepository? = nil
    ) {
        _model = StateObject(wrappedValue: HomeViewModel(repository: repository, auth: auth, userRepository: userRepository))
        self.contentRepository = contentRepository
        self.usesPreviewData = usesPreviewData
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KlangradarBackground()
                    .ignoresSafeArea()

                content
                    .frame(maxWidth: KlangradarTheme.contentMaxWidth)
            }
            .navigationTitle("Klangradar")
            .navigationDestination(for: ConcertEvent.self) { event in
                EventDetailView(event: event, repository: model.repository, contentRepository: contentRepository)
            }
            .navigationDestination(for: EditorialCollection.self) { collection in
                CollectionDetailView(collection: collection, repository: contentRepository, eventRepository: model.repository)
            }
            .task {
                await model.load()
                collections = (try? await contentRepository.collections()) ?? []
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Konzerte werden geladen …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .failed(message):
            ContentUnavailableView {
                Label("Laden fehlgeschlagen", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Erneut versuchen") {
                    Task { await model.refresh() }
                }
            }

        case let .loaded(events):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 34) {
                    if usesPreviewData {
                        previewNotice
                    }

                    if let hero = events.first {
                        NavigationLink(value: hero) {
                            HeroEventView(event: hero, height: horizontalSizeClass == .regular ? 280 : 224)
                        }
                        .buttonStyle(.plain)
                    }

                    EventRail(
                        title: "Heute in München",
                        events: events.dropFirst().filter { event in
                            event.startDate.map(Calendar.current.isDateInToday) ?? false
                        }
                    )

                    EventRail(
                        title: "Demnächst in München",
                        // Nutzerfeedback: "zu wenig personalisiert" — Events,
                        // die zu den Interessen/Favoriten (Personen,
                        // Ensembles, Orte) passen, zuerst; innerhalb beider
                        // Gruppen bleibt die bisherige chronologische
                        // Reihenfolge erhalten (stabile Sortierung). Ohne
                        // Anmeldung/Interessen ist personalizedEntityIDs
                        // leer und die Reihenfolge bleibt exakt wie zuvor.
                        events: events.dropFirst()
                            .filter { event in
                                !(event.startDate.map(Calendar.current.isDateInToday) ?? false)
                            }
                            .sorted { lhs, rhs in
                                let lhsMatch = lhs.matchesPersonalization(model.personalizedEntityIDs)
                                let rhsMatch = rhs.matchesPersonalization(model.personalizedEntityIDs)
                                return lhsMatch && !rhsMatch
                            }
                    )

                    if !collections.isEmpty {
                        CollectionRail(collections: collections)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
            .refreshable { await model.refresh() }
        }
    }

    private var previewNotice: some View {
        Label(
            "Preview-Daten – Supabase noch nicht konfiguriert",
            systemImage: "hammer"
        )
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, KlangradarTheme.pagePadding)
    }
}

private struct CollectionRail: View {
    let collections: [EditorialCollection]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Redaktionelle Sammlungen")
                .font(.title2.bold())
                .padding(.horizontal, KlangradarTheme.pagePadding)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(collections) { collection in
                        NavigationLink(value: collection) {
                            VStack(alignment: .leading, spacing: 8) {
                                AsyncImage(url: collection.coverImageURL) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Rectangle().fill(.quaternary)
                                        .overlay { Image(systemName: "sparkles") }
                                }
                                .frame(width: 280, height: 160)
                                .clipShape(.rect(cornerRadius: 22))
                                Text(collection.title).font(.headline)
                                if let subtitle = collection.subtitle {
                                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            .frame(width: 280, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, KlangradarTheme.pagePadding)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct HeroEventView: View {
    let event: ConcertEvent
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            EventArtwork(event: event)
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
                        Text(heroDate(event))
                            .font(.caption.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.9))

                        Text(event.title)
                            .font(.title3.weight(.bold))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Label(event.subtitle ?? event.venueName, systemImage: "mappin")
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

    private func heroDate(_ event: ConcertEvent) -> String {
        guard let date = event.startDate else { return "NÄCHSTE VERANSTALTUNG" }
        let day = Calendar.current.isDateInToday(date) ? "HEUTE" : date.formatted(.dateTime.locale(Locale(identifier: "de_DE")).weekday(.abbreviated).day().month(.abbreviated)).uppercased()
        return "\(day) · \(date.formatted(date: .omitted, time: .shortened))"
    }
}

private struct EventRail: View {
    let title: String
    let events: [ConcertEvent]

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.bold())
                .padding(.horizontal, KlangradarTheme.pagePadding)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(events) { event in
                        NavigationLink(value: event) {
                            EventCard(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, KlangradarTheme.pagePadding)
            }
            .scrollIndicators(.hidden)
            }
        }
    }
}
