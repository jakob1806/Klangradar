// Erstellt von Claude Code (Nutzerwunsch 24.10.2026, Punkte 10+11).
import SwiftUI

/// "In 3 Minuten vorbereitet": Werke zum Reinhören (Apple Music/Spotify
/// über die Suche, keine Konto-Anbindung nötig) und kurze Hinweise für
/// Einsteiger:innen. Flach, ohne Karte-in-Karte.
struct PrepareSection: View {
    let detail: JSONObject

    @State private var showsTips = false

    private var works: [(title: String, composer: String?, movements: Int?)] {
        detail.objects("event_works")
            .sorted { ($0.integer("position") ?? 0) < ($1.integer("position") ?? 0) }
            .compactMap { link in
                guard let work = link.object("works"), let title = work.string("title") else { return nil }
                let movements: Int? = {
                    if let count = work.integer("movements") { return count }
                    if case let .array(items)? = work["movements"] { return items.count }
                    return nil
                }()
                return (title, work.object("composer")?.string("full_name"), movements)
            }
    }

    var body: some View {
        if !works.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("In 3 Minuten vorbereitet").font(.title2.bold())
                    Text("Reinhören, bevor es losgeht").font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    ForEach(Array(works.enumerated()), id: \.offset) { index, work in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(work.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text([work.composer, work.movements.map { $0 == 1 ? "1 Satz" : "\($0) Sätze" }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            listenLink("Apple Music", symbol: "applelogo", url: searchURL(apple: true, work))
                            listenLink("Spotify", symbol: "dot.radiowaves.left.and.right", url: searchURL(apple: false, work))
                        }
                        .padding(.vertical, 12)
                        if index < works.count - 1 { Divider() }
                    }
                }
                DisclosureGroup(isExpanded: $showsTips.animation(.snappy)) {
                    VStack(alignment: .leading, spacing: 10) {
                        tip("hands.clap", "Applaus erst nach dem letzten Satz eines Werks – im Zweifel kurz abwarten, bis andere klatschen.")
                        tip("iphone.slash", "Handy lautlos, auch keine Vibration – im Saal hört man alles.")
                        tip("tshirt", "Kein Dresscode: von Jeans bis Abendkleid ist alles normal.")
                        tip("clock", "Wer zu spät kommt, wird oft erst in einer Pause eingelassen.")
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Zum ersten Mal im Konzert?").font(.subheadline.weight(.semibold)).foregroundStyle(KlangradarTheme.accent)
                }
                .tint(KlangradarTheme.accent)
            }
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(KlangradarTheme.accent).frame(width: 22)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func listenLink(_ label: String, symbol: String, url: URL?) -> some View {
        Group {
            if let url {
                Link(destination: url) {
                    Image(systemName: symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KlangradarTheme.accent)
                        .frame(width: 36, height: 36)
                        .background(KlangradarTheme.accent.opacity(0.1), in: .circle)
                }
                .accessibilityLabel("Auf \(label) anhören")
            }
        }
    }

    private func searchURL(apple: Bool, _ work: (title: String, composer: String?, movements: Int?)) -> URL? {
        let term = [work.composer, work.title].compactMap { $0 }.joined(separator: " ")
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: apple ? "https://music.apple.com/de/search?term=\(encoded)" : "https://open.spotify.com/search/\(encoded)")
    }
}

/// Punkt 10: Freunde, deren Geschmack zu diesem Konzert passt.
struct FriendTasteRow: View {
    let event: ConcertEvent
    @State private var matches: [FriendTasteMatch] = []
    @State private var showsComposer = false

    var body: some View {
        VStack(spacing: 0) {
        if !matches.isEmpty {
            Button { showsComposer = true } label: {
                HStack(spacing: 12) {
                    AvatarStack(people: matches.map(\.person), size: 30, limit: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                        Text("Frag, ob sie mitkommen").font(.caption).foregroundStyle(KlangradarTheme.accent)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showsComposer) {
                NavigationStack { PlanComposerView(event: event, quickAsk: true) }
            }
        }
        }
        .task {
                guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
                matches = (try? await repository.friendTaste(eventID: event.id, token: token)) ?? []
            }
    }

    private var headline: String {
        guard let first = matches.first else { return "" }
        let name = first.person.name.split(separator: " ").first.map(String.init) ?? first.person.name
        return matches.count == 1 ? "\(name) \(first.reason)" : "\(name) \(first.reason) – und \(matches.count - 1) weitere"
    }
}
