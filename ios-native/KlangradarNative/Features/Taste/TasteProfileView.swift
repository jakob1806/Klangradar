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

    @State private var profile: TasteProfile?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    TasteHero(profile: profile)
                    if let profile, !profile.isEmpty {
                        if !profile.composers.isEmpty { TasteComposerTile(entries: Array(profile.composers.prefix(6))) }
                        if !profile.artists.isEmpty { TasteArtistsTile(entries: Array(profile.artists.prefix(10))) }
                        HStack(alignment: .top, spacing: 12) {
                            if !profile.venues.isEmpty { TasteVenuesTile(entries: Array(profile.venues.prefix(4))) }
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

/// Komponist:innen: Nummer eins groß, danach Balken im Verhältnis.
private struct TasteComposerTile: View {
    let entries: [TasteProfile.Entry]

    var body: some View {
        let top = entries[0]
        let maxWeight = max(entries.map(\.weight).max() ?? 1, 0.0001)
        VStack(alignment: .leading, spacing: 14) {
            TasteLabel(text: "Am meisten gehört")
            Text(top.name)
                .font(.system(.title, design: .serif).weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if entries.count > 1 {
                VStack(spacing: 9) {
                    ForEach(entries.dropFirst()) { entry in
                        HStack(spacing: 10) {
                            Text(entry.name).font(.subheadline).lineLimit(1).minimumScaleFactor(0.85).frame(width: 165, alignment: .leading)
                            GeometryReader { proxy in
                                Capsule().fill(KlangradarTheme.accent.opacity(0.3))
                                    .frame(width: max(8, proxy.size.width * entry.weight / maxWeight))
                            }
                            .frame(height: 8)
                        }
                    }
                }
            }
        }
        .tasteTile()
    }
}

/// Künstler:innen und Ensembles als Kapseln mit kleinem Symbol.
private struct TasteArtistsTile: View {
    let entries: [TasteProfile.Entry]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TasteLabel(text: "Künstler:innen & Ensembles")
            FlowLayout(spacing: 8) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: 6) {
                        Image(systemName: entry.kind == "ensemble" ? "person.3.fill" : "person.fill")
                            .font(.caption2)
                            .foregroundStyle(index == 0 ? .white : KlangradarTheme.accent)
                        Text(entry.name).font(.subheadline.weight(index == 0 ? .semibold : .regular))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .foregroundStyle(index == 0 ? .white : .primary)
                    .background(index == 0 ? AnyShapeStyle(KlangradarTheme.accent) : AnyShapeStyle(KlangradarTheme.accent.opacity(0.1)), in: .capsule)
                }
            }
        }
        .tasteTile()
    }
}

/// Lieblingsorte als kurze Rangliste.
private struct TasteVenuesTile: View {
    let entries: [TasteProfile.Entry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TasteLabel(text: "Lieblingsorte")
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(.subheadline, design: .serif).weight(.bold))
                        .foregroundStyle(index == 0 ? KlangradarTheme.accent : .secondary)
                        .frame(width: 14, alignment: .leading)
                    Text(entry.name)
                        .font(.subheadline.weight(index == 0 ? .semibold : .regular))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
