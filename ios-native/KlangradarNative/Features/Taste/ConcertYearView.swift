// Erstellt von Claude Code (Nutzerwunsch 24.10.2026, Punkt 12).
import SwiftUI

/// "Dein Konzertjahr": ruhiger Rückblick mit großen Zahlen, teilbar als Bild.
struct ConcertYearView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository

    @State private var year: ConcertYear?
    @State private var isLoading = true
    @State private var shareImage: Image?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let year {
                    YearPoster(year: year)
                    if let shareImage {
                        ShareLink(item: shareImage, preview: SharePreview("Mein Konzertjahr \(year.year)", image: shareImage)) {
                            Label("Als Bild teilen", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(.white)
                                .background(KlangradarTheme.accent, in: .capsule)
                        }
                    }
                } else if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.horizontal, KlangradarTheme.pagePadding)
            .padding(.vertical, 16)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let token = auth.accessToken else { isLoading = false; return }
            year = try? await repository.concertYear(token: token)
            isLoading = false
            if let year {
                let renderer = ImageRenderer(content: YearPoster(year: year).padding(32).frame(width: 420).background(.white))
                renderer.scale = 3
                if let image = renderer.uiImage { shareImage = Image(uiImage: image) }
            }
        }
    }
}

private struct YearPoster: View {
    let year: ConcertYear

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DEIN KONZERTJAHR").font(.footnote.weight(.semibold)).tracking(1.4).foregroundStyle(KlangradarTheme.accent)
                Text(String(year.year)).font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
            }
            if year.concerts == 0 {
                Text("Noch keine Konzerte erfasst. Markiere Konzerte als besucht oder bewerte sie – dann füllt sich dein Jahr.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    stat("\(year.concerts)", year.concerts == 1 ? "Konzert" : "Konzerte")
                    stat("\(max(1, year.minutes / 60))", "Stunden Musik")
                    stat("\(year.venues)", year.venues == 1 ? "Saal" : "Säle")
                }
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                if !year.topComposers.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Am meisten gehört").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(Array(year.topComposers.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("\(index + 1)").font(.headline.monospacedDigit()).foregroundStyle(KlangradarTheme.accent).frame(width: 18)
                                Text(item.name).font(.title3.weight(.semibold))
                                Spacer()
                                Text("\(item.count)×").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    if let venue = year.topVenue { line("Lieblingssaal", venue) }
                    if let artist = year.topArtist { line("Am häufigsten erlebt", artist) }
                    if let best = year.bestRated { line("Bester Abend", "\(best.title) · \(String(repeating: "★", count: best.stars))") }
                    if let first = year.first { line("Angefangen mit", first) }
                }
            }
            Text("klangradar").font(.caption.weight(.bold)).tracking(1).foregroundStyle(.secondary)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).lineLimit(2)
        }
    }
}
