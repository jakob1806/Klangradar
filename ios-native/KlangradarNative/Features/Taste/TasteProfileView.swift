// Erstellt von Claude Code (Nutzerwunsch 24.10.2026, Punkte 5+6).
// Neu gestaltet 29.10.2026 (Nutzerwunsch: "optischer, schöner, orientiert an
// Dein Konzertjahr"): Titelkarte mit Verlauf, darunter Kacheln statt einer
// langen Liste.
import SwiftUI

/// "Dein Geschmack": was Klangradar aus Merken, Hingehen, Bewertungen und
/// Folgen gelernt hat – transparent, damit Empfehlungen nachvollziehbar sind.
struct TasteProfileView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository
    let contentRepository: any ContentRepository

    @State private var profile: TasteProfile?
    @State private var thumbnails: [UUID: URL] = [:]
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    TasteHero(profile: profile)
                    if let profile, !profile.isEmpty {
                        if !profile.composers.isEmpty { TasteComposerTile(entries: Array(profile.composers.prefix(5)), thumbnails: thumbnails, contentRepository: contentRepository) }
                        if !profile.artists.isEmpty { TasteArtistsTile(entries: Array(profile.artists.prefix(12)), thumbnails: thumbnails, contentRepository: contentRepository) }
                        HStack(alignment: .top, spacing: 12) {
                            if !profile.venues.isEmpty { TasteVenuesTile(entries: Array(profile.venues.prefix(4)), thumbnails: thumbnails, contentRepository: contentRepository) }
                            if !profile.weekdays.isEmpty { TasteWeekdayTile(profile: profile) }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Text("Entsteht aus dem, was du merkst, besuchst, bewertest und wem du folgst. Empfehlungen zeigen dazu eine kurze Begründung – und ab und zu bewusst etwas Neues.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, KlangradarTheme.pagePadding)
            .padding(.vertical, 16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let token = auth.accessToken { profile = try? await repository.tasteProfile(token: token) }
            isLoading = false
            if let profile, let token = auth.accessToken {
                let people = profile.composers + profile.artists.filter { $0.kind != "ensemble" }
                thumbnails = await repository.entityThumbnails(
                    personIDs: people.map(\.id),
                    ensembleIDs: profile.artists.filter { $0.kind == "ensemble" }.map(\.id),
                    venueIDs: profile.venues.map(\.id),
                    token: token
                )
            }
        }
    }
}

// MARK: - Bausteine

private enum TasteStyle {
    static let weekdayShort = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    static let weekdayNames = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]

    static func favoriteDay(_ profile: TasteProfile?) -> String? {
        guard let best = profile?.weekdays.max(by: { $0.value < $1.value })?.key, (1...7).contains(best) else { return nil }
        return weekdayNames[best - 1]
    }
}

private struct TasteTile: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 22, style: .continuous))
    }
}

private extension View {
    func tasteTile() -> some View { modifier(TasteTile()) }
}

private struct TasteLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).tracking(1.1).foregroundStyle(.secondary)
    }
}

/// Titelkarte im Stil von "Dein Konzertjahr".
private struct TasteHero: View {
    let profile: TasteProfile?

    private var headline: String {
        guard let top = profile?.composers.first?.name ?? profile?.artists.first?.name else { return "Noch ganz am Anfang" }
        if let day = TasteStyle.favoriteDay(profile) { return "Viel \(top), gern am \(day)" }
        return "Viel \(top)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Dein Geschmack").font(.system(.title3, design: .serif).italic())
                Spacer()
                Image(systemName: "waveform").font(.headline).opacity(0.75)
            }
            Text(headline)
                .font(.system(size: 34, weight: .bold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
            if let profile, !profile.isEmpty {
                HStack(spacing: 0) {
                    stat("\(profile.signalCount)", profile.signalCount == 1 ? "Signal" : "Signale")
                    divider
                    stat("\(profile.composers.count)", "Komponist:innen")
                    divider
                    stat("\(profile.artists.count)", "Künstler:innen")
                }
            } else {
                Text("Merke dir ein paar Konzerte, folge Künstler:innen oder bewerte, was du gehört hast – dann entsteht hier dein Profil.")
                    .font(.subheadline)
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
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

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title2.bold().monospacedDigit())
            Text(label).font(.caption).opacity(0.75).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Neu gestaltet 30.10.2026 (Nutzerwunsch): jede Zeile führt jetzt zur
/// Person/zum Ensemble/zur Spielstätte, Anteile statt nackter Balken.
private func tasteRoute(_ entry: TasteProfile.Entry, fallback: EntityKind) -> EntityRoute {
    let kind = entry.kind.flatMap(EntityKind.init(rawValue:)) ?? fallback
    return EntityRoute(kind: kind, identifier: entry.id.uuidString.lowercased())
}

/// Ziel-Links statt NavigationLink(value:): Die Geschmack-Seite wird per
/// Ziel-Link geöffnet; wertbasierte Links darin lösten erst nach "Zurück"
/// aus (bekanntes SwiftUI-Problem beim Mischen beider Arten).
private struct TasteLink<Label: View>: View {
    let entry: TasteProfile.Entry
    let fallback: EntityKind
    let contentRepository: any ContentRepository
    @ViewBuilder let label: () -> Label

    var body: some View {
        NavigationLink {
            EntityDetailView(route: tasteRoute(entry, fallback: fallback), repository: contentRepository)
        } label: { label() }
        .buttonStyle(.plain)
    }
}

private struct TasteInitials: View {
    let name: String
    var highlighted = false
    var size: CGFloat = 44
    var imageURL: URL? = nil

    private var initials: String {
        let parts = name.split(separator: " ").filter { $0.first?.isUppercase == true }
        return String((parts.first?.prefix(1) ?? "") + (parts.count > 1 ? parts.last!.prefix(1) : ""))
    }

    var body: some View {
        let placeholder = Text(initials)
            .font(.system(size: size * 0.36, weight: .semibold, design: .serif))
            .foregroundStyle(highlighted ? .white : KlangradarTheme.accent)
            .frame(width: size, height: size)
            .background(highlighted ? AnyShapeStyle(KlangradarTheme.accent) : AnyShapeStyle(KlangradarTheme.accent.opacity(0.12)), in: .circle)
        if let imageURL {
            CachedAsyncImage(url: imageURL, maxPixel: 240) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(.circle)
            .overlay(Circle().stroke(highlighted ? KlangradarTheme.accent : .clear, lineWidth: 2))
        } else {
            placeholder
        }
    }
}

/// Komponist:innen als Rangliste mit Anteil am Geschmack.
private struct TasteComposerTile: View {
    let entries: [TasteProfile.Entry]
    let thumbnails: [UUID: URL]
    let contentRepository: any ContentRepository

    var body: some View {
        let total = max(entries.map(\.weight).reduce(0, +), 0.0001)
        let maxWeight = max(entries.map(\.weight).max() ?? 1, 0.0001)
        VStack(alignment: .leading, spacing: 12) {
            TasteLabel(text: "Komponist:innen")
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider().padding(.leading, 56) }
                    TasteLink(entry: entry, fallback: .person, contentRepository: contentRepository) {
                        HStack(spacing: 12) {
                            TasteInitials(name: entry.name, highlighted: index == 0, imageURL: thumbnails[entry.id])
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.name)
                                    .font(index == 0 ? .system(.headline, design: .serif) : .subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                GeometryReader { proxy in
                                    Capsule().fill(KlangradarTheme.accent.opacity(index == 0 ? 0.8 : 0.3))
                                        .frame(width: max(6, proxy.size.width * entry.weight / maxWeight))
                                }
                                .frame(height: 5)
                            }
                            Text("\(Int((entry.weight / total * 100).rounded())) %")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 8)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .tasteTile()
    }
}

/// Künstler:innen und Ensembles als Porträtreihe zum Wischen.
private struct TasteArtistsTile: View {
    let entries: [TasteProfile.Entry]
    let thumbnails: [UUID: URL]
    let contentRepository: any ContentRepository

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TasteLabel(text: "Künstler:innen & Ensembles")
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        TasteLink(entry: entry, fallback: .person, contentRepository: contentRepository) {
                            VStack(spacing: 6) {
                                TasteInitials(name: entry.name, highlighted: index == 0, size: 60, imageURL: thumbnails[entry.id])
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: entry.kind == "ensemble" ? "person.3.fill" : "person.fill")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(KlangradarTheme.accent)
                                            .padding(5)
                                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .circle)
                                    }
                                Text(entry.name)
                                    .font(.caption.weight(index == 0 ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(width: 76)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .tasteTile()
    }
}

/// Lieblingsorte als kurze Rangliste.
private struct TasteVenuesTile: View {
    let entries: [TasteProfile.Entry]
    let thumbnails: [UUID: URL]
    let contentRepository: any ContentRepository

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TasteLabel(text: "Lieblingsorte")
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                TasteLink(entry: entry, fallback: .venue, contentRepository: contentRepository) {
                    HStack(spacing: 10) {
                        TasteInitials(name: entry.name, highlighted: index == 0, size: 34, imageURL: thumbnails[entry.id])
                        Text(entry.name)
                            .font(.subheadline.weight(index == 0 ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .tasteTile()
    }
}

/// Wochentage als kleine Balken, dazu die bevorzugte Tageszeit.
private struct TasteWeekdayTile: View {
    let profile: TasteProfile

    var body: some View {
        let maxValue = max(profile.weekdays.values.max() ?? 1, 0.1)
        VStack(alignment: .leading, spacing: 12) {
            TasteLabel(text: "Wann du gehst")
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(1...7, id: \.self) { day in
                    let value = max(profile.weekdays[day] ?? 0, 0)
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(value == maxValue ? AnyShapeStyle(KlangradarTheme.accent) : AnyShapeStyle(KlangradarTheme.accent.opacity(value > 0 ? 0.3 : 0.1)))
                            .frame(height: 6 + 54 * value / maxValue)
                        Text(TasteStyle.weekdayShort[day - 1])
                            .font(.caption2.weight(value == maxValue ? .bold : .regular))
                            .foregroundStyle(value == maxValue ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 80, alignment: .bottom)
            if let band = profile.bands.max(by: { $0.value < $1.value })?.key {
                Text(band == "tag" ? "Meist tagsüber – Matineen liegen dir." : band == "vorabend" ? "Meist am frühen Abend." : "Meist abends ab 19 Uhr.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tasteTile()
    }
}
