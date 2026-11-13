// Erstellt von Claude Code (13.11.2026): Startseiten-Modul „Weil du … hörst“
// – die drei besten Musikgeschmack-Konzerte der gewählten Stadt. Erscheint
// nur, wenn ein Musikgeschmack verknüpft ist und es Treffer gibt.
import SwiftUI

struct MusicTasteHomeModule: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository
    let contentRepository: any ContentRepository
    @EnvironmentObject private var cityStore: CityStore
    @State private var taste: MusicTaste?

    var body: some View {
        Group {
            if let taste, let events = Optional(taste.events.filter { $0.reasons != ["Passt zu deinen Genres"] }), !events.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title(taste)).font(.title2.bold()).lineLimit(1)
                        Spacer()
                        NavigationLink {
                            MusicTasteView(auth: auth, repository: repository, contentRepository: contentRepository)
                        } label: { Text("Mehr").font(.subheadline.weight(.semibold)) }
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(events.prefix(3).enumerated()), id: \.element.id) { index, item in
                            Button { if let slug = item.slug { DeepLinkRouter.shared.handle(route: "/event/\(slug)") } } label: {
                                HStack(spacing: 12) {
                                    CachedAsyncImage(url: item.imageURL, maxPixel: 200) { phase in
                                        if let image = phase.image { image.resizable().scaledToFill() }
                                        else { Color(uiColor: .tertiarySystemFill).overlay { Image(systemName: "music.note").foregroundStyle(.secondary) } }
                                    }
                                    .frame(width: 52, height: 52).clipShape(.rect(cornerRadius: 10, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                                        if let subtitle = item.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < min(events.count, 3) - 1 { Divider().padding(.leading, 76) }
                        }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 18, style: .continuous))
                }
                .padding(.horizontal, KlangradarTheme.pagePadding)
            }
        }
        .task(id: cityStore.selectedCity?.id) {
            guard let token = auth.accessToken else { return }
            taste = await repository.musicTaste(cityID: cityStore.selectedCity?.id, token: token)
        }
    }

    private func title(_ taste: MusicTaste) -> String {
        if let top = taste.events.first?.reasons.first { return "Weil du \(top.split(separator: " ").last.map(String.init) ?? top) hörst" }
        return "Für deinen Geschmack"
    }
}
