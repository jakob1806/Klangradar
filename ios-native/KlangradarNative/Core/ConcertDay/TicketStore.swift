// Erstellt von Claude Code (Nutzerwunsch 24.10.2026, Punkt 3).
import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers
import Vision
import CoreImage.CIFilterBuiltins

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
        if let codeURL = codeURL(for: eventID) { try? FileManager.default.removeItem(at: codeURL) }
    }

    // MARK: Ticket-Code (07.11.2026)

    /// Im Ticket erkannter Code (Inhalt + Format), damit die App ihn groß und
    /// gestochen scharf zeigen und in die Wallet-Karte übernehmen kann.
    struct TicketCode: Codable, Hashable, Sendable {
        var payload: String
        /// "qr", "aztec", "pdf417" oder "code128" (Wallet-Formate)
        var format: String
    }

    private static func codeURL(for eventID: UUID) -> URL? {
        folder?.appendingPathComponent("\(eventID.uuidString.lowercased()).code.json")
    }

    static func code(for eventID: UUID) -> TicketCode? {
        guard let url = codeURL(for: eventID), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TicketCode.self, from: data)
    }

    static func saveCode(_ code: TicketCode?, for eventID: UUID) {
        guard let url = codeURL(for: eventID) else { return }
        guard let code, let data = try? JSONEncoder().encode(code) else { try? FileManager.default.removeItem(at: url); return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Sucht QR/Aztec/PDF417/Code128 im Ticketbild (Vision, auf dem Gerät).
    static func detectCode(in image: UIImage) async -> TicketCode? {
        guard let cgImage = image.cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> TicketCode? in
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr, .aztec, .pdf417, .code128]
            try? VNImageRequestHandler(cgImage: cgImage).perform([request])
            guard let best = request.results?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }),
                  let payload = best.payloadStringValue, !payload.isEmpty else { return nil }
            let format: String
            switch best.symbology {
            case .aztec: format = "aztec"
            case .pdf417: format = "pdf417"
            case .code128: format = "code128"
            default: format = "qr"
            }
            return TicketCode(payload: payload, format: format)
        }.value
    }

    /// Code neu erzeugt (scharf, ohne Fotorauschen) für die Vollbildanzeige.
    static func render(_ code: TicketCode, scale: CGFloat = 12) -> UIImage? {
        let context = CIContext()
        let data = Data(code.payload.utf8)
        let output: CIImage?
        switch code.format {
        case "aztec": let f = CIFilter.aztecCodeGenerator(); f.message = data; output = f.outputImage
        case "pdf417": let f = CIFilter.pdf417BarcodeGenerator(); f.message = data; output = f.outputImage
        case "code128": let f = CIFilter.code128BarcodeGenerator(); f.message = data; output = f.outputImage
        default: let f = CIFilter.qrCodeGenerator(); f.message = data; f.correctionLevel = "M"; output = f.outputImage
        }
        guard let image = output?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
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
