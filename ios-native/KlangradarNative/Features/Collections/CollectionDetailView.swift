import SwiftUI

struct CollectionDetailView: View {
    let collection: EditorialCollection
    let repository: any ContentRepository
    let eventRepository: any EventRepository
    @State private var resolved: EditorialCollection?

    private var content: EditorialCollection { resolved ?? collection }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                collectionHero

                VStack(alignment: .leading, spacing: 10) {
                    if let subtitle = content.subtitle {
                        Text(subtitle).font(.headline).foregroundStyle(.secondary)
                    }
                    if let description = content.description {
                        Text(description).font(.body)
                    }
                }

                if !content.events.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(content.events.count) Veranstaltungen")
                            .font(.title2.bold())

                        LazyVStack(spacing: 12) {
                            ForEach(content.events) { event in
                                NavigationLink(value: event) {
                                    CollectionEventRow(event: event)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(KlangradarTheme.pagePadding)
            .padding(.bottom, 100)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background { KlangradarBackground().ignoresSafeArea() }
        .navigationTitle(content.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ConcertEvent.self) { EventDetailView(event: $0, repository: eventRepository, contentRepository: repository) }
        .navigationDestination(for: EntityRoute.self) { EntityDetailView(route: $0, repository: repository) }
        .task {
            guard let loaded = try? await repository.collection(slug: collection.slug) else { return }
            let enriched = (try? await eventRepository.enrichingImages(in: loaded.events)) ?? loaded.events
            resolved = EditorialCollection(
                id: loaded.id,
                slug: loaded.slug,
                title: loaded.title,
                subtitle: loaded.subtitle,
                description: loaded.description,
                coverImageURL: loaded.coverImageURL,
                events: enriched
            )
        }
    }

    @ViewBuilder
    private var collectionHero: some View {
        if let url = content.coverImageURL {
            GeometryReader { proxy in
                AsyncImage(url: url) { image in
                    ZStack {
                        Color.black
                        image.resizable().scaledToFill().blur(radius: 22).scaleEffect(1.12).opacity(0.55)
                        image.resizable().scaledToFit()
                    }
                } placeholder: {
                    Rectangle().fill(.quaternary).overlay { ProgressView() }
                }
                .frame(width: proxy.size.width, height: 230)
                .clipped()
            }
            .frame(height: 230)
            .clipShape(.rect(cornerRadius: 24))
        }
    }
}

private struct CollectionEventRow: View {
    let event: ConcertEvent
    // Einheitliche Konzertzeile (02.11.2026).
    var body: some View { ConcertRow(event: event).background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous)) }
}
