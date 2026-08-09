import SwiftUI

struct CollectionDetailView: View {
    let collection: EditorialCollection
    let repository: any ContentRepository
    let eventRepository: any EventRepository
    @State private var resolved: EditorialCollection?

    private var content: EditorialCollection { resolved ?? collection }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                AsyncImage(url: content.coverImageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(height: 280)
                .clipShape(.rect(cornerRadius: 28))

                VStack(alignment: .leading, spacing: 10) {
                    if let subtitle = content.subtitle {
                        Text(subtitle).font(.headline).foregroundStyle(.secondary)
                    }
                    if let description = content.description {
                        Text(description).font(.body)
                    }
                }

                ForEach(content.events) { event in
                    NavigationLink(value: event) {
                        EventCard(event: event)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(KlangradarTheme.pagePadding)
        }
        .navigationTitle(content.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ConcertEvent.self) { EventDetailView(event: $0, repository: eventRepository, contentRepository: repository) }
        .task { resolved = try? await repository.collection(slug: collection.slug) }
    }
}
