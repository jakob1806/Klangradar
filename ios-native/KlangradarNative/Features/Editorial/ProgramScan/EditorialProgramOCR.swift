import UIKit
import Vision

/// OCR- und Entity-Matching-Schritte von Punkt 18 (Programmheft-Scan).
enum EditorialProgramOCR {
    /// Erkennt Textzeilen auf allen gescannten Seiten, auf dem Gerät via
    /// Vision — keine Netzwerkanfrage nötig, funktioniert auch offline.
    static func recognizeLines(in images: [UIImage]) async -> [String] {
        var lines: [String] = []
        for image in images {
            guard let cgImage = image.cgImage else { continue }
            let recognized = await recognizeLines(in: cgImage)
            lines.append(contentsOf: recognized)
        }
        // Leere/zu kurze Zeilen (Trennstriche, einzelne Satzzeichen aus
        // Layout-Elementen) sind für Werk-/Namenserkennung nutzlos.
        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
    }

    private static func recognizeLines(in cgImage: CGImage) async -> [String] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["de-DE", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do { try handler.perform([request]) }
            catch { continuation.resume(returning: []) }
        }
    }

    /// Bestmögliche existierende Entität zu einem erkannten Namen — rein
    /// clientseitig (Wortüberlappung), damit der Editor "vermutlich X, oder
    /// neu anlegen?" schon vorausgewählt sieht statt jeden Treffer manuell
    /// zu suchen. Kein Ersatz für eine echte Fuzzy-Suche, aber für Namen mit
    /// nur leichten OCR-Abweichungen (Groß-/Kleinschreibung, Diakritika,
    /// abgeschnittene Wortenden) ausreichend zuverlässig.
    static func bestMatch(for text: String, in options: [EditorialOption]) -> EditorialOption? {
        let needle = normalize(text)
        guard !needle.isEmpty else { return nil }
        var best: (option: EditorialOption, score: Double)?
        for option in options {
            let haystack = normalize(option.title)
            guard !haystack.isEmpty else { continue }
            let score: Double
            if haystack == needle {
                score = 1.0
            } else if haystack.contains(needle) || needle.contains(haystack) {
                score = 0.75
            } else {
                score = wordOverlapRatio(needle, haystack)
            }
            if score >= 0.5, best == nil || score > best!.score {
                best = (option, score)
            }
        }
        return best?.option
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().folding(options: .diacriticInsensitive, locale: .current).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func wordOverlapRatio(_ a: String, _ b: String) -> Double {
        let wordsA = Set(a.split(separator: " ").map(String.init))
        let wordsB = Set(b.split(separator: " ").map(String.init))
        guard !wordsA.isEmpty, !wordsB.isEmpty else { return 0 }
        let shared = wordsA.intersection(wordsB).count
        return Double(shared) / Double(max(wordsA.count, wordsB.count))
    }
}
