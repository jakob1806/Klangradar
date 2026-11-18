// Erstellt von Claude Code (18.11.2026): Konzert-Rückblick teilen – eine
// Bildkarte (Story-Format 9:16) mit Konzertbild, Titel, Datum, Ort und
// Programm, für Instagram, WhatsApp & Co.
import SwiftUI

struct ConcertRecapSheet: View {
    let event: ConcertEvent
    let program: String?
    @Environment(\.dismiss) private var dismiss
    @State private var rendered: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let rendered {
                    Image(uiImage: rendered).resizable().scaledToFit()
                        .clipShape(.rect(cornerRadius: 18, style: .continuous))
                        .shadow(radius: 12, y: 6)
                        .padding(.horizontal, 40)
                    ShareLink(item: Image(uiImage: rendered), preview: SharePreview(event.title, image: Image(uiImage: rendered))) {
                        Label("Rückblick teilen", systemImage: "square.and.arrow.up")
                            .font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                            .foregroundStyle(.white)
                            .background(KlangradarTheme.accent, in: .capsule)
                    }
                    .padding(.horizontal, 24)
                } else {
                    ProgressView("Karte wird erstellt …")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Konzert-Rückblick")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
            .task { await render() }
        }
    }

    @MainActor private func render() async {
        var photo: UIImage?
        if let url = event.primaryImageURL ?? event.imageUrls?.first.flatMap(URL.init(string:)),
           let (data, _) = try? await URLSession.shared.data(from: url) {
            photo = UIImage(data: data)
        }
        let card = ConcertRecapCard(event: event, program: program, photo: photo)
            .frame(width: 360, height: 640)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        rendered = renderer.uiImage
    }
}

private struct ConcertRecapCard: View {
    let event: ConcertEvent
    let program: String?
    let photo: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.07, green: 0.08, blue: 0.14)
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
                    .frame(width: 360, height: 640).clipped()
            }
            LinearGradient(colors: [.clear, .black.opacity(0.25), .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                Text("ICH WAR DABEI").font(.system(size: 12, weight: .bold)).tracking(2).foregroundStyle(.white.opacity(0.8))
                Text(event.title)
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(4)
                    .minimumScaleFactor(0.6)
                if let program, !program.isEmpty {
                    Text(program.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(1).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                }
                Text([event.startDate.map { KlangradarDateTime.string($0, format: "d. MMMM yyyy") }, event.venues?.name].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                HStack(spacing: 6) {
                    KlangradarMark(stem: .white).frame(width: 14, height: 17)
                    Text("Klangradar").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                }
                .padding(.top, 12)
            }
            .padding(28)
        }
        .frame(width: 360, height: 640)
    }
}
