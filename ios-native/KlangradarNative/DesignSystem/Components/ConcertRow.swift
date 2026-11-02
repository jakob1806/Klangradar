import SwiftUI

/// Einheitliche Konzertzeile (02.11.2026) für Kalender, Suche, Favoriten,
/// Listen, Sammlungen, Spielstätten und Karten-Sheet – vorher 8 eigene
/// Varianten. Aufbau wie System-Apps (Kalender/Mail): Datum links, Bild,
/// drei Textzeilen, Herz rechts, langes Drücken für Merken/Teilen.
struct ConcertRow: View {
    enum Leading { case date, time, none }

    let event: ConcertEvent
    var leading: Leading = .date
    var showsFavorite = true
    /// 0 in Systemlisten (List rückt selbst ein), sonst 14.
    var horizontalPadding: CGFloat = 14
    @EnvironmentObject private var favorites: FavoriteStore
    @ScaledMetric(relativeTo: .body) private var artworkSize: CGFloat = 56

    private var isFavorite: Bool { favorites.ids.contains(event.id) }
    private var isCancelled: Bool { ["cancelled", "canceled", "abgesagt"].contains(event.status ?? "") }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leadingColumn
            EventArtwork(event: event)
                .frame(width: artworkSize, height: artworkSize)
                .clipped()
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .strikethrough(isCancelled)
                Text(secondLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let third = thirdLine {
                    Text(third)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if isCancelled {
                    Text("Abgesagt")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsFavorite {
                Button {
                    Task { await favorites.toggle(event.id) }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.body)
                        .foregroundStyle(isFavorite ? KlangradarTheme.accent : Color.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? "Nicht mehr merken" : "Merken")
            }
        }
        .padding(.vertical, 10)
        .padding(.leading, horizontalPadding)
        .padding(.trailing, showsFavorite ? max(horizontalPadding - 10, 0) : horizontalPadding)
        .contentShape(.rect)
        .contextMenu {
            Button(isFavorite ? "Nicht mehr merken" : "Merken", systemImage: isFavorite ? "heart.slash" : "heart") {
                Task { await favorites.toggle(event.id) }
            }
            ShareLink(item: event.shareURL, subject: Text(event.title), message: Text("\(event.title) · \(event.dateLine)")) {
                Label("Teilen", systemImage: "square.and.arrow.up")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var leadingColumn: some View {
        switch leading {
        case .date:
            VStack(spacing: 0) {
                Text(event.startDate.map { KlangradarDateTime.string($0, format: "EEE") } ?? "")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(isCancelled ? Color.secondary : KlangradarTheme.accent)
                Text(event.startDate.map { KlangradarDateTime.string($0, format: "d") } ?? "–")
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text(event.startDate.map { KlangradarDateTime.string($0, format: "MMM") } ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 38)
        case .time:
            Text(event.startDate.map { KlangradarDateTime.string($0, format: "HH:mm") } ?? "–")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(KlangradarTheme.accent)
                .frame(minWidth: 44, alignment: .leading)
        case .none:
            EmptyView()
        }
    }

    /// Ort · Uhrzeit (bei Zeit-Spalte nur der Ort).
    private var secondLine: String {
        let time = event.startDate.map { KlangradarDateTime.string($0, format: "HH:mm") }
        return [event.venueName, leading == .time ? nil : time].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Wer spielt (bis zu zwei Namen) · Preis – nur wenn vorhanden.
    private var thirdLine: String? {
        let names = (event.eventParticipants ?? [])
            .compactMap { $0.persons?.name ?? $0.ensembles?.name }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .prefix(2)
        let parts = [names.isEmpty ? nil : names.joined(separator: ", "), event.priceLabel].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Gruppierter Hintergrund für eine Liste aus ConcertRows, wie
/// `.insetGrouped` in Systemlisten – mit eingerückten Trennlinien.
struct ConcertRowList<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let items: Data
    @ViewBuilder let row: (Data.Element) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item)
                if index < items.count - 1 {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
    }
}
