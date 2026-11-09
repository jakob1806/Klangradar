// Erstellt von Claude Code (09.11.2026): Platzerkennung v3.
// 1. Wörterbuch statt Einzelmuster: Bezeichnungen je Art (Bereich, Reihe,
//    Platz, Eingang, Etage) auf Deutsch und Englisch.
// 2. Ausschlussliste: Preis, Kategorie, Ticket-/Kundennummer, Adresse, PLZ,
//    Datum/Uhrzeit liefern nie Platzwerte.
// 3. Lage auf dem Ticket: Wert rechts neben oder direkt unter der
//    Bezeichnung, Tabellen „Block | Reihe | Platz“ spaltenweise.
// 4. Plausibilität je Feld; Bezeichnung so übernommen, wie sie auf dem
//    Ticket steht („Sitz“, „Tür“, „Rang“).
// 5. Anbieter-Vorlagen (München Ticket/MPHIL, Eventim, Reservix,
//    Staatsoper) für deren Eigenheiten.
import CoreGraphics
import Foundation

enum SeatParser {
    struct Line: Sendable {
        var text: String
        /// Lage normiert (0…1 je Seite, oben links), nil = unbekannt.
        var box: CGRect?
    }

    enum Kind: CaseIterable { case area, row, seat, entrance, floor }

    /// Bezeichnung → Art. Schlüssel kleingeschrieben, ohne Satzzeichen.
    static let dictionary: [String: Kind] = {
        var d: [String: Kind] = [:]
        for w in ["block", "bereich", "sektor", "sektion", "section", "rang", "parkett", "loge", "balkon", "galerie",
                  "empore", "tribüne", "tribuene", "podium", "stehplatz", "area"] { d[w] = .area }
        for w in ["reihe", "rh", "row", "r"] { d[w] = .row }
        for w in ["platz", "sitz", "sitzplatz", "pl", "seat", "p", "nr", "platznr", "platz-nr"] { d[w] = .seat }
        for w in ["eingang", "einlass", "tür", "tuer", "tor", "gate", "entrance", "zugang", "aufgang", "portal", "door"] { d[w] = .entrance }
        for w in ["etage", "ebene", "stock", "geschoss", "level", "floor"] { d[w] = .floor }
        return d
    }()

    /// Bereichswörter, die auch ohne Doppelpunkt am Zeilenanfang einen Wert tragen („Rang Mitte“).
    static let areaWords: Set<String> = ["rang", "parkett", "loge", "balkon", "galerie", "empore", "tribüne", "podium", "seitenbalkon", "stehplatz"]

    static let exclusions = ["preis", "eur", "€", "kat.", "kategorie", "ticketnummer", "ticket-nr", "kundennummer", "auftrag",
                             "bestell", "straße", "strasse", "str.", "gebühr", "inkl", "uhr", "www", "http", "@", "gültig",
                             "lichtbild", "veranstalter", "vvk"]

    enum Provider: String { case muenchenTicket, eventim, reservix, staatsoper, generic }

    static func provider(of text: String) -> Provider {
        let t = text.lowercased()
        if t.contains("münchen ticket") || t.contains("muenchenticket") || t.contains("mphilweb") { return .muenchenTicket }
        if t.contains("eventim") { return .eventim }
        if t.contains("reservix") || t.contains("adticket") { return .reservix }
        if t.contains("staatsoper") || t.contains("staatstheater") { return .staatsoper }
        return .generic
    }

    static func key(_ token: String) -> String {
        token.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    }

    static func isExcluded(_ line: String) -> Bool {
        let l = line.lowercased()
        if exclusions.contains(where: { l.contains($0) }) { return true }
        // PLZ, Datum, Uhrzeit, lange Nummern
        let patterns = [#"\b\d{5}\b"#, #"\d{1,2}\.\d{1,2}\.\d{2,4}"#, #"\b\d{1,2}:\d{2}\b"#, #"\d{7,}"#]
        return patterns.contains { l.range(of: $0, options: .regularExpression) != nil }
    }

    static func plausible(_ kind: Kind, _ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty, !isExcluded(v) else { return false }
        switch kind {
        case .row: return v.count <= 4 && v.range(of: #"^[0-9A-Za-zÄÖÜäöü]+$"#, options: .regularExpression) != nil
        case .seat: return v.count <= 5 && v.range(of: #"^\d+[a-zA-Z]?$"#, options: .regularExpression) != nil
        case .entrance: return v.count <= 14
        case .area: return v.count <= 28 && dictionary[key(v)] != .row && dictionary[key(v)] != .seat
        case .floor: return v.count <= 14
        }
    }

    static func floorValue(in text: String) -> String? {
        guard let r = text.range(of: #"(\d{1,2}\.\s*(OG|UG|Obergeschoss|Untergeschoss|Etage|Stock|Ebene)|\bEG\b|Erdgeschoss|Hochparterre)"#,
                                 options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(text[r])
    }

    // MARK: Auswertung

    struct Hit { var kind: Kind; var label: String; var value: String; var score: Int }

    static func parse(_ rawLines: [Line]) -> ConcertSeat {
        let lines = rawLines
            .map { Line(text: $0.text.trimmingCharacters(in: .whitespaces), box: $0.box) }
            .filter { !$0.text.isEmpty }
        let fullText = lines.map(\.text).joined(separator: "\n")
        let provider = provider(of: fullText)
        var hits: [Hit] = []

        func add(_ kind: Kind, _ label: String, _ raw: String, score: Int) {
            let value = String(raw.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ":.,;|"))).prefix(28))
            guard plausible(kind, value) else { return }
            hits.append(Hit(kind: kind, label: label.trimmingCharacters(in: .punctuationCharacters), value: value, score: score))
        }

        for (index, line) in lines.enumerated() {
            // Teile einer Zeile: „Tür M, 2. OG“ → „Tür M“ + „2. OG“
            let segments = line.text.components(separatedBy: CharacterSet(charactersIn: ",;"))
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            for segment in segments {
                if let floor = floorValue(in: segment), segment.count <= floor.count + 2 {
                    add(.floor, "Etage", floor, score: 3); continue
                }
                if isExcluded(segment) { continue }
                let tokens = segment.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "|" || $0 == "/" }).map(String.init)
                guard !tokens.isEmpty else { continue }

                // Tabellenkopf: nur Bezeichnungen → Werte in der nächsten Zeile (spaltenweise über Lage).
                let kinds = tokens.compactMap { dictionary[key($0)] }
                if kinds.count >= 2, kinds.count == tokens.count {
                    if let values = valuesBelow(lines, index), values.count == kinds.count {
                        for (k, (t, v)) in zip(kinds, zip(tokens, values)) { add(k, t, v, score: 4) }
                        continue
                    }
                }
                // „Reihe/Platz 14/22“
                if let m = segment.range(of: #"(?i)(Reihe|Rh\.?|Row)\s*/\s*(Platz|Pl\.?|Sitz|Seat)\s*:?\s*(\w{1,4})\s*/\s*(\d{1,4})"#, options: .regularExpression) {
                    let parts = segment[m].components(separatedBy: CharacterSet(charactersIn: " /:")).filter { !$0.isEmpty }
                    if parts.count >= 4 { add(.row, parts[0], parts[parts.count - 2], score: 4); add(.seat, parts[1], parts[parts.count - 1], score: 4) }
                    continue
                }
                // Bereich am Zeilenanfang ohne Doppelpunkt: „Rang Mitte“, „2. Rang links“, „Parkett rechts“
                let lead = tokens.first.map(key) ?? ""
                let second = tokens.count > 1 ? key(tokens[1]) : ""
                if (areaWords.contains(lead) || (lead.range(of: #"^\d+$"#, options: .regularExpression) != nil && areaWords.contains(second))),
                   tokens.count <= 4, !tokens.dropFirst().contains(where: { dictionary[key($0)] == .row || dictionary[key($0)] == .seat }) {
                    add(.area, "Bereich", segment, score: 3); continue
                }
                // Paare „Bezeichnung Wert“, auch mehrere je Zeile („Reihe 14 Platz 22“).
                var k = 0
                var consumed = false
                while k < tokens.count {
                    if let kind = dictionary[key(tokens[k])], kind != .floor {
                        let isShort = key(tokens[k]).count <= 2
                        if k + 1 < tokens.count {
                            let next = tokens[k + 1]
                            if isShort && next.first?.isNumber != true { k += 1; continue }
                            if dictionary[key(next)] == nil {
                                add(kind, tokens[k], next, score: tokens[k].hasSuffix(":") ? 3 : 2)
                                consumed = true; k += 2; continue
                            }
                        } else if !isShort, tokens.count == 1 || k == tokens.count - 1 {
                            // Bezeichnung am Ende/allein → Wert rechts daneben oder darunter.
                            if let v = valueBeside(lines, index) ?? valueBelow(lines, index) {
                                add(kind, tokens[k], v, score: 2); consumed = true
                            }
                        }
                    }
                    k += 1
                }
                _ = consumed
            }
        }

        // Anbieter-Eigenheiten
        switch provider {
        case .muenchenTicket:
            // Bereich steht ohne Bezeichnung direkt über „Reihe:“
            if !hits.contains(where: { $0.kind == .area }),
               let rowIndex = lines.firstIndex(where: { key($0.text.split(separator: " ").first.map(String.init) ?? "") == "reihe" }),
               rowIndex > 0 {
                let above = lines[rowIndex - 1].text
                if !isExcluded(above), above.count <= 24, above.rangeOfCharacter(from: .letters) != nil, !above.contains(":") {
                    add(.area, "Bereich", above, score: 2)
                }
            }
        case .eventim, .reservix, .staatsoper, .generic:
            break
        }

        return assemble(hits)
    }

    static func assemble(_ hits: [Hit]) -> ConcertSeat {
        var seat = ConcertSeat()
        func best(_ kind: Kind) -> Hit? {
            hits.filter { $0.kind == kind }.max { $0.score < $1.score }  // bei Gleichstand der erste
        }
        func label(_ hit: Hit, default fallback: String) -> String {
            let l = hit.label.prefix(1).uppercased() + hit.label.dropFirst().lowercased()
            return l == fallback ? "" : l
        }
        if let h = best(.area) {
            seat.block = h.value
            let l = label(h, default: ConcertSeat.defaultLabels.block)
            seat.blockLabel = l == "Bereich" || areaWords.contains(key(h.label)) ? (l == "Bereich" ? "Bereich" : l) : l
        }
        if let h = best(.row) { seat.row = h.value; seat.rowLabel = ["R", "Rh", "Row"].contains(label(h, default: "Reihe")) ? "" : label(h, default: "Reihe") }
        if let h = best(.seat) {
            seat.seat = h.value
            let l = label(h, default: "Platz")
            seat.seatLabel = ["Sitz", "Sitzplatz"].contains(l) ? l : ""
        }
        if let h = best(.entrance) { seat.entrance = h.value; seat.entranceLabel = label(h, default: "Eingang") }
        if let h = best(.floor) { seat.extras.append(.init(label: "Etage", value: h.value)) }
        return seat
    }

    // MARK: Lage

    private static func valueBeside(_ lines: [Line], _ index: Int) -> String? {
        guard let box = lines[index].box else { return nil }
        return lines.enumerated()
            .filter { $0.offset != index }
            .compactMap { (_, l) -> (CGFloat, String)? in
                guard let b = l.box, abs(b.midY - box.midY) < box.height * 0.7, b.minX > box.maxX - 0.005, b.minX - box.maxX < 0.35 else { return nil }
                return (b.minX - box.maxX, l.text)
            }
            .min { $0.0 < $1.0 }?.1
    }

    private static func valueBelow(_ lines: [Line], _ index: Int) -> String? {
        guard index + 1 < lines.count else { return nil }
        if let box = lines[index].box {
            return lines.enumerated()
                .filter { $0.offset != index }
                .compactMap { (_, l) -> (CGFloat, String)? in
                    guard let b = l.box, b.minY > box.minY + box.height * 0.5, b.minY - box.maxY < box.height * 2.2,
                          b.maxX > box.minX - 0.02, b.minX < box.maxX + 0.02 else { return nil }
                    return (b.minY, l.text)
                }
                .min { $0.0 < $1.0 }?.1
        }
        let next = lines[index + 1].text
        return next.count <= 20 && dictionary[key(next.split(separator: " ").first.map(String.init) ?? "")] == nil ? next : nil
    }

    private static func valuesBelow(_ lines: [Line], _ index: Int) -> [String]? {
        guard index + 1 < lines.count else { return nil }
        if let box = lines[index].box {
            let row = lines.enumerated().filter { $0.offset != index }.compactMap { (_, l) -> Line? in
                guard let b = l.box, b.minY > box.minY + box.height * 0.5, b.minY - box.maxY < box.height * 2.2 else { return nil }
                return l
            }.sorted { ($0.box?.minX ?? 0) < ($1.box?.minX ?? 0) }
            let tokens = row.flatMap { $0.text.split(whereSeparator: { $0 == " " || $0 == "|" || $0 == "\t" }).map(String.init) }
            if !tokens.isEmpty { return tokens }
        }
        return lines[index + 1].text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "|" }).map(String.init)
    }
}
