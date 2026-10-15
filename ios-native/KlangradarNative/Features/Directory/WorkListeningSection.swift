import AVFoundation
import SwiftUI

/// Werkseite: 30-Sekunden-Hörprobe (öffentliche iTunes-Suche, braucht weder
/// MusicKit-Berechtigung noch Apple-Music-Abo) und eine kurze Einführung der
/// Klangradar KI auf Abruf. Die nächsten Aufführungen zeigt die Werkseite
/// bereits über `linkedEvents`.
struct WorkListeningSection: View {
    let title: String
    let composer: String?

    @EnvironmentObject private var follows: FollowStore
    @State private var preview: MusicPreview?
    @State private var didSearch = false
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var introduction: String?
    @State private var isLoadingIntroduction = false
    @State private var introductionError: String?
    @State private var showsPlusPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reinhören & verstehen").font(.title2.bold())
            if let preview { previewCard(preview) }
            introductionCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await searchPreview() }
        .onDisappear { stop() }
        .sheet(isPresented: $showsPlusPaywall) {
            PlusPaywallView(reason: "Du hast diese Woche deine \(CoachQuota.weeklyLimit) kostenlosen Fragen an die Klangradar KI genutzt. Mit Plus fragst du ohne Limit.")
        }
    }

    // MARK: Hörprobe

    private func previewCard(_ preview: MusicPreview) -> some View {
        LiquidGlassSurface(cornerRadius: 22) {
            HStack(spacing: 14) {
                AsyncImage(url: preview.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.12).overlay { Image(systemName: "music.note") }
                }
                .frame(width: 58, height: 58)
                .clipShape(.rect(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Hörprobe").font(.caption.bold()).foregroundStyle(KlangradarTheme.accent)
                    Text(preview.trackName).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(preview.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let storeURL = preview.storeURL {
                        Link("In Apple Music öffnen", destination: storeURL).font(.caption)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    Haptics.light()
                    isPlaying ? stop() : play(preview)
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(KlangradarTheme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Hörprobe anhalten" : "Hörprobe abspielen")
            }
            .padding(14)
        }
    }

    private func play(_ preview: MusicPreview) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let player = AVPlayer(url: preview.previewURL)
        self.player = player
        player.play()
        isPlaying = true
        // Vorschauen sind 30 s lang; danach Button zurücksetzen.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(31))
            if self.player === player { stop() }
        }
    }

    private func stop() {
        player?.pause()
        player = nil
        isPlaying = false
    }

    private func searchPreview() async {
        guard !didSearch else { return }
        didSearch = true
        preview = await MusicPreview.search(title: title, composer: composer)
    }

    // MARK: KI-Einführung

    @ViewBuilder private var introductionCard: some View {
        LiquidGlassSurface(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Kurz erklärt", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KlangradarTheme.accent)
                if let introduction {
                    Text(introduction).font(.subheadline).lineSpacing(3)
                    Text("Von der Klangradar KI erstellt, kann Fehler enthalten.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else if isLoadingIntroduction {
                    ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Worum geht es, worauf lohnt es sich zu achten? Die Klangradar KI erklärt das Werk in wenigen Sätzen.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let introductionError {
                        Text(introductionError).font(.caption).foregroundStyle(.red)
                    }
                    Button(follows.isSignedIn ? "Einführung anzeigen" : "Anmelden für die Einführung") {
                        Task { await loadIntroduction() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(KlangradarTheme.accent)
                    .disabled(!follows.isSignedIn)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadIntroduction() async {
        if PlusStore.shared.enforcesLimits && CoachQuota.remaining == 0 {
            showsPlusPaywall = true
            return
        }
        isLoadingIntroduction = true
        introductionError = nil
        defer { isLoadingIntroduction = false }
        let work = [composer, title].compactMap { $0 }.joined(separator: ": ")
        let prompt = """
        Erkläre mir das Werk „\(work)“ in höchstens fünf Sätzen für jemanden, der es zum ersten Mal im Konzert hört: \
        Entstehung, Charakter, worauf man beim Hören achten kann. Keine Konzertempfehlungen, keine Aufzählung.
        """
        do {
            introduction = try await follows.askKlangradarAI(prompt)
            if introduction?.isEmpty ?? true { introductionError = "Keine Antwort erhalten. Bitte später erneut versuchen." }
        } catch {
            introductionError = "Die Einführung konnte nicht geladen werden."
        }
    }
}

/// Ein Treffer der öffentlichen iTunes Search API mit 30-s-Vorschau.
struct MusicPreview: Sendable {
    let trackName: String
    let artistName: String
    let previewURL: URL
    let artworkURL: URL?
    let storeURL: URL?

    private struct Response: Decodable {
        struct Item: Decodable {
            let trackName: String?
            let artistName: String?
            let collectionName: String?
            let previewUrl: String?
            let artworkUrl100: String?
            let trackViewUrl: String?
        }
        let results: [Item]
    }

    /// Deutsche Gattungsbegriffe auf die englischen Tracktitel der Labels abbilden.
    private static let translations: [(String, String)] = [
        ("sinfonie", "symphony"), ("symphonie", "symphony"), ("klavierkonzert", "piano concerto"),
        ("violinkonzert", "violin concerto"), ("cellokonzert", "cello concerto"), ("streichquartett", "string quartet"),
        ("klaviersonate", "piano sonata"), ("violinsonate", "violin sonata"), ("ouvertüre", "overture"),
        ("konzert", "concerto"), ("nr.", "no."), ("nr ", "no. ")
    ]

    static func normalized(_ text: String) -> String {
        var result = text.lowercased()
        for (german, english) in translations { result = result.replacingOccurrences(of: german, with: english) }
        return result
    }

    /// "no. 2", "op. 98", "bwv 244", "kv 620" aus dem Titel; alle müssen im Treffer vorkommen.
    static func catalogMarkers(in text: String) -> [String] {
        let pattern = /\b(no\.?|op\.?|bwv|kv|k\.|hob\.?|d\.?)\s*([0-9]+[a-z]?)\b/
        return normalized(text).matches(of: pattern).map { match in
            let prefix = String(match.output.1).replacingOccurrences(of: ".", with: "")
            return "\(prefix == "k" ? "kv" : prefix) \(match.output.2)"
        }
    }

    static func search(title: String, composer: String?) async -> MusicPreview? {
        let cleanTitle = title.cleanedWorkTitle
        let composerSurname = composer?.split(separator: " ").last.map(String.init)
        let term = [composerSurname, normalized(cleanTitle)].compactMap { $0 }.joined(separator: " ")
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "country", value: "DE"),
            URLQueryItem(name: "limit", value: "25")
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(Response.self, from: data)
        else { return nil }

        // Lieber keine Hörprobe als eine falsche: Komponist, Werknummern und
        // (ohne Nummern) mindestens ein Titelwort müssen im Treffer stehen.
        let markers = catalogMarkers(in: cleanTitle)
        let titleWords = normalized(cleanTitle).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).filter { $0.count > 3 }
        let match = response.results.first { item in
            guard item.previewUrl != nil else { return false }
            let haystack = normalized([item.trackName, item.collectionName, item.artistName].compactMap { $0 }.joined(separator: " "))
            let hasComposer = composerSurname.map { haystack.contains($0.lowercased()) } ?? true
            let itemMarkers = Set(catalogMarkers(in: haystack))
            let hasTitle = markers.isEmpty
                ? (titleWords.isEmpty || titleWords.contains { haystack.contains($0) })
                : markers.allSatisfy { itemMarkers.contains($0) }
            return hasComposer && hasTitle
        }
        guard let match, let preview = match.previewUrl.flatMap(URL.init(string:)) else { return nil }
        return MusicPreview(
            trackName: match.trackName ?? cleanTitle,
            artistName: match.artistName ?? "",
            previewURL: preview,
            artworkURL: match.artworkUrl100.flatMap(URL.init(string:)),
            storeURL: match.trackViewUrl.flatMap(URL.init(string:))
        )
    }
}
