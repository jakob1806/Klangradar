// Erstellt von Claude Code (Nutzerwunsch 24.10.2026, Punkt 3).
import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers

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

    /// Bild aus Foto-Datei oder erster PDF-Seite (in hoher Auflösung, damit
    /// QR-/Barcodes am Einlass scanbar bleiben).
    static func image(from url: URL) -> UIImage? {
        if url.pathExtension.lowercased() == "pdf" || UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
            guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let scale = 2400 / max(bounds.width, bounds.height)
            return page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}
