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

    var body: some View {
        HStack(spacing: 14) {
            EventArtwork(event: event)
                .frame(width: 112, height: 92)
                .clipped()
                .clipShape(.rect(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.headline)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(event.dateLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.thinMaterial, in: .rect(cornerRadius: 20))
        .contentShape(.rect)
    }
}
