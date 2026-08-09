import SwiftUI

struct EventCard: View {
    let event: ConcertEvent
    @EnvironmentObject private var favorites: FavoriteStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EventArtwork(event: event)
                .frame(width: 196, height: 110)
                .clipped()
                .clipShape(.rect(cornerRadius: 18))
                .overlay(alignment: .topTrailing) {
                    GlassIconButton(
                        systemImage: favorites.ids.contains(event.id) ? "heart.fill" : "heart",
                        accessibilityLabel: "Zu Favoriten hinzufügen"
                    ) { Task { await favorites.toggle(event.id) } }
                    .padding(8)
                }

            // Nutzerfeedback: zu viel Abstand zwischen Konzertname und
            // Tag/Uhrzeit/Ort darunter — Ursache war eine feste 42pt-Box für
            // den Titel (für 2-zeilige Titel reserviert), die bei kurzen,
            // einzeiligen Titeln als sichtbare Lücke vor der Datumszeile
            // übrig blieb. Die äußere feste Kartenhöhe (192pt) sorgt
            // bereits für gleich hohe Karten im Rail, die feste Titel-Box
            // war dafür nicht nötig — engerer, eigener Abstand (4pt) statt
            // der geerbten 10pt-VStack-Lücke.
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(event.dateLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 196, height: 192, alignment: .topLeading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
