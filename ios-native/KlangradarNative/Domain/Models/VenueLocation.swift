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
