// Erstellt von Claude Code (Nutzerwunsch 24.10.2026, Punkte 10+11).
import SwiftUI

/// "In 3 Minuten vorbereitet": je Werk Werkeinführung (KI aus Wikipedia,
/// Edge Function work-introduction) und Reinhören über Apple Music/Spotify
/// (Suche, kein Konto nötig).
struct PrepareSection: View {
    let event: ConcertEvent
    let detail: JSONObject

    @State private var introWork: WorkRef?

    struct WorkRef: Identifiable, Hashable {
        let id: UUID
        let title: String
        let composer: String?
        let movements: [String]
    }

    private var works: [WorkRef] {
        detail.objects("event_works")
            .sorted { ($0.integer("position") ?? 0) < ($1.integer("position") ?? 0) }
            .compactMap { link in
                guard let work = link.object("works"), let title = work.string("title"),
                      let id = work.string("id").flatMap(UUID.init(uuidString:)) else { return nil }
                var movements: [String] = []
                if case let .array(items)? = work["movements"] {
                    movements = items.compactMap { if case let .string(text) = $0 { text } else { nil } }
                }
                return WorkRef(id: id, title: title, composer: work.object("composer")?.string("full_name"), movements: movements)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !works.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("In 3 Minuten vorbereitet").font(.title2.bold())
                        Text("Einführung lesen und reinhören").font(.subheadline).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(works.enumerated()), id: \.element.id) { index, work in
                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(work.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Text([work.composer, work.movements.count > 1 ? "\(work.movements.count) Sätze" : nil].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                HStack(spacing: 8) {
                                    Button { introWork = work } label: {
                                        Label("Werkeinführung", systemImage: "text.book.closed")
                                            .font(.footnote.weight(.semibold))
                                            .padding(.horizontal, 12).padding(.vertical, 8)
                                            .foregroundStyle(KlangradarTheme.accent)
                                            .background(KlangradarTheme.accent.opacity(0.1), in: .capsule)
                                    }
                                    .buttonStyle(.plain)
                                    Spacer(minLength: 0)
                                    if let url = searchURL(apple: true, work) {
                                        Link(destination: url) { AppleMusicLogo().frame(width: 34, height: 34) }
                                            .accessibilityLabel("In Apple Music anhören")
                                    }
                                    if let url = searchURL(apple: false, work) {
                                        Link(destination: url) { SpotifyLogo().frame(width: 34, height: 34) }
                                            .accessibilityLabel("In Spotify anhören")
                                    }
                                }
                            }
                            .padding(.vertical, 14)
                            if index < works.count - 1 { Divider() }
                        }
                    }
                }
            }
        }
        .sheet(item: $introWork) { work in
            WorkIntroductionSheet(work: work)
                .presentationDetents([.medium, .large])
        }
    }

    private func searchURL(apple: Bool, _ work: WorkRef) -> URL? {
        let term = [work.composer, work.title].compactMap { $0 }.joined(separator: " ")
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: apple ? "https://music.apple.com/de/search?term=\(encoded)" : "https://open.spotify.com/search/\(encoded)")
    }
}

/// Programmheft des Veranstalters, falls online verfügbar (ganz unten auf
/// der Konzertseite).
struct ProgramBookletLink: View {
    let event: ConcertEvent
    @State private var bookletURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            if let bookletURL {
                Link(destination: bookletURL) {
                    HStack(spacing: 14) {
                        Image(systemName: "book.pages")
                            .font(.title3).foregroundStyle(KlangradarTheme.accent)
                            .frame(width: 44, height: 44)
                            .background(KlangradarTheme.accent.opacity(0.1), in: .rect(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Programmheft").font(.headline).foregroundStyle(.primary)
                            Text("Vom Veranstalter, online lesen").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .task(id: event.id) {
            // Separat und fehlertolerant, damit die Detailseite nicht von der
            // neuen Spalte abhängt.
            guard let client = SocialStore.shared.repository?.client else { return }
            let rows: [JSONObject]? = try? await client.get(table: "events", queryItems: [
                URLQueryItem(name: "select", value: "program_booklet_url"),
                URLQueryItem(name: "id", value: "eq.\(event.id.uuidString)")
            ])
            bookletURL = rows?.first?.string("program_booklet_url").flatMap(URL.init(string:))
        }
    }
}

/// Einführung zu einem Werk; lädt sie bei Bedarf über die Edge Function.
private struct WorkIntroductionSheet: View {
    let work: PrepareSection.WorkRef

    @State private var introduction: String?
    @State private var sourceURL: URL?
    @State private var movements: [String] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let composer = work.composer {
                            Text(composer.uppercased()).font(.caption.weight(.semibold)).tracking(1).foregroundStyle(KlangradarTheme.accent)
                        }
                        Text(work.title).font(.title2.bold())
                    }
                    if isLoading {
                        HStack(spacing: 10) { ProgressView(); Text("Einführung wird recherchiert …").foregroundStyle(.secondary) }
                    } else if let introduction {
                        Text(introduction).font(.body).lineSpacing(5)
                    } else {
                        Text("Zu diesem Werk haben wir noch keine verlässliche Einführung gefunden.").foregroundStyle(.secondary)
                    }
                    if movements.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sätze").font(.headline)
                            ForEach(Array(movements.enumerated()), id: \.offset) { _, movement in
                                Text(movement).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let sourceURL {
                        Link(destination: sourceURL) {
                            Label("Quelle: Wikipedia", systemImage: "link").font(.footnote)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Werkeinführung")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await load() }
    }

    private func load() async {
        movements = work.movements
        defer { isLoading = false }
        guard let client = SocialStore.shared.repository?.client else { return }
        let rows: [JSONObject]? = try? await client.get(table: "works", queryItems: [
            URLQueryItem(name: "select", value: "introduction_de,introduction_source_url,movements"),
            URLQueryItem(name: "id", value: "eq.\(work.id.uuidString)")
        ])
        if let row = rows?.first, let text = row.string("introduction_de"), !text.isEmpty {
            apply(row)
            return
        }
        guard let token = SocialStore.shared.token else { return }
        if let row: JSONObject = try? await client.edgeFunction("work-introduction", body: ["work_id": .string(work.id.uuidString)], accessToken: token) {
            if let text = row.string("introduction") { introduction = text }
            if let source = row.string("sourceUrl") { sourceURL = URL(string: source) }
            if case let .array(items)? = row["movements"] {
                let list = items.compactMap { if case let .string(text) = $0 { text } else { nil } }
                if list.count > 1 { movements = list }
            }
        }
    }

    private func apply(_ row: JSONObject) {
        introduction = row.string("introduction_de")
        sourceURL = row.string("introduction_source_url").flatMap(URL.init(string:))
        if case let .array(items)? = row["movements"] {
            let list = items.compactMap { if case let .string(text) = $0 { text } else { nil } }
            if list.count > 1 { movements = list }
        }
    }
}

/// Apple-Music-App-Symbol nachgebaut (rot-pinker Verlauf, weiße Note), damit
/// keine fremde Bilddatei eingebunden werden muss.
struct AppleMusicLogo: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.36, blue: 0.47), Color(red: 0.98, green: 0.14, blue: 0.24)], startPoint: .top, endPoint: .bottom))
            .overlay { Image(systemName: "music.note").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white) }
    }
}

/// Spotify-Symbol: grüner Kreis mit drei schwarzen Bögen.
struct SpotifyLogo: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(Color(red: 0.118, green: 0.843, blue: 0.376))
                ForEach(0..<3, id: \.self) { index in
                    SpotifyArc(index: index)
                        .stroke(Color.black, style: StrokeStyle(lineWidth: size * [0.105, 0.085, 0.07][index], lineCap: .round))
                }
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct SpotifyArc: Shape {
    let index: Int
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let widths: [CGFloat] = [0.62, 0.52, 0.42]
        let ys: [CGFloat] = [0.36, 0.52, 0.66]
        let half = w * widths[index] / 2
        let y = rect.minY + w * ys[index]
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - half, y: y))
        path.addQuadCurve(to: CGPoint(x: rect.midX + half, y: y + w * 0.04), control: CGPoint(x: rect.midX, y: y - w * 0.11))
        return path
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
