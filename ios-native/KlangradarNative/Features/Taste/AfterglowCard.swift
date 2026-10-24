// Erstellt von Claude Code (Nutzerwunsch 24.10.2026, Punkt 4).
import SwiftUI

/// "Nachklang": nach dem Konzert direkt auf Home bewerten. Flach, weiß,
/// große Sterne. Die Bewertung fließt ins Geschmacksprofil ein.
struct AfterglowCard: View {
    let event: ConcertEvent
    let repository: UserRepository
    @ObservedObject var auth: AuthStore
    let onDone: () -> Void

    @State private var stars = 0
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                CachedAsyncImage(url: event.primaryImageURL, maxPixel: 200) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { Color.secondary.opacity(0.12) }
                }
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("NACHKLANG").font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(KlangradarTheme.accent)
                    Text(sent ? "Danke – wir merken uns das." : "Wie war's?").font(.headline)
                    Text(event.title).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        stars = value
                        Haptics.light()
                        Task { await send(value) }
                    } label: {
                        Image(systemName: value <= stars ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(value <= stars ? KlangradarTheme.accent : Color.secondary.opacity(0.5))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(value) von 5 Sternen")
                    .disabled(sent)
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 20, style: .continuous))
        .animation(.snappy, value: sent)
    }

    private func send(_ value: Int) async {
        guard let token = auth.accessToken else { return }
        try? await repository.rateEvent(event.id, stars: value, comment: nil, token: token)
        sent = true
        try? await Task.sleep(for: .seconds(1.6))
        onDone()
    }
}
