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

    /// Alle erkannten Codes (mehrere Tickets in einem PDF → mehrere Codes).
    static func codes(for eventID: UUID) -> [TicketCode] {
        guard let url = codeURL(for: eventID), let data = try? Data(contentsOf: url) else { return [] }
        if let list = try? JSONDecoder().decode([TicketCode].self, from: data) { return list }
        if let single = try? JSONDecoder().decode(TicketCode.self, from: data) { return [single] }
        return []
    }

    static func code(for eventID: UUID) -> TicketCode? { codes(for: eventID).first }

    static func saveCodes(_ codes: [TicketCode], for eventID: UUID) {
        guard let url = codeURL(for: eventID) else { return }
        guard !codes.isEmpty, let data = try? JSONEncoder().encode(codes) else { try? FileManager.default.removeItem(at: url); return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    static func saveCode(_ code: TicketCode?, for eventID: UUID) {
        saveCodes(code.map { [$0] } ?? [], for: eventID)
    }

    /// Alle Seiten eines PDFs (oder das eine Bild) in hoher Auflösung.
    static func pages(from url: URL) -> [UIImage] {
        if url.pathExtension.lowercased() == "pdf" || UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
            guard let document = PDFDocument(url: url) else { return [] }
            return (0..<min(document.pageCount, 12)).compactMap { index in
                guard let page = document.page(at: index) else { return nil }
                let bounds = page.bounds(for: .mediaBox)
                let scale = 2400 / max(bounds.width, bounds.height)
                return page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            }
        }
        return image(from: url).map { [$0] } ?? []
    }

    /// Sucht in allen Bildern nach Codes, entfernt Doppelte und behält nur
    /// Codes, die die Probe gegen das Original bestehen.
    static func detectCodes(in images: [UIImage]) async -> [TicketCode] {
        var found: [TicketCode] = []
        for image in images {
            for code in await detectAll(in: image) where !found.contains(where: { $0.payload == code.payload }) {
                if await verify(code) { found.append(code) }
            }
        }
        return found
    }

    static func detectCode(in image: UIImage) async -> TicketCode? {
        await detectCodes(in: [image]).first
    }

    private static func detectAll(in image: UIImage) async -> [TicketCode] {
        guard let cgImage = image.cgImage else { return [] }
        return await Task.detached(priority: .userInitiated) { () -> [TicketCode] in
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr, .aztec, .pdf417, .code128]
            try? VNImageRequestHandler(cgImage: cgImage).perform([request])
            return (request.results ?? [])
                .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
                .compactMap { result -> TicketCode? in
                    guard let payload = result.payloadStringValue, !payload.isEmpty else { return nil }
                    let format: String
                    switch result.symbology {
                    case .aztec: format = "aztec"
                    case .pdf417: format = "pdf417"
                    case .code128: format = "code128"
                    default: format = "qr"
                    }
                    return TicketCode(payload: payload, format: format)
                }
        }.value
    }

    /// Probe: den neu gezeichneten Code wieder einlesen – nur wenn derselbe
    /// Inhalt herauskommt, wird er statt des Originals angezeigt.
    private static func verify(_ code: TicketCode) async -> Bool {
        guard let rendered = render(code, scale: 8) else { return false }
        let padded = UIGraphicsImageRenderer(size: CGSize(width: rendered.size.width + 80, height: rendered.size.height + 80)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: rendered.size.width + 80, height: rendered.size.height + 80)))
            rendered.draw(at: CGPoint(x: 40, y: 40))
        }
        guard let cgImage = padded.cgImage else { return false }
        return await Task.detached(priority: .userInitiated) { () -> Bool in
            let request = VNDetectBarcodesRequest()
            try? VNImageRequestHandler(cgImage: cgImage).perform([request])
            return request.results?.contains { $0.payloadStringValue == code.payload } ?? false
        }.value
    }

    /// Platz aus dem Ticket-Text lesen (08.11.2026): Eingang, Block/Rang,
    /// Reihe, Platz – per Texterkennung auf dem Gerät, alle Seiten.
    static func detectSeat(in images: [UIImage]) async -> ConcertSeat {
        var lines: [String] = []
        for image in images.prefix(6) {
            guard let cgImage = image.cgImage else { continue }
            let found: [String] = await Task.detached(priority: .userInitiated) {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["de-DE", "en-US"]
                request.usesLanguageCorrection = false
                try? VNImageRequestHandler(cgImage: cgImage).perform([request])
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            }.value
            lines += found
        }
        return parseSeat(lines.joined(separator: "\n"))
    }

    /// Erkennt typische Angaben deutscher Tickets (08.11.2026, erweitert):
    /// „Reihe 14“ in einer Zeile, Beschriftung und Wert in zwei Zeilen,
    /// Tabellen („Block  Reihe  Platz“ / „A  14  22“), „Reihe/Platz 14/22“,
    /// Kurzformen „Rh.“, „Pl.“, „R 14 P 22“, Ränge wie „2. Rang links“.
    static func parseSeat(_ text: String) -> ConcertSeat {
        var seat = ConcertSeat()
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        enum Field { case entrance, block, row, seat }
        func field(for label: String) -> Field? {
            let l = label.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if ["eingang", "einlass", "tor", "gate", "entrance", "zugang", "aufgang"].contains(l) { return .entrance }
            if ["block", "bereich", "sektor", "rang", "ebene", "kategorie block", "section"].contains(l) { return .block }
            if ["reihe", "row", "rh", "r"].contains(l) { return .row }
            if ["platz", "sitz", "sitzplatz", "seat", "pl", "p"].contains(l) { return .seat }
            return nil
        }
        func set(_ f: Field, _ raw: String) {
            let value = String(raw.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)).prefix(24))
            guard !value.isEmpty else { return }
            switch f {
            case .entrance: if seat.entrance.isEmpty { seat.entrance = value }
            case .block: if seat.block.isEmpty { seat.block = value }
            case .row: if seat.row.isEmpty { seat.row = value }
            case .seat: if seat.seat.isEmpty { seat.seat = value }
            }
        }

        for (index, line) in lines.enumerated() {
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "|" }).map(String.init)
            // Tabellenkopf: mehrere Beschriftungen in einer Zeile, Werte darunter.
            let labels = tokens.compactMap(field(for:))
            if labels.count >= 2, labels.count == tokens.count, index + 1 < lines.count {
                let values = lines[index + 1].split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "|" }).map(String.init)
                if values.count == labels.count {
                    for (f, v) in zip(labels, values) { set(f, v) }
                    continue
                }
            }
            // Beschriftung allein in der Zeile → Wert in der nächsten.
            if tokens.count == 1, let f = field(for: tokens[0]), index + 1 < lines.count, lines[index + 1].count <= 20 {
                set(f, lines[index + 1])
            }
            // „Reihe/Platz 14/22“ oder „Reihe | Platz: 14 | 22“
            if let regex = try? NSRegularExpression(pattern: #"(?:Reihe|Rh\.?)\s*[/|]\s*(?:Platz|Pl\.?|Sitz)\s*[:.]?\s*(\w{1,4})\s*[/|]\s*(\d{1,4})"#, options: .caseInsensitive),
               let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let r1 = Range(m.range(at: 1), in: line), let r2 = Range(m.range(at: 2), in: line) {
                set(.row, String(line[r1])); set(.seat, String(line[r2]))
            }
            // Paare „Label Wert“ innerhalb der Zeile (auch mehrere je Zeile).
            var k = 0
            while k < tokens.count - 1 {
                if let f = field(for: tokens[k]), tokens[k].count > 1 || tokens[k + 1].first?.isNumber == true {
                    set(f, tokens[k + 1]); k += 2
                } else { k += 1 }
            }
        }

        // Ränge und Bereiche mit mehreren Wörtern („2. Rang links“, „Parkett rechts“).
        func first(_ pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
        if let rank = first(#"((?:\d\.\s*)?(?:Rang|Balkon|Galerie)(?:\s+(?:links|rechts|Mitte|li\.?|re\.?))?)"#)
            ?? first(#"((?:Parkett|Loge|Empore|Podium)(?:\s+(?:links|rechts|Mitte|\d+))?)"#) {
            // Ein ausgeschriebener Rang ist aussagekräftiger als ein einzelnes Kürzel.
            if seat.block.isEmpty || seat.block.count <= 2 { seat.block = String(rank.prefix(24)) }
        }
        // Nur plausible Werte behalten.
        if seat.row.count > 4 { seat.row = "" }
        if seat.seat.count > 5 || !(seat.seat.first?.isNumber ?? true) { seat.seat = "" }
        return seat
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
