// Erstellt von Claude Code (Nutzerwunsch 24.10.2026, Punkt 12).
// Neu gestaltet 27.10.2026: weniger linear – Titelkarte, Monatsrhythmus,
// Kacheln statt Liste; Rhythmus, Wochentag und Ranglisten mit Plus,
// Teilen im Story-Format mit Plus.
import SwiftUI

/// "Dein Konzertjahr": Rückblick mit großen Zahlen, teilbar als Bild.
struct ConcertYearView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository

    @ObservedObject private var plus = PlusStore.shared
    @State private var year: ConcertYear?
    @State private var isLoading = true
    @State private var shareImage: Image?
    @State private var showsPaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let year {
                    YearHero(year: year)
                    if year.concerts > 0 {
                        YearDetails(year: year, isPlus: plus.isPlus) { showsPaywall = true }
                    }
                    shareButton(year)
                } else if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.horizontal, KlangradarTheme.pagePadding)
            .padding(.vertical, 16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsPaywall) {
            PlusPaywallView(reason: "Mit Plus siehst du dein ganzes Konzertjahr: Monatsrhythmus, Lieblingswochentag, alle Säle und Mitwirkenden.")
        }
        .task {
            guard let token = auth.accessToken else { isLoading = false; return }
            year = try? await repository.concertYear(token: token)
            isLoading = false
            renderShareImage()
        }
        .onChange(of: plus.isPlus) { _, _ in renderShareImage() }
    }

    @ViewBuilder private func shareButton(_ year: ConcertYear) -> some View {
        if let shareImage, year.concerts > 0 {
            ShareLink(item: shareImage, preview: SharePreview("Mein Konzertjahr \(String(year.year))", image: shareImage)) {
                Label(plus.isPlus ? "Als Story teilen" : "Als Bild teilen", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(KlangradarTheme.accent, in: .capsule)
            }
            .padding(.top, 8)
        }
    }

    private func renderShareImage() {
        guard let year else { return }
        let renderer: ImageRenderer<AnyView>
        if plus.isPlus {
            renderer = ImageRenderer(content: AnyView(YearStoryPoster(year: year).frame(width: 360, height: 640)))
        } else {
            renderer = ImageRenderer(content: AnyView(YearHero(year: year).padding(20).frame(width: 420).background(Color.white)))
        }
        renderer.scale = 3
        if let image = renderer.uiImage { shareImage = Image(uiImage: image) }
    }
}

// MARK: - Bausteine

enum YearStyle {
    static let monthInitials = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
    static let monthNames = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]
    static let weekdayShort = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    static let weekdayNames = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]

    static var heroGradient: LinearGradient {
        LinearGradient(colors: [KlangradarTheme.accent, Color.indigo, Color.black.opacity(0.92)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func peak(_ values: [Int]) -> Int? {
        guard let max = values.max(), max > 0 else { return nil }
        return values.firstIndex(of: max)
    }
}

/// Titelkarte: Jahr, Konzertzahl und die drei Eckdaten.
private struct YearHero: View {
    let year: ConcertYear

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Dein Konzertjahr").font(.system(.title3, design: .serif).italic())
                Spacer()
                Text(String(year.year)).font(.headline.monospacedDigit()).opacity(0.75)
            }
            if year.concerts == 0 {
                Text("Noch keine Konzerte erfasst. Markiere Konzerte als besucht oder trag sie im Profil ein, dann füllt sich dein Jahr.")
                    .font(.subheadline).opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text("\(year.concerts)")
                        .font(.system(size: 92, weight: .bold, design: .serif))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(year.concerts == 1 ? "Konzert" : "Konzerte")
                        .font(.system(.title2, design: .serif))
                        .opacity(0.85)
                }
                HStack(spacing: 0) {
                    heroStat("\(max(1, year.minutes / 60))", "Stunden")
                    divider
                    heroStat("\(year.venues)", year.venues == 1 ? "Saal" : "Säle")
                    divider
                    if year.works > 0 {
                        heroStat("\(year.works)", year.works == 1 ? "Werk" : "Werke")
                    } else {
                        heroStat("\(year.topComposers.count)", "Komponisten")
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(YearStyle.heroGradient, in: .rect(cornerRadius: 28, style: .continuous))
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 34).padding(.horizontal, 12)
    }

    private func heroStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title2.bold().monospacedDigit())
            Text(label).font(.caption).opacity(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Kacheln unter der Titelkarte.
private struct YearDetails: View {
    let year: ConcertYear
    let isPlus: Bool
    let showPaywall: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if !year.months.isEmpty { locked { RhythmTile(months: year.months) } }
            if !year.topComposers.isEmpty { ComposerTile(items: year.topComposers) }
            HStack(alignment: .top, spacing: 12) {
                if let best = year.bestRated {
                    SmallTile(label: "Bester Abend", value: best.title, accent: String(repeating: "★", count: best.stars))
                } else if let first = year.first {
                    SmallTile(label: "Angefangen mit", value: first, accent: nil)
                }
                if !year.weekdays.isEmpty, let peak = YearStyle.peak(year.weekdays) {
                    locked { WeekdayTile(weekdays: year.weekdays, peak: peak) }
                } else if let venue = year.topVenue {
                    SmallTile(label: "Lieblingssaal", value: venue, accent: nil)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if !year.topVenues.isEmpty {
                locked { RankingTile(title: "Deine Säle", symbol: "building.columns", items: year.topVenues) }
            } else if let venue = year.topVenue, !year.weekdays.isEmpty {
                SmallTile(label: "Lieblingssaal", value: venue, accent: nil)
            }
            if !year.topArtists.isEmpty {
                locked { RankingTile(title: "Am häufigsten erlebt", symbol: "person.2", items: year.topArtists) }
            } else if let artist = year.topArtist {
                SmallTile(label: "Am häufigsten erlebt", value: artist, accent: nil)
            }
            if year.bestRated != nil, let first = year.first {
                SmallTile(label: "Angefangen mit", value: first, accent: nil)
            }
        }
    }

    /// Ohne Plus: Kachel verschwommen mit Hinweis, Tippen öffnet die Paywall.
    @ViewBuilder private func locked<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if isPlus {
            content()
        } else {
            Button(action: showPaywall) {
                content()
                    .blur(radius: 7)
                    .allowsHitTesting(false)
                    .overlay {
                        Label("Mit Plus", systemImage: "lock.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.regularMaterial, in: .capsule)
                    }
                    .clipShape(.rect(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct TileBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 22, style: .continuous))
    }
}

private extension View {
    func yearTile() -> some View { modifier(TileBackground()) }
}

private struct TileLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).tracking(1.1).foregroundStyle(.secondary)
    }
}

/// Zwölf Monatsbalken, der stärkste Monat hervorgehoben.
private struct RhythmTile: View {
    let months: [Int]

    var body: some View {
        let peak = YearStyle.peak(months)
        let maxValue = CGFloat(max(1, months.max() ?? 1))
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                TileLabel(text: "Dein Rhythmus")
                Spacer()
                if let peak {
                    Text("Stärkster Monat: \(YearStyle.monthNames[peak])").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(months.prefix(12).enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 6) {
                        Text(value > 0 ? "\(value)" : " ")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(index == peak ? AnyShapeStyle(KlangradarTheme.accent) : AnyShapeStyle(KlangradarTheme.accent.opacity(value > 0 ? 0.35 : 0.1)))
                            .frame(height: max(6, 84 * CGFloat(value) / maxValue))
                        Text(YearStyle.monthInitials[index])
                            .font(.caption2.weight(index == peak ? .bold : .regular))
                            .foregroundStyle(index == peak ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 124, alignment: .bottom)
        }
        .yearTile()
    }
}

/// Komponisten: Nummer eins groß, danach Balken im Verhältnis.
private struct ComposerTile: View {
    let items: [(name: String, count: Int)]

    var body: some View {
        let top = items[0]
        let maxCount = CGFloat(max(1, top.count))
        VStack(alignment: .leading, spacing: 14) {
            TileLabel(text: "Am meisten gehört")
            VStack(alignment: .leading, spacing: 2) {
                Text(top.name)
                    .font(.system(.title, design: .serif).weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text("in \(top.count) \(top.count == 1 ? "Konzert" : "Konzerten")").font(.subheadline).foregroundStyle(.secondary)
            }
            if items.count > 1 {
                VStack(spacing: 9) {
                    ForEach(Array(items.dropFirst().enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 10) {
                            Text(item.name).font(.subheadline).lineLimit(1).minimumScaleFactor(0.85).frame(width: 165, alignment: .leading)
                            GeometryReader { proxy in
                                Capsule().fill(KlangradarTheme.accent.opacity(0.3))
                                    .frame(width: max(8, proxy.size.width * CGFloat(item.count) / maxCount))
                            }
                            .frame(height: 8)
                            Text("\(item.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .yearTile()
    }
}

private struct SmallTile: View {
    let label: String
    let value: String
    let accent: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TileLabel(text: label)
            Text(value).font(.headline).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            if let accent { Text(accent).font(.subheadline).foregroundStyle(KlangradarTheme.accent) }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 110, maxHeight: .infinity, alignment: .topLeading)
        .yearTile()
        .frame(maxHeight: .infinity)
    }
}

/// Wochentage als Punktreihe, der häufigste hervorgehoben.
private struct WeekdayTile: View {
    let weekdays: [Int]
    let peak: Int

    var body: some View {
        let maxValue = CGFloat(max(1, weekdays.max() ?? 1))
        VStack(alignment: .leading, spacing: 8) {
            TileLabel(text: "Lieblingstag")
            Text(YearStyle.weekdayNames[peak]).font(.headline)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(weekdays.prefix(7).enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(index == peak ? AnyShapeStyle(KlangradarTheme.accent) : AnyShapeStyle(KlangradarTheme.accent.opacity(value > 0 ? 0.3 : 0.08)))
                            .frame(width: 6 + 10 * CGFloat(value) / maxValue, height: 6 + 10 * CGFloat(value) / maxValue)
                            .frame(height: 16, alignment: .bottom)
                        Text(YearStyle.weekdayShort[index]).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(minHeight: 110, maxHeight: .infinity, alignment: .topLeading)
        .yearTile()
        .frame(maxHeight: .infinity)
    }
}

private struct RankingTile: View {
    let title: String
    let symbol: String
    let items: [(name: String, count: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label { TileLabel(text: title) } icon: { Image(systemName: symbol).font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(.title3, design: .serif).weight(.semibold))
                        .foregroundStyle(index == 0 ? KlangradarTheme.accent : .secondary)
                        .frame(width: 20, alignment: .leading)
                    Text(item.name).font(index == 0 ? .headline : .subheadline).lineLimit(2)
                    Spacer(minLength: 8)
                    Text("\(item.count)×").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .yearTile()
    }
}

/// Teilbild im Story-Format (9:16) für Plus.
private struct YearStoryPoster: View {
    let year: ConcertYear

    var body: some View {
        let peak = YearStyle.peak(year.months)
        let maxValue = CGFloat(max(1, year.months.max() ?? 1))
        VStack(alignment: .leading, spacing: 22) {
            Text("Mein Konzertjahr").font(.system(size: 22, design: .serif).italic()).opacity(0.85)
            Text(String(year.year)).font(.system(size: 30, weight: .semibold).monospacedDigit()).opacity(0.6)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(year.concerts)").font(.system(size: 120, weight: .bold, design: .serif)).monospacedDigit()
                Text(year.concerts == 1 ? "Konzert" : "Konzerte").font(.system(size: 28, design: .serif)).opacity(0.85)
            }
            if !year.months.isEmpty {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(year.months.prefix(12).enumerated()), id: \.offset) { index, value in
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.white.opacity(index == peak ? 1 : (value > 0 ? 0.45 : 0.15)))
                                .frame(height: max(4, 70 * CGFloat(value) / maxValue))
                            Text(YearStyle.monthInitials[index]).font(.system(size: 10)).opacity(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 90, alignment: .bottom)
            }
            VStack(alignment: .leading, spacing: 12) {
                if let composer = year.topComposers.first { posterLine("Am meisten gehört", composer.name) }
                if let venue = year.topVenue { posterLine("Lieblingssaal", venue) }
                posterLine("Musik", "\(max(1, year.minutes / 60)) Stunden in \(year.venues) \(year.venues == 1 ? "Saal" : "Sälen")")
            }
            Spacer(minLength: 0)
            Text("klangradar").font(.system(size: 15, weight: .bold)).tracking(1.5).opacity(0.7)
        }
        .foregroundStyle(.white)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(YearStyle.heroGradient)
    }

    private func posterLine(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.2).opacity(0.65)
            Text(value).font(.system(size: 19, weight: .semibold)).lineLimit(2)
        }
    }
}
