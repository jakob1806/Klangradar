import Foundation

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
        return "\(startDate.formatted(.dateTime.locale(Locale(identifier: "de_DE")).weekday(.abbreviated).hour().minute())) · \(venueName)"
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
        fallbackImageUrls: [String]? = nil
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
            fallbackImageUrls: nil
        )
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
    let photoUrl: String?
    init(id: UUID? = nil, photoUrl: String?) { self.id = id; self.photoUrl = photoUrl }
    init(json: JSONObject) { id = json.string("id").flatMap(UUID.init(uuidString:)); photoUrl = json.string("photo_url") }
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
