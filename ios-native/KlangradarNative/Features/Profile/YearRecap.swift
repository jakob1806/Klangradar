import SwiftUI

/// Jahresrückblick aus den besuchten Konzerten (event_attendance), rein
/// clientseitig berechnet. Laut Preis-Konzept (docs/15) gehört die Grund-
/// ansicht allen, die Detailseiten (Top-Werke, Musiklandschaft) sind Plus.
struct YearRecap: Sendable, Equatable {
    struct Ranked: Sendable, Equatable {
        let name: String
        let count: Int
    }

    let year: Int
    let concerts: Int
    let works: Int
    let composers: Int
    let venues: Int
    let cities: Int
    let topComposer: Ranked?
    let topVenue: Ranked?
    let topGenre: Ranked?
    let busiestMonth: Ranked?
    let topWorks: [Ranked]
    let firstConcert: String?

    static func years(in visits: [VisitedConcert]) -> [Int] {
        let calendar = KlangradarDateTime.calendar
        return Set(visits.compactMap { $0.attendedAt.map { calendar.component(.year, from: $0) } }).sorted(by: >)
    }

    static func make(year: Int, visits allVisits: [VisitedConcert]) -> YearRecap {
        let calendar = KlangradarDateTime.calendar
        let visits = allVisits
            .filter { $0.attendedAt.map { calendar.component(.year, from: $0) } == year }
            .sorted { ($0.attendedAt ?? .distantPast) < ($1.attendedAt ?? .distantPast) }
        let works = visits.flatMap(\.works)

        func top(_ values: [String]) -> Ranked? {
            ranked(values).first
        }
        func ranked(_ values: [String]) -> [Ranked] {
            Dictionary(grouping: values, by: { $0 })
                .map { Ranked(name: $0.key, count: $0.value.count) }
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
        }

        let monthNames = visits.compactMap { $0.attendedAt.map { KlangradarDateTime.string($0, format: "MMMM") } }
        // Pro Konzert jeden Komponisten nur einmal zählen, sonst gewinnt, wer
        // an einem Abend fünf Lieder beigesteuert hat.
        let composersPerConcert = visits.flatMap { Set($0.works.compactMap(\.composerName)) }

        return YearRecap(
            year: year,
            concerts: visits.count,
            works: Set(works.map(\.id)).count,
            composers: Set(works.compactMap(\.composerID)).count,
            venues: Set(visits.compactMap(\.venueID)).count,
            cities: Set(visits.compactMap(\.city)).count,
            topComposer: top(composersPerConcert),
            topVenue: top(visits.map(\.venue)),
            topGenre: top(visits.flatMap(\.genres)),
            busiestMonth: top(monthNames),
            topWorks: Array(ranked(works.map { work in
                [work.composerName?.split(separator: " ").last.map(String.init), work.title.cleanedWorkTitle].compactMap { $0 }.joined(separator: ": ")
            }).prefix(5)),
            firstConcert: visits.first?.title
        )
    }
}

struct YearRecapView: View {
    let visits: [VisitedConcert]
    @State var year: Int
    @ObservedObject private var plus = PlusStore.shared
    @State private var showsPaywall = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    private var recap: YearRecap { YearRecap.make(year: year, visits: visits) }
    private var years: [Int] { YearRecap.years(in: visits) }

    var body: some View {
        NavigationStack {
            TabView {
                page { overviewPage }
                if let composer = recap.topComposer { page { highlightPage("Am häufigsten gehört", value: composer.name, detail: "in \(composer.count) \(composer.count == 1 ? "Konzert" : "Konzerten")", symbol: "person.wave.2.fill") } }
                if let venue = recap.topVenue { page { highlightPage("Dein Lieblingssaal", value: venue.name, detail: "\(venue.count)× besucht", symbol: "building.columns.fill") } }
                if let month = recap.busiestMonth { page { highlightPage("Dein Konzertmonat", value: month.name, detail: "\(month.count) \(month.count == 1 ? "Konzert" : "Konzerte")", symbol: "calendar") } }
                page { plusGated { topWorksPage } }
                page { sharePage }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .background { recapBackground.ignoresSafeArea() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if years.count > 1 {
                        Menu {
                            ForEach(years, id: \.self) { value in Button(String(value)) { year = value } }
                        } label: {
                            Label(String(year), systemImage: "chevron.down").labelStyle(.titleAndIcon)
                        }
                        .tint(.white)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }.tint(.white)
                }
            }
            .sheet(isPresented: $showsPaywall) {
                PlusPaywallView(reason: "Mit Plus siehst du deinen vollständigen Jahresrückblick mit allen Werken und Statistiken.")
            }
        }
    }

    private var recapBackground: some View {
        LinearGradient(colors: [KlangradarTheme.accent, .indigo, .black.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .foregroundStyle(.white)
            .padding(28)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var overviewPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("DEIN JAHR \(String(year))").font(.caption.bold()).tracking(2).opacity(0.8)
            Text("\(recap.concerts)").font(.system(size: 96, weight: .heavy, design: .rounded)).monospacedDigit()
            Text(recap.concerts == 1 ? "Konzert erlebt" : "Konzerte erlebt").font(.title.bold())
            VStack(alignment: .leading, spacing: 10) {
                stat(recap.works, "Werke", "music.note.list")
                stat(recap.composers, "Komponist:innen", "person.2.fill")
                stat(recap.venues, "Spielstätten", "building.columns")
                stat(recap.cities, recap.cities == 1 ? "Stadt" : "Städte", "map")
            }
            if let first = recap.firstConcert {
                Text("Angefangen hat alles mit „\(first)“.").font(.subheadline).opacity(0.85)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ value: Int, _ label: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 24)
            Text("\(value)").font(.title3.bold()).monospacedDigit()
            Text(label).font(.title3)
        }
    }

    private func highlightPage(_ eyebrow: String, value: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: symbol).font(.system(size: 54, weight: .semibold))
            Text(eyebrow.uppercased()).font(.caption.bold()).tracking(2).opacity(0.8)
            Text(value).font(.largeTitle.bold()).multilineTextAlignment(.center).minimumScaleFactor(0.6)
            Text(detail).font(.title3).opacity(0.85)
            Spacer()
        }
    }

    @ViewBuilder private func plusGated<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if plus.enforcesLimits {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "lock.fill").font(.system(size: 44))
                Text("Deine Top-Werke \(String(year))").font(.title.bold()).multilineTextAlignment(.center)
                Text("Der vollständige Rückblick gehört zu Klangradar Plus.").multilineTextAlignment(.center).opacity(0.85)
                Button("Plus ansehen") { showsPaywall = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(KlangradarTheme.accent)
                Spacer()
            }
        } else {
            content()
        }
    }

    private var topWorksPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TOP-WERKE").font(.caption.bold()).tracking(2).opacity(0.8)
            if recap.topWorks.isEmpty {
                Text("Zu deinen Konzerten sind noch keine Werke erfasst.").font(.title3)
            }
            ForEach(Array(recap.topWorks.enumerated()), id: \.offset) { index, work in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)").font(.title.bold()).monospacedDigit().frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(work.name).font(.headline).lineLimit(2)
                        Text("\(work.count)× live").font(.caption).opacity(0.8)
                    }
                }
            }
            if let genre = recap.topGenre {
                Text("Dein Schwerpunkt: \(genre.name)").font(.subheadline.weight(.semibold)).padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sharePage: some View {
        VStack(spacing: 22) {
            Spacer()
            YearRecapShareCard(recap: recap)
                .frame(width: 260, height: 340)
                .shadow(radius: 20)
            if let image = renderShareImage() {
                ShareLink(item: image, preview: SharePreview("Mein Klangradar-Jahr \(String(year))", image: image)) {
                    Label("Rückblick teilen", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(.white, in: .capsule)
                        .foregroundStyle(KlangradarTheme.accent)
                }
            }
            Spacer()
        }
    }

    @MainActor private func renderShareImage() -> Image? {
        let renderer = ImageRenderer(content: YearRecapShareCard(recap: recap).frame(width: 360, height: 470))
        renderer.scale = displayScale
        return renderer.uiImage.map(Image.init(uiImage:))
    }
}

/// Teilbares Bild (Story-Format) mit den wichtigsten Zahlen.
struct YearRecapShareCard: View {
    let recap: YearRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform").font(.headline)
                Text("Klangradar").font(.headline)
                Spacer()
                Text(String(recap.year)).font(.headline).monospacedDigit()
            }
            Spacer()
            Text("\(recap.concerts)").font(.system(size: 72, weight: .heavy, design: .rounded)).monospacedDigit()
            Text(recap.concerts == 1 ? "Konzert" : "Konzerte").font(.title2.bold())
            Text("\(recap.works) Werke · \(recap.composers) Komponist:innen · \(recap.venues) Säle").font(.caption).opacity(0.9)
            if let composer = recap.topComposer {
                Text("Meistgehört: \(composer.name)").font(.subheadline.weight(.semibold)).padding(.top, 6)
            }
            if let venue = recap.topVenue {
                Text("Lieblingssaal: \(venue.name)").font(.subheadline.weight(.semibold))
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [KlangradarTheme.accent, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
    }
}
