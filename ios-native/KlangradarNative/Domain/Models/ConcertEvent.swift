import Foundation

enum KlangradarDateTime {
    static let timeZone = TimeZone(identifier: "Europe/Berlin")!
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "de_DE")
        calendar.timeZone = timeZone
        return calendar
    }

    static func string(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

struct ConcertEvent: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let slug: String
    let title: String
    let subtitle: String?
    let startDatetime: String
    let imageUrls: [String]?
    let status: String?
    let venues: VenueSummary?
    let eventParticipants: [EventParticipantImage]?
    let fallbackImageUrls: [String]?
    let category: String?
    let genreIDs: [UUID]
    let genreLabels: [String]
    let isFree: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, slug, title, subtitle, startDatetime, imageUrls, status, venues
        case eventParticipants, fallbackImageUrls, category, genreIDs, genreLabels, isFree
    }

    var startDate: Date? {
        FlexibleDateParser.date(from: startDatetime)
    }

    var primaryImageURL: URL? {
        imageUrls?.compactMap(URL.init(string:)).first
            ?? fallbackImageUrls?.compactMap(URL.init(string:)).first
            ?? eventParticipants?.compactMap(\.imageURL).first
            ?? venues?.photoURL
    }

    var venueName: String {
        venues?.name ?? "Ort folgt"
    }

    var dateLine: String {
        guard let startDate else { return venueName }
        // Nutzerfeedback: "Mo, 18:00" allein zeigt weder Tag noch Monat —
        // ohne den vollen Kontext (z.B. beim Scrollen durch Suchergebnisse
        // über mehrere Wochen) weiß man nicht, WELCHER Montag gemeint ist.
        // Tag+Monat ergänzt, Wochentag/Uhrzeit bleiben aus Platzgründen kurz.
        return "\(KlangradarDateTime.string(startDate, format: "EEE, d. MMM HH:mm")) · \(venueName)"
    }

    init(
        id: UUID,
        slug: String,
        title: String,
        subtitle: String?,
        startDatetime: String,
        imageUrls: [String]?,
        status: String?,
        venues: VenueSummary?,
        eventParticipants: [EventParticipantImage]? = nil,
        fallbackImageUrls: [String]? = nil,
        category: String? = nil,
        genreIDs: [UUID] = [],
        genreLabels: [String] = [],
        isFree: Bool? = nil
    ) {
        self.id = id
        self.slug = slug
        self.title = title
        self.subtitle = subtitle
        self.startDatetime = startDatetime
        self.imageUrls = imageUrls
        self.status = status
        self.venues = venues
        self.eventParticipants = eventParticipants
        self.fallbackImageUrls = fallbackImageUrls
        self.category = category
        self.genreIDs = genreIDs
        self.genreLabels = genreLabels
        self.isFree = isFree
    }

    init?(json: JSONObject) {
        guard
            let id = json.string("id").flatMap(UUID.init(uuidString:)),
            let slug = json.string("slug"),
            let title = json.string("title"),
            let startDatetime = json.string("start_datetime")
        else { return nil }

        let venue = json.object("venues").flatMap { value -> VenueSummary? in
            guard
                let venueID = value.string("id").flatMap(UUID.init(uuidString:)),
                let name = value.string("name")
            else { return nil }
            return VenueSummary(id: venueID, name: name, photoUrl: value.string("photo_url"))
        }

        let genreRows = json.objects("event_genres").compactMap { $0.object("genres") }

        self.init(
            id: id,
            slug: slug,
            title: title,
            subtitle: json.string("subtitle"),
            startDatetime: startDatetime,
            imageUrls: json.strings("image_urls"),
            status: json.string("status"),
            venues: venue,
            eventParticipants: json.objects("event_participants").map(EventParticipantImage.init(json:)),
            fallbackImageUrls: nil,
            category: json.string("category"),
            genreIDs: genreRows.compactMap { $0.string("id").flatMap(UUID.init(uuidString:)) },
            genreLabels: genreRows.compactMap { $0.string("label_de") ?? $0.string("slug") },
            isFree: json.bool("is_free")
        )
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            slug: try values.decode(String.self, forKey: .slug),
            title: try values.decode(String.self, forKey: .title),
            subtitle: try values.decodeIfPresent(String.self, forKey: .subtitle),
            startDatetime: try values.decode(String.self, forKey: .startDatetime),
            imageUrls: try values.decodeIfPresent([String].self, forKey: .imageUrls),
            status: try values.decodeIfPresent(String.self, forKey: .status),
            venues: try values.decodeIfPresent(VenueSummary.self, forKey: .venues),
            eventParticipants: try values.decodeIfPresent([EventParticipantImage].self, forKey: .eventParticipants),
            fallbackImageUrls: try values.decodeIfPresent([String].self, forKey: .fallbackImageUrls),
            category: try values.decodeIfPresent(String.self, forKey: .category),
            genreIDs: try values.decodeIfPresent([UUID].self, forKey: .genreIDs) ?? [],
            genreLabels: try values.decodeIfPresent([String].self, forKey: .genreLabels) ?? [],
            isFree: try values.decodeIfPresent(Bool.self, forKey: .isFree)
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(slug, forKey: .slug)
        try values.encode(title, forKey: .title)
        try values.encodeIfPresent(subtitle, forKey: .subtitle)
        try values.encode(startDatetime, forKey: .startDatetime)
        try values.encodeIfPresent(imageUrls, forKey: .imageUrls)
        try values.encodeIfPresent(status, forKey: .status)
        try values.encodeIfPresent(venues, forKey: .venues)
        try values.encodeIfPresent(eventParticipants, forKey: .eventParticipants)
        try values.encodeIfPresent(fallbackImageUrls, forKey: .fallbackImageUrls)
        try values.encodeIfPresent(category, forKey: .category)
        try values.encode(genreIDs, forKey: .genreIDs)
        try values.encode(genreLabels, forKey: .genreLabels)
        try values.encodeIfPresent(isFree, forKey: .isFree)
    }

    func matchesFeedTerms(_ terms: [String]) -> Bool {
        let haystack = ([title, subtitle, category] + genreLabels)
            .compactMap { $0 }
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()
        return terms.contains { haystack.contains($0) }
    }
}

struct VenueSummary: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let photoUrl: String?

    init(id: UUID, name: String, photoUrl: String? = nil) {
        self.id = id; self.name = name; self.photoUrl = photoUrl
    }

    var photoURL: URL? { photoUrl.flatMap(URL.init(string:)) }
}

struct EventParticipantImage: Codable, Hashable, Sendable {
    let persons: ParticipantPhoto?
    let ensembles: ParticipantPhoto?
    var imageURL: URL? { (persons?.photoUrl ?? ensembles?.photoUrl).flatMap(URL.init(string:)) }
    init(persons: ParticipantPhoto?, ensembles: ParticipantPhoto?) { self.persons = persons; self.ensembles = ensembles }
    init(json: JSONObject) { persons = json.object("persons").map(ParticipantPhoto.init(json:)); ensembles = json.object("ensembles").map(ParticipantPhoto.init(json:)) }
}

struct ParticipantPhoto: Codable, Hashable, Sendable {
    let id: UUID?
    let name: String?
    let photoUrl: String?
    init(id: UUID? = nil, name: String? = nil, photoUrl: String?) { self.id = id; self.name = name; self.photoUrl = photoUrl }
    init(json: JSONObject) {
        id = json.string("id").flatMap(UUID.init(uuidString:))
        // persons liefert full_name, ensembles liefert name — beide Fälle abdecken.
        name = json.string("full_name") ?? json.string("name")
        photoUrl = json.string("photo_url")
    }
}

enum FlexibleDateParser {
    static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }
}
