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
    @StateObject private var store = MarketingContentStore()
    @State private var showsEditor = false

    var body: some View {
        NavigationStack {
            ZStack {
                KlangradarBackground()
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 34) {
                        MarketingHeroView(
                            hero: store.content.hero,
                            height: horizontalSizeClass == .regular ? 280 : 224
                        )

                        ForEach(store.content.modules) { module in
                            MarketingEventRail(title: module.title, events: module.events)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 110)
                }
                .frame(maxWidth: KlangradarTheme.contentMaxWidth)
            }
            .navigationTitle("Klangradar")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showsEditor = true } label: {
                        Label("Bearbeiten", systemImage: "pencil")
                    }
                }
            }
            .sheet(isPresented: $showsEditor) {
                MarketingContentEditorView()
                    .environmentObject(store)
            }
        }
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

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.title2.bold())
                    .padding(.horizontal, KlangradarTheme.pagePadding)

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(events) { event in
                            MarketingEventCard(event: event)
                        }
                    }
                    .padding(.horizontal, KlangradarTheme.pagePadding)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

#Preview {
    MarketingHomeScreenView()
}
