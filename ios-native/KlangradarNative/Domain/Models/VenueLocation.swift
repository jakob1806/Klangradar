import CoreLocation
import Foundation

struct VenueLocation: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let slug: String?
    let city: String?
    let upcomingEventCount: Int
    let latitude: Double
    let longitude: Double

    init(id: UUID, name: String, slug: String? = nil, city: String? = nil, upcomingEventCount: Int = 0, latitude: Double, longitude: Double) {
        self.id = id; self.name = name; self.slug = slug; self.city = city; self.upcomingEventCount = upcomingEventCount; self.latitude = latitude; self.longitude = longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Gruppiert Venues nach auf ~11m gerundeter Koordinate (4 Nachkommastellen)
/// — deckt exakte Adress-Kollisionen wie Gasteig HP8 (Isarphilharmonie/
/// Saal X/Blackbox teilen sich dieselbe Koordinate) zuverlässig ab, ohne
/// echte, nur zufällig nahe beieinanderliegende Venues zusammenzulegen.
/// Eigene, aus VenueMapView herausgezogene Funktion, damit sie ohne
/// SwiftUI/Map testbar ist (siehe VenueLocationTests.swift).
func groupVenuesByLocation(_ venues: [VenueLocation]) -> [[VenueLocation]] {
    let rounded = { (value: Double) in (value * 10_000).rounded() / 10_000 }
    let grouped = Dictionary(grouping: venues) { venue in
        "\(rounded(venue.latitude)),\(rounded(venue.longitude))"
    }
    return Array(grouped.values)
}

/// Nutzerfeedback: der Übertitel des Gruppen-Pins zeigte den Namen des
/// ERSTEN Venues in der Gruppe (z.B. "Black Box im Gasteig HP8") statt des
/// gemeinsamen Gebäudenamens — extrahiert stattdessen den längsten
/// gemeinsamen Teilstring aller Namen in der Gruppe (z.B. "Gasteig HP8" aus
/// "Isarphilharmonie (Gasteig HP8)"/"Saal X im Gasteig HP8"/"Black Box im
/// Gasteig HP8"). Generisch statt hartkodiert, damit künftige Mehrfach-
/// Säle-Gebäude ohne Code-Änderung funktionieren. Eigene, aus VenueMapView
/// herausgezogene Funktion, damit sie ohne SwiftUI/Map testbar ist.
func titleForVenueGroup(_ group: [VenueLocation]) -> String {
    guard let common = longestCommonSubstring(group.map(\.name)),
          common.trimmingCharacters(in: .whitespaces).count >= 4
    else {
        return "\(group.count) Konzertorte"
    }
    return common.trimmingCharacters(in: CharacterSet(charactersIn: " ()").union(.whitespaces))
}

private func longestCommonSubstring(_ strings: [String]) -> String? {
    guard var candidate = strings.first else { return nil }
    for s in strings.dropFirst() {
        guard let next = longestCommonSubstring(candidate, s), !next.isEmpty else { return nil }
        candidate = next
    }
    return candidate.isEmpty ? nil : candidate
}

private func longestCommonSubstring(_ a: String, _ b: String) -> String? {
    let aChars = Array(a), bChars = Array(b)
    guard !aChars.isEmpty, !bChars.isEmpty else { return nil }
    var table = Array(repeating: Array(repeating: 0, count: bChars.count + 1), count: aChars.count + 1)
    var maxLen = 0, endIndex = 0
    for i in 1...aChars.count {
        for j in 1...bChars.count {
            if aChars[i - 1] == bChars[j - 1] {
                table[i][j] = table[i - 1][j - 1] + 1
                if table[i][j] > maxLen { maxLen = table[i][j]; endIndex = i }
            }
        }
    }
    guard maxLen > 0 else { return nil }
    return String(aChars[(endIndex - maxLen)..<endIndex])
}
