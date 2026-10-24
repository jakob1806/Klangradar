// Erstellt von Claude Code (Nutzerwunsch 24.10.2026, Punkte 5+6).
import SwiftUI

/// "Dein Geschmack": was Klangradar aus Merken, Hingehen, Bewertungen und
/// Folgen gelernt hat – transparent, damit Empfehlungen nachvollziehbar sind.
struct TasteProfileView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository

    @State private var profile: TasteProfile?
    @State private var isLoading = true

    private let weekdayNames = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DEIN GESCHMACK").font(.footnote.weight(.semibold)).tracking(1.2).foregroundStyle(KlangradarTheme.accent)
                    Text(headline).font(.system(size: 32, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                }
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if let profile, !profile.isEmpty {
                    if !profile.composers.isEmpty { weighted("Komponist:innen", profile.composers.prefix(6)) }
                    if !profile.artists.isEmpty { chips("Künstler:innen & Ensembles", profile.artists.prefix(10)) }
                    if !profile.venues.isEmpty { weighted("Lieblingsorte", profile.venues.prefix(4)) }
                    if !profile.weekdays.isEmpty { rhythm(profile) }
                    Text("Entsteht aus dem, was du merkst, besuchst, bewertest und wem du folgst. Empfehlungen zeigen dazu eine kurze Begründung – und ab und zu bewusst etwas Neues.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Merke dir ein paar Konzerte, folge Künstler:innen oder bewerte, was du gehört hast – dann entsteht hier dein Profil.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, KlangradarTheme.pagePadding)
            .padding(.vertical, 16)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let token = auth.accessToken { profile = try? await repository.tasteProfile(token: token) }
            isLoading = false
        }
    }

    private var headline: String {
        guard let top = profile?.composers.first?.name ?? profile?.artists.first?.name else { return "Noch ganz am Anfang" }
        return "Viel \(top), gern am \(favoriteDay ?? "Abend")"
    }

    private var favoriteDay: String? {
        guard let best = profile?.weekdays.max(by: { $0.value < $1.value })?.key, (1...7).contains(best) else { return nil }
        return ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"][best - 1]
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.headline)
    }

    private func weighted<S: Sequence>(_ title: String, _ entries: S) -> some View where S.Element == TasteProfile.Entry {
        let list = Array(entries)
        let maxWeight = list.map(\.weight).max() ?? 1
        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle(title)
            ForEach(list) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.name).font(.subheadline)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(uiColor: .tertiarySystemFill))
                            Capsule().fill(KlangradarTheme.accent).frame(width: max(6, proxy.size.width * entry.weight / maxWeight))
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
    }

    private func chips<S: Sequence>(_ title: String, _ entries: S) -> some View where S.Element == TasteProfile.Entry {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(title)
            FlowLayout(spacing: 8) {
                ForEach(Array(entries)) { entry in
                    Text(entry.name)
                        .font(.subheadline)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .overlay(Capsule().stroke(KlangradarTheme.accent.opacity(0.35), lineWidth: 1))
                }
            }
        }
    }

    private func rhythm(_ profile: TasteProfile) -> some View {
        let maxValue = max(profile.weekdays.values.max() ?? 1, 0.1)
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Wann du gehst")
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(1...7, id: \.self) { day in
                    let value = max(profile.weekdays[day] ?? 0, 0)
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(value == maxValue ? KlangradarTheme.accent : KlangradarTheme.accent.opacity(0.25))
                            .frame(height: 8 + 64 * value / maxValue)
                        Text(weekdayNames[day - 1]).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 96, alignment: .bottom)
            if let band = profile.bands.max(by: { $0.value < $1.value })?.key {
                Text(band == "tag" ? "Meist tagsüber – Matineen liegen dir." : band == "vorabend" ? "Meist am frühen Abend." : "Meist abends ab 19 Uhr.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
