// Erstellt von Claude Code (Nutzerwunsch 24.10.2026, Punkt 3).
import Foundation
import UIKit

/// Ticket (Foto/Screenshot/PDF-Seite) pro Konzert, nur lokal auf dem Gerät
/// im App-Group-Container — nichts geht an den Server.
enum TicketStore {
    private static var folder: URL? {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedConcertStore.appGroup)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let url = base?.appendingPathComponent("Tickets", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func url(for eventID: UUID) -> URL? {
        folder?.appendingPathComponent("\(eventID.uuidString.lowercased()).jpg")
    }

    static func image(for eventID: UUID) -> UIImage? {
        guard let url = url(for: eventID), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func save(_ image: UIImage, for eventID: UUID) {
        guard let url = url(for: eventID), let data = image.jpegData(compressionQuality: 0.9) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    static func remove(for eventID: UUID) {
        guard let url = url(for: eventID) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
