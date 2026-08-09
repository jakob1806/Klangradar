import Foundation

enum EntityKind: String, CaseIterable, Codable, Hashable, Sendable {
    case person
    case ensemble
    case venue
    case work

    var title: String {
        switch self {
        case .person: "Personen"
        case .ensemble: "Ensembles"
        case .venue: "Orte"
        case .work: "Werke"
        }
    }

    var systemImage: String {
        switch self {
        case .person: "person"
        case .ensemble: "person.3"
        case .venue: "building.columns"
        case .work: "music.note.list"
        }
    }
}

/// Redaktionell gewählter Bildausschnitt (Anteile 0..1 des Originalbilds),
/// analog zu app/lib/core/gallery/entity_gallery_providers.dart#GalleryImage
/// bzw. der neuen persons/ensembles.avatar_crop_x/y/width/height-Spalte
/// (siehe 20261007000005_person_name_parts_and_avatar_crop.sql).
struct CropRect: Hashable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct DirectoryItem: Identifiable, Hashable, Sendable {
    let id: String
    let kind: EntityKind
    let slug: String?
    let title: String
    let subtitle: String?
    let imageURL: URL?
    /// Runder Avatar-Fokuspunkt für `imageURL`, nur bei `.person`/`.ensemble`
    /// gesetzt und nur gültig, solange `imageURL` tatsächlich von der
    /// eigenen `photo_url`-Spalte stammt (siehe enrichingDirectoryImages —
    /// Cover-Fallback aus der Galerie überschreibt imageURL nur, wenn es
    /// vorher leer war, der Crop bleibt dadurch immer zum richtigen Bild
    /// konsistent, ohne extra Nullung nötig).
    var avatarCrop: CropRect? = nil
}

struct GalleryImage: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let altText: String?
    let photographer: String?
    let license: String?
}

struct LinkedEvent: Identifiable, Hashable, Sendable {
    let id: String
    let slug: String
    let title: String
    let startDate: Date?
    let venueName: String?
    let role: String?
    let imageURLs: [String]?
    let venueID: UUID?
    let venuePhotoURL: String?

    init(
        id: String,
        slug: String,
        title: String,
        startDate: Date?,
        venueName: String?,
        role: String?,
        imageURLs: [String]? = nil,
        venueID: UUID? = nil,
        venuePhotoURL: String? = nil
    ) {
        self.id = id
        self.slug = slug
        self.title = title
        self.startDate = startDate
        self.venueName = venueName
        self.role = role
        self.imageURLs = imageURLs
        self.venueID = venueID
        self.venuePhotoURL = venuePhotoURL
    }

    var concertEvent: ConcertEvent? {
        guard let eventID = UUID(uuidString: id), let startDate else { return nil }
        return ConcertEvent(
            id: eventID,
            slug: slug,
            title: title,
            subtitle: nil,
            startDatetime: ISO8601DateFormatter().string(from: startDate),
            imageUrls: imageURLs,
            status: "scheduled",
            venues: venueID.map { VenueSummary(id: $0, name: venueName ?? "Ort folgt", photoUrl: venuePhotoURL) }
        )
    }
}

struct EntityDetail: Identifiable, Sendable {
    let id: String
    let kind: EntityKind
    let slug: String?
    let title: String
    let subtitle: String?
    let primaryImageURL: URL?
    let fields: JSONObject
    let gallery: [GalleryImage]
    let events: [LinkedEvent]
    let similar: [DirectoryItem]
}

struct EditorialCollection: Identifiable, Hashable, Sendable {
    let id: String
    let slug: String
    let title: String
    let subtitle: String?
    let description: String?
    let coverImageURL: URL?
    let events: [ConcertEvent]
}

struct SearchHit: Identifiable, Hashable, Sendable {
    let id: String
    let kind: EntityKind?
    let slug: String?
    let title: String
    let subtitle: String?
}

/// Anzeigenamen für die rohen role-Enum-Werte aus `persons.roles`
/// (Bugfix: Verzeichnisliste/Personen-Detailseite zeigten bisher die
/// rohen Kleinbuchstaben-Werte der DB, z.B. "dirigent" statt "Dirigent:in"
/// — analog zum bereits vorhandenen Fix in der Flutter-App, siehe
/// app/lib/core/constants/role_labels.dart).
func personRoleLabel(_ role: String) -> String {
    switch role {
    case "komponist": "Komponist:in"
    case "dirigent": "Dirigent:in"
    case "solist": "Solist:in"
    case "chorleiter": "Chorleiter:in"
    case "moderator": "Moderator:in"
    default: role.capitalized
    }
}

extension String {
    var cleanedWorkTitle: String {
        var value = trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let quotePairs: [(Character, Character)] = [
            ("\"", "\""), ("'", "'"), ("„", "“"), ("“", "”"), ("«", "»"), ("‹", "›")
        ]
        var changed = true
        while changed, value.count > 1 {
            changed = false
            if let first = value.first, let last = value.last,
               quotePairs.contains(where: { $0.0 == first && $0.1 == last }) {
                value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
            }
        }
        return value
    }
}
