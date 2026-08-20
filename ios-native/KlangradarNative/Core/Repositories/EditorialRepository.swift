import Foundation

enum EditorialEntityKind: String, CaseIterable, Identifiable, Sendable {
    case venue, person, ensemble, work
    var id: String { rawValue }
    var title: String { switch self { case .venue: "Venues"; case .person: "Personen"; case .ensemble: "Ensembles"; case .work: "Werke" } }
    var singularTitle: String { switch self { case .venue: "Venue"; case .person: "Person"; case .ensemble: "Ensemble"; case .work: "Werk" } }
    var symbol: String { switch self { case .venue: "building.columns"; case .person: "person"; case .ensemble: "person.3"; case .work: "music.note" } }
    var table: String { switch self { case .venue: "venues"; case .person: "persons"; case .ensemble: "ensembles"; case .work: "works" } }
}

/// Feldparität mit dem Web-Admin (admin/src/app/(dashboard)/{venues,persons,
/// ensembles}/*-form.tsx) — flache optionale Felder statt pro-Kind-Varianten,
/// analog zum bereits bestehenden composerID (nur bei .work befüllt).
struct EditorialEntity: Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: EditorialEntityKind
    let title: String
    let subtitle: String?
    let editableSubtitle: String?
    let description: String?
    let imageURL: String?
    let composerID: UUID?
    // Gemeinsam
    var slug: String? = nil
    var isVerified: Bool? = nil
    var websiteURL: String? = nil
    // Venue
    var addressStreet: String? = nil
    var addressZip: String? = nil
    var addressCity: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var capacity: Int? = nil
    // Person
    var firstName: String? = nil
    var middleName: String? = nil
    var lastName: String? = nil
    var roles: [String]? = nil
    var nationality: String? = nil
    var birthDate: String? = nil
    var deathDate: String? = nil
    var isDeceased: Bool? = nil
    var memberOfEnsembleID: UUID? = nil
    // Ensemble
    var ensembleType: String? = nil
    var foundedYear: Int? = nil
    var memberCount: Int? = nil
    var homeVenueID: UUID? = nil
    var parentEnsembleID: UUID? = nil
    /// Runder Avatar-Ausschnitt (nur bei .person/.ensemble befüllt, siehe
    /// persons/ensembles.avatar_crop_x/y/width/height,
    /// 20261007000005_person_name_parts_and_avatar_crop.sql) — Punkt 19,
    /// natives Bild-Crop in EditorialEntityEditorView.
    var avatarCrop: CropRect? = nil
}

struct EditorialEvent: Identifiable, Hashable, Sendable {
    let id: UUID
    let slug: String
    let title: String
    let subtitle: String?
    let startDate: Date
    let venueID: UUID
    let venueName: String
    let imageURL: String?
    let status: String
    // Feldparität mit event-form.tsx
    var descriptionDe: String? = nil
    var durationMinutes: Int? = nil
    var hasIntermission: Bool = false
    var organizerID: UUID? = nil
    var ticketURL: String? = nil
    var priceMin: Double? = nil
    var priceMax: Double? = nil
    var isFree: Bool = false
    var remainingTicketsStatus: String? = nil
    var doorsInfo: String? = nil
    var ageRestriction: String? = nil
    var discountInfo: String? = nil
    var presaleFeeInfo: String? = nil
    var genreIDs: [UUID] = []
}

struct EditorialOption: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String?
}

struct EditorialGalleryImage: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: String
    let sortOrder: Int
}

struct EditorialParticipant: Identifiable, Hashable, Sendable {
    let id: UUID
    let entityID: UUID
    let entityType: String
    let name: String
    let roleLabel: String?
}

struct EditorialWorkLink: Identifiable, Hashable, Sendable {
    var id: String { "\(workID.uuidString)-\(position)" }
    let workID: UUID
    let title: String
    let composer: String?
    let catalogNumber: String?
    let description: String?
    let composerID: UUID?
    let position: Int
}

struct EditorialEventDetail: Sendable {
    let event: EditorialEvent
    let participants: [EditorialParticipant]
    let works: [EditorialWorkLink]
}

struct EditorialAIProposal: Identifiable, Hashable, Sendable {
    let id = UUID()
    let field: String
    let value: JSONValue
    let confidence: String
    let rationale: String?
    let sourceURLs: [String]
}

struct EditorialAIReply: Sendable {
    let answer: String
    let proposals: [EditorialAIProposal]
}

struct EditorialRepository: Sendable {
    let client: SupabaseRESTClient

    func hasAccess(token: String) async -> Bool {
        let result: Bool? = try? await client.rpc("is_admin_or_editor", accessToken: token)
        return result == true
    }

    func askEditorialAI(entityType: String, entityID: UUID, message: String, token: String) async throws -> EditorialAIReply {
        let response: JSONObject = try await client.edgeFunction("editorial-ai-assistant", body: [
            "action": .string("chat"), "entityType": .string(entityType),
            "entityId": .string(entityID.uuidString), "message": .string(message)
        ], accessToken: token)
        let proposals = response.objects("proposals").compactMap { row -> EditorialAIProposal? in
            guard let field = row.string("field"), let value = row["value"], let confidence = row.string("confidence") else { return nil }
            return EditorialAIProposal(field: field, value: value, confidence: confidence, rationale: row.string("rationale"), sourceURLs: row.strings("sourceUrls"))
        }
        return EditorialAIReply(answer: response.string("answer") ?? "Keine belastbare Antwort gefunden.", proposals: proposals)
    }

    func applyEditorialAI(entityType: String, entityID: UUID, proposals: [EditorialAIProposal], token: String) async throws {
        let values: [JSONValue] = proposals.map { proposal in
            .object(["field": .string(proposal.field), "value": proposal.value, "confidence": .string(proposal.confidence),
                     "rationale": proposal.rationale.map(JSONValue.string) ?? .null,
                     "sourceUrls": .array(proposal.sourceURLs.map(JSONValue.string))])
        }
        let _: JSONObject = try await client.edgeFunction("editorial-ai-assistant", body: [
            "action": .string("apply"), "entityType": .string(entityType), "entityId": .string(entityID.uuidString),
            "proposals": .array(values)
        ], accessToken: token)
    }

    func uploadEditorialImage(data: Data, originType: String, originID: UUID, token: String) async throws -> URL {
        let path = "\(originType)/\(originID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        do {
            return try await client.uploadPublicObject(
                bucket: "entity-photos",
                path: path,
                data: data,
                contentType: "image/jpeg",
                accessToken: token
            )
        } catch APIError.httpStatus(403, _) {
            throw EditorialError.validation("Der Bild-Upload wurde von Supabase abgelehnt. Bitte die Anmeldung erneuern oder die Redaktionsberechtigung prüfen.")
        }
    }

    func galleryImages(originType: String, originID: UUID, token: String) async throws -> [EditorialGalleryImage] {
        let rows: [JSONObject] = try await client.get(table: "images", queryItems: [
            URLQueryItem(name: "select", value: "id,source_url,sort_order"),
            URLQueryItem(name: "origin_type", value: "eq.\(originType)"),
            URLQueryItem(name: "origin_id", value: "eq.\(originID.uuidString)"),
            URLQueryItem(name: "license_status", value: "neq.rejected"),
            URLQueryItem(name: "order", value: "sort_order.asc,imported_at.asc")
        ], accessToken: token)
        return rows.compactMap { row in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)), let url = row.string("source_url") else { return nil }
            return EditorialGalleryImage(id: id, url: url, sortOrder: row.integer("sort_order") ?? 0)
        }
    }

    func addGalleryImages(data: [Data], originType: String, originID: UUID, actor: UUID, token: String) async throws -> [EditorialGalleryImage] {
        guard !data.isEmpty else { return try await galleryImages(originType: originType, originID: originID, token: token) }
        let existing = try await galleryImages(originType: originType, originID: originID, token: token)
        var nextSortOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
        var added: [EditorialGalleryImage] = []

        for imageData in data {
            let url = try await uploadEditorialImage(data: imageData, originType: originType, originID: originID, token: token)
            let values: JSONObject = [
                "origin_type": .string(originType),
                "origin_id": .string(originID.uuidString),
                "source_url": .string(url.absoluteString),
                "storage_path": .null,
                "sort_order": .number(Double(nextSortOrder)),
                "license_status": .string("confirmed_free"),
                "needs_review": .bool(false),
                "review_status": .string("approved"),
                "quality_status": .string("valid"),
                "source_name": .string("Native-Redaktionsupload")
            ]
            let rows = try await client.insert(table: "images", values: values, accessToken: token, returning: true)
            guard let id = rows.first?.string("id").flatMap(UUID.init(uuidString:)) else { throw APIError.invalidResponse }
            added.append(EditorialGalleryImage(id: id, url: url.absoluteString, sortOrder: nextSortOrder))
            nextSortOrder += 1
        }

        let combined = existing + added
        if existing.isEmpty, let first = combined.first {
            try await setPrimaryGalleryImage(first, originType: originType, originID: originID, token: token)
        }
        await logGallery(originType: originType, originID: originID, action: "native_editor_gallery_images_added", actor: actor, count: added.count, token: token)
        return try await galleryImages(originType: originType, originID: originID, token: token)
    }

    func setPrimaryGalleryImage(_ selected: EditorialGalleryImage, originType: String, originID: UUID, token: String) async throws {
        let images = try await galleryImages(originType: originType, originID: originID, token: token)
        let reordered = [selected] + images.filter { $0.id != selected.id }
        for (index, image) in reordered.enumerated() where image.sortOrder != index {
            try await client.update(table: "images", values: ["sort_order": .number(Double(index))], filters: [
                URLQueryItem(name: "id", value: "eq.\(image.id.uuidString)")
            ], accessToken: token)
        }
        try await syncLegacyPrimary(originType: originType, originID: originID, images: reordered, token: token)
    }

    func deleteGalleryImage(_ image: EditorialGalleryImage, originType: String, originID: UUID, actor: UUID, token: String) async throws -> [EditorialGalleryImage] {
        try await client.delete(table: "images", filters: [URLQueryItem(name: "id", value: "eq.\(image.id.uuidString)")], accessToken: token)
        var remaining = try await galleryImages(originType: originType, originID: originID, token: token)
        for (index, row) in remaining.enumerated() where row.sortOrder != index {
            try await client.update(table: "images", values: ["sort_order": .number(Double(index))], filters: [
                URLQueryItem(name: "id", value: "eq.\(row.id.uuidString)")
            ], accessToken: token)
        }
        remaining = try await galleryImages(originType: originType, originID: originID, token: token)
        try await syncLegacyPrimary(originType: originType, originID: originID, images: remaining, token: token)
        await logGallery(originType: originType, originID: originID, action: "native_editor_gallery_image_deleted", actor: actor, count: 1, token: token)
        return remaining
    }

    /// Nutzeranfrage: "es sollen alle verfügbaren Veranstaltungen angezeigt
    /// werden" — vorher war hier ein hartes limit=150 gesetzt, sodass bei
    /// mehr offenen/zukünftigen Events die Redaktionsliste (die client-
    /// seitig über EditorialDashboardView.filteredEvents durchsucht wird)
    /// unvollständig blieb. Paginiert jetzt analog zu
    /// LiveEventRepository.allUpcomingEvents(), bis eine Seite kleiner als
    /// die Seitengröße zurückkommt.
    func events(search: String, token: String) async throws -> [EditorialEvent] {
        let clean = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let pageSize = 500
        var result: [EditorialEvent] = []
        var offset = 0
        while true {
            var query = [
                URLQueryItem(name: "select", value: "id,slug,title,subtitle,start_datetime,venue_id,image_urls,status,venues(name)"),
                URLQueryItem(name: "start_datetime", value: "gte.\(Self.isoString(from: KlangradarDateTime.calendar.startOfDay(for: .now)))"),
                URLQueryItem(name: "order", value: "start_datetime.asc"),
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
            if !clean.isEmpty {
                let escaped = clean.replacingOccurrences(of: ",", with: " ")
                query.append(URLQueryItem(name: "or", value: "(title.ilike.*\(escaped)*,subtitle.ilike.*\(escaped)*)"))
            }
            let rows: [JSONObject] = try await client.get(table: "events", queryItems: query, accessToken: token)
            let page = rows.compactMap(Self.event)
            result.append(contentsOf: page)
            if page.count < pageSize { return result }
            offset += pageSize
        }
    }

    /// select-Listen erweitert für Feldparität mit den Web-Admin-Formularen
    /// (venue-form.tsx/person-form.tsx/ensemble-form.tsx) — siehe
    /// EditorialEntity-Kommentar. lat/lng kommen NICHT aus dieser Tabellen-
    /// Query (venues.location ist eine PostGIS geography-Spalte, kein
    /// direktes Feld), sondern separat über die schon bestehende
    /// venues_with_latlng-RPC (siehe ContentRepository.venueLocations()) und
    /// werden unten per id gemerged.
    func entities(kind: EditorialEntityKind, token: String) async throws -> [EditorialEntity] {
        let selection: String
        let order: String
        switch kind {
        case .venue: selection = "id,slug,name,address_street,address_zip,address_city,capacity,website_url,description_de,photo_url"; order = "name.asc"
        case .person: selection = "id,slug,full_name,first_name,middle_name,last_name,roles,instrument,nationality,birth_date,death_date,is_deceased,member_of_ensemble_id,website_url,is_verified,biography_de,photo_url,avatar_crop_x,avatar_crop_y,avatar_crop_width,avatar_crop_height"; order = "full_name.asc"
        case .ensemble: selection = "id,slug,name,type,founded_year,member_count,home_venue_id,parent_ensemble_id,website_url,is_verified,description_de,photo_url,avatar_crop_x,avatar_crop_y,avatar_crop_width,avatar_crop_height"; order = "name.asc"
        case .work: selection = "id,title,catalog_number,description_de,composer_id,composer:persons(full_name)"; order = "title.asc"
        }
        async let rowsTask: [JSONObject] = client.get(table: kind.table, queryItems: [
            URLQueryItem(name: "select", value: selection),
            URLQueryItem(name: "order", value: order),
            URLQueryItem(name: "limit", value: "3000")
        ], accessToken: token)
        async let latLngTask: [JSONObject] = kind == .venue ? (try? await client.rpc("venues_with_latlng", accessToken: token)) ?? [] : []
        let rows = try await rowsTask
        let latLngByID: [String: (Double, Double)] = kind == .venue
            ? Dictionary(uniqueKeysWithValues: (await latLngTask).compactMap { row -> (String, (Double, Double))? in
                guard let id = row.string("id"), let lat = row.number("lat"), let lng = row.number("lng") else { return nil }
                return (id, (lat, lng))
            })
            : [:]

        return rows.compactMap { row in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)), let title = row.string(kind == .person ? "full_name" : kind == .work ? "title" : "name") else { return nil }
            let subtitle: String? = switch kind {
            case .venue: row.string("address_city")
            case .person: row.string("instrument")
            case .ensemble: row.string("type")
            case .work: [row.object("composer")?.string("full_name"), row.string("catalog_number")].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
            }
            let latLng = latLngByID[id.uuidString]
            return EditorialEntity(
                id: id, kind: kind, title: title, subtitle: subtitle, editableSubtitle: kind == .work ? row.string("catalog_number") : subtitle,
                description: row.string(kind == .person ? "biography_de" : "description_de"),
                imageURL: row.string("photo_url"), composerID: row.string("composer_id").flatMap(UUID.init(uuidString:)),
                slug: row.string("slug"), isVerified: row.bool("is_verified"), websiteURL: row.string("website_url"),
                addressStreet: row.string("address_street"), addressZip: row.string("address_zip"), addressCity: kind == .venue ? row.string("address_city") : nil,
                latitude: latLng?.0, longitude: latLng?.1, capacity: row.integer("capacity"),
                firstName: row.string("first_name"), middleName: row.string("middle_name"), lastName: row.string("last_name"),
                roles: row.array("roles").isEmpty ? nil : row.strings("roles"),
                nationality: row.string("nationality"), birthDate: row.string("birth_date"), deathDate: row.string("death_date"), isDeceased: row.bool("is_deceased"),
                memberOfEnsembleID: row.string("member_of_ensemble_id").flatMap(UUID.init(uuidString:)),
                ensembleType: kind == .ensemble ? row.string("type") : nil, foundedYear: row.integer("founded_year"), memberCount: row.integer("member_count"),
                homeVenueID: row.string("home_venue_id").flatMap(UUID.init(uuidString:)), parentEnsembleID: row.string("parent_ensemble_id").flatMap(UUID.init(uuidString:)),
                avatarCrop: (kind == .person || kind == .ensemble) ? Self.avatarCrop(from: row) : nil
            )
        }
    }

    /// Siehe EditorialEntity.avatarCrop.
    private static func avatarCrop(from row: JSONObject) -> CropRect? {
        guard
            let x = row.number("avatar_crop_x"),
            let y = row.number("avatar_crop_y"),
            let width = row.number("avatar_crop_width"),
            let height = row.number("avatar_crop_height")
        else { return nil }
        return CropRect(x: x, y: y, width: width, height: height)
    }

    /// Basisfelder (Name/Titel, Kurztext, Beschreibung, Bild, Komponist bei
    /// Werken) — für Venues siehe stattdessen updateVenue() (eigene RPC
    /// wegen der PostGIS-Geodaten). Erweiterte Personen-/Ensemble-Felder
    /// (Feldparität mit person-form.tsx/ensemble-form.tsx) siehe
    /// updatePersonDetails()/updateEnsembleDetails() darunter — bewusst
    /// eigene Funktionen statt eines einzigen riesigen Parametersatzes hier,
    /// leichter lesbar und die Basis-Speicherung bleibt unverändert nutzbar.
    func updateEntity(entity: EditorialEntity, title: String, subtitle: String, description: String, imageURL: String, composerID: UUID?, actor: UUID, token: String) async throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw EditorialError.validation("Der Name bzw. Titel darf nicht leer sein.") }
        let cleanImage = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanImage.isEmpty, URL(string: cleanImage)?.scheme?.hasPrefix("http") != true {
            throw EditorialError.validation("Die Bildadresse muss mit http:// oder https:// beginnen.")
        }
        let titleKey = entity.kind == .person ? "full_name" : entity.kind == .work ? "title" : "name"
        var values: JSONObject = [titleKey: .string(cleanTitle)]
        switch entity.kind {
        case .venue:
            values["description_de"] = description.nilIfEmpty.map(JSONValue.string) ?? .null
            values["photo_url"] = cleanImage.nilIfEmpty.map(JSONValue.string) ?? .null
        case .person:
            values["instrument"] = subtitle.nilIfEmpty.map(JSONValue.string) ?? .null
            values["biography_de"] = description.nilIfEmpty.map(JSONValue.string) ?? .null
            values["photo_url"] = cleanImage.nilIfEmpty.map(JSONValue.string) ?? .null
        case .ensemble:
            values["description_de"] = description.nilIfEmpty.map(JSONValue.string) ?? .null
            values["photo_url"] = cleanImage.nilIfEmpty.map(JSONValue.string) ?? .null
        case .work:
            values["catalog_number"] = subtitle.nilIfEmpty.map(JSONValue.string) ?? .null
            values["description_de"] = description.nilIfEmpty.map(JSONValue.string) ?? .null
            values["composer_id"] = composerID.map { .string($0.uuidString) } ?? .null
        }
        if entity.kind != .work { values["updated_at"] = .string(Self.isoString(from: .now)) }
        try await client.update(table: entity.kind.table, values: values, filters: [URLQueryItem(name: "id", value: "eq.\(entity.id.uuidString)")], accessToken: token)
        await logEntity(entity: entity, action: "native_editor_update_\(entity.kind.rawValue)", actor: actor, after: values, token: token)
    }

    /// Punkt 19, natives Bild-Crop — nur Personen/Ensembles haben die
    /// avatar_crop_x/y/width/height-Spalten (siehe
    /// 20261007000005_person_name_parts_and_avatar_crop.sql). `crop: nil`
    /// setzt den Ausschnitt zurück (alle vier Spalten auf NULL).
    func updateAvatarCrop(entity: EditorialEntity, crop: CropRect?, actor: UUID, token: String) async throws {
        guard entity.kind == .person || entity.kind == .ensemble else {
            throw EditorialError.validation("Für diesen Eintragstyp gibt es keinen Avatar-Ausschnitt.")
        }
        let values: JSONObject = [
            "avatar_crop_x": crop.map { .number($0.x) } ?? .null,
            "avatar_crop_y": crop.map { .number($0.y) } ?? .null,
            "avatar_crop_width": crop.map { .number($0.width) } ?? .null,
            "avatar_crop_height": crop.map { .number($0.height) } ?? .null,
            "updated_at": .string(Self.isoString(from: .now))
        ]
        try await client.update(table: entity.kind.table, values: values, filters: [URLQueryItem(name: "id", value: "eq.\(entity.id.uuidString)")], accessToken: token)
        await logEntity(entity: entity, action: "native_editor_update_avatar_crop_\(entity.kind.rawValue)", actor: actor, after: values, token: token)
    }

    /// Feldparität mit venue-form.tsx — läuft bewusst über die bereits im
    /// Web-Admin genutzte update_venue()-RPC (siehe
    /// 20260825000001_entity_photo_uploads.sql), weil venues.location eine
    /// PostGIS-geography-Spalte ist, die ein einfaches PATCH nicht aus
    /// lat/lng zusammensetzen kann — die RPC übernimmt ST_MakePoint.
    func updateVenue(
        entity: EditorialEntity, name: String, slug: String, description: String,
        addressStreet: String, addressZip: String, addressCity: String,
        latitude: Double, longitude: Double, capacity: Int?, websiteURL: String, imageURL: String,
        actor: UUID, token: String
    ) async throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSlug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw EditorialError.validation("Der Venue-Name darf nicht leer sein.") }
        guard !cleanSlug.isEmpty else { throw EditorialError.validation("Der Slug darf nicht leer sein.") }
        guard !addressStreet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !addressZip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !addressCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw EditorialError.validation("Straße, PLZ und Stadt dürfen nicht leer sein.") }
        let cleanImage = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanImage.isEmpty, URL(string: cleanImage)?.scheme?.hasPrefix("http") != true {
            throw EditorialError.validation("Die Bildadresse muss mit http:// oder https:// beginnen.")
        }
        let parameters: JSONObject = [
            "p_id": .string(entity.id.uuidString),
            "p_slug": .string(cleanSlug),
            "p_name": .string(cleanName),
            "p_description_de": description.nilIfEmpty.map(JSONValue.string) ?? .null,
            "p_address_street": .string(addressStreet.trimmingCharacters(in: .whitespacesAndNewlines)),
            "p_address_zip": .string(addressZip.trimmingCharacters(in: .whitespacesAndNewlines)),
            "p_address_city": .string(addressCity.trimmingCharacters(in: .whitespacesAndNewlines)),
            "p_lat": .number(latitude),
            "p_lng": .number(longitude),
            "p_capacity": capacity.map { .number(Double($0)) } ?? .null,
            "p_website_url": websiteURL.nilIfEmpty.map(JSONValue.string) ?? .null,
            "p_photo_url": cleanImage.nilIfEmpty.map(JSONValue.string) ?? .null
        ]
        let _: JSONObject = try await client.rpc("update_venue", parameters: parameters, accessToken: token)
        await logEntity(entity: entity, action: "native_editor_update_venue", actor: actor, after: parameters, token: token)
    }

    /// Feldparität mit person-form.tsx — full_name wird wie im Web-Admin aus
    /// den drei Namensfeldern zusammengesetzt (full_name bleibt die einzige
    /// Quelle für Fuzzy-Matching, siehe dortiger Kommentar).
    /// Deckt ALLE Personenfelder ab (Basis + erweitert) — anders als bei
    /// Venue/Ensemble kein separater Aufruf für Name/Instrument/Bio/Foto,
    /// weil full_name aus firstName/middleName/lastName zusammengesetzt wird
    /// (siehe unten) und die generische updateEntity() sonst mit dem
    /// veralteten `title`-Zustand full_name überschreiben würde.
    func updatePersonDetails(
        entity: EditorialEntity, firstName: String, middleName: String, lastName: String, slug: String,
        instrument: String, biographyDe: String, imageURL: String,
        roles: [String], nationality: String, birthDate: String, deathDate: String, isDeceased: Bool,
        memberOfEnsembleID: UUID?, websiteURL: String, isVerified: Bool, actor: UUID, token: String
    ) async throws {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let middle = middleName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty, !last.isEmpty else { throw EditorialError.validation("Vor- und Nachname dürfen nicht leer sein.") }
        let cleanImage = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanImage.isEmpty, URL(string: cleanImage)?.scheme?.hasPrefix("http") != true {
            throw EditorialError.validation("Die Bildadresse muss mit http:// oder https:// beginnen.")
        }
        let fullName = [first, middle, last].filter { !$0.isEmpty }.joined(separator: " ")
        let values: JSONObject = [
            "first_name": .string(first),
            "middle_name": middle.isEmpty ? .null : .string(middle),
            "last_name": .string(last),
            "full_name": .string(fullName),
            "slug": .string(slug.trimmingCharacters(in: .whitespacesAndNewlines)),
            "instrument": instrument.nilIfEmpty.map(JSONValue.string) ?? .null,
            "biography_de": biographyDe.nilIfEmpty.map(JSONValue.string) ?? .null,
            "photo_url": cleanImage.nilIfEmpty.map(JSONValue.string) ?? .null,
            "roles": .array(roles.map(JSONValue.string)),
            "nationality": nationality.nilIfEmpty.map(JSONValue.string) ?? .null,
            "birth_date": birthDate.nilIfEmpty.map(JSONValue.string) ?? .null,
            "death_date": deathDate.nilIfEmpty.map(JSONValue.string) ?? .null,
            "is_deceased": .bool(isDeceased),
            "member_of_ensemble_id": memberOfEnsembleID.map { .string($0.uuidString) } ?? .null,
            "website_url": websiteURL.nilIfEmpty.map(JSONValue.string) ?? .null,
            "is_verified": .bool(isVerified),
            "updated_at": .string(Self.isoString(from: .now))
        ]
        try await client.update(table: "persons", values: values, filters: [URLQueryItem(name: "id", value: "eq.\(entity.id.uuidString)")], accessToken: token)
        await logEntity(entity: entity, action: "native_editor_update_person_details", actor: actor, after: values, token: token)
    }

    /// Feldparität mit ensemble-form.tsx.
    func updateEnsembleDetails(
        entity: EditorialEntity, slug: String, type: String, foundedYear: Int?, memberCount: Int?,
        homeVenueID: UUID?, parentEnsembleID: UUID?, websiteURL: String, isVerified: Bool, actor: UUID, token: String
    ) async throws {
        let values: JSONObject = [
            "slug": .string(slug.trimmingCharacters(in: .whitespacesAndNewlines)),
            "type": .string(type),
            "founded_year": foundedYear.map { .number(Double($0)) } ?? .null,
            "member_count": memberCount.map { .number(Double($0)) } ?? .null,
            "home_venue_id": homeVenueID.map { .string($0.uuidString) } ?? .null,
            "parent_ensemble_id": parentEnsembleID.map { .string($0.uuidString) } ?? .null,
            "website_url": websiteURL.nilIfEmpty.map(JSONValue.string) ?? .null,
            "is_verified": .bool(isVerified),
            "updated_at": .string(Self.isoString(from: .now))
        ]
        try await client.update(table: "ensembles", values: values, filters: [URLQueryItem(name: "id", value: "eq.\(entity.id.uuidString)")], accessToken: token)
        await logEntity(entity: entity, action: "native_editor_update_ensemble_details", actor: actor, after: values, token: token)
    }

    /// Venue-Pendant zu createEntity() (das für .venue bewusst ablehnt, siehe
    /// dortiger Kommentar) — Venues brauchen zwingend Adresse+Geodaten und
    /// laufen deshalb über die schon für updateVenue() genutzte create_venue-
    /// RPC statt eines einfachen INSERT (venues.location ist eine PostGIS
    /// geography-Spalte, die RPC übernimmt ST_MakePoint).
    func createVenue(
        name: String, addressStreet: String, addressZip: String, addressCity: String,
        description: String, latitude: Double, longitude: Double,
        capacity: Int?, websiteURL: String, imageURL: String,
        actor: UUID, token: String
    ) async throws -> EditorialEntity {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw EditorialError.validation("Der Venue-Name darf nicht leer sein.") }
        guard !addressStreet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !addressZip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !addressCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw EditorialError.validation("Straße, PLZ und Stadt dürfen nicht leer sein.") }
        let cleanImage = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanImage.isEmpty, URL(string: cleanImage)?.scheme?.hasPrefix("http") != true {
            throw EditorialError.validation("Die Bildadresse muss mit http:// oder https:// beginnen.")
        }
        let parameters: JSONObject = [
            "p_slug": .string(uniqueSlug(for: cleanName)),
            "p_name": .string(cleanName),
            "p_description_de": description.nilIfEmpty.map(JSONValue.string) ?? .null,
            "p_address_street": .string(addressStreet.trimmingCharacters(in: .whitespacesAndNewlines)),
            "p_address_zip": .string(addressZip.trimmingCharacters(in: .whitespacesAndNewlines)),
            "p_address_city": .string(addressCity.trimmingCharacters(in: .whitespacesAndNewlines)),
            "p_lat": .number(latitude),
            "p_lng": .number(longitude),
            "p_capacity": capacity.map { .number(Double($0)) } ?? .null,
            "p_website_url": websiteURL.nilIfEmpty.map(JSONValue.string) ?? .null,
            "p_photo_url": cleanImage.nilIfEmpty.map(JSONValue.string) ?? .null
        ]
        let row: JSONObject = try await client.rpc("create_venue", parameters: parameters, accessToken: token)
        guard let id = row.string("id").flatMap(UUID.init(uuidString:)) else { throw APIError.invalidResponse }
        await logNewEntity(kind: .venue, id: id, actor: actor, after: parameters, token: token)
        return EditorialEntity(
            id: id, kind: .venue, title: cleanName,
            subtitle: nil, editableSubtitle: nil, description: description.nilIfEmpty,
            imageURL: cleanImage.nilIfEmpty, composerID: nil,
            slug: row.string("slug"), websiteURL: websiteURL.nilIfEmpty,
            addressStreet: addressStreet, addressZip: addressZip, addressCity: addressCity,
            latitude: latitude, longitude: longitude, capacity: capacity
        )
    }

    func createEntity(kind: EditorialEntityKind, title: String, subtitle: String, description: String, imageURL: String, composerID: UUID?, actor: UUID, token: String) async throws -> EditorialEntity {
        guard kind == .person || kind == .ensemble || kind == .work else {
            throw EditorialError.validation("Dieser Eintragstyp kann hier nicht neu angelegt werden.")
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw EditorialError.validation("Name bzw. Titel darf nicht leer sein.") }
        let cleanImage = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanImage.isEmpty, URL(string: cleanImage)?.scheme?.hasPrefix("http") != true {
            throw EditorialError.validation("Die Bildadresse muss mit http:// oder https:// beginnen.")
        }

        if kind == .ensemble {
            let resolved: [JSONObject] = try await client.rpc(
                "resolve_ensemble_entities",
                parameters: ["p_name": .string(cleanTitle)],
                accessToken: token
            )
            let canonical = resolved.filter { $0.string("id") != nil }
            if resolved.contains(where: { $0.string("resolution") == "ignore" }) {
                throw EditorialError.validation("Diese Bezeichnung beschreibt kein festes Ensemble und wird deshalb nicht als Stammdatensatz angelegt.")
            }
            if resolved.contains(where: { $0.string("resolution") == "ambiguous" }) {
                throw EditorialError.validation("Diese Bezeichnung ist innerhalb der Ensemblefamilie nicht eindeutig. Bitte das konkrete Unterensemble auswählen.")
            }
            if canonical.count > 1 {
                let names = canonical.compactMap { $0.string("name") }.joined(separator: ", ")
                throw EditorialError.validation("Diese Sammelbezeichnung wird bereits automatisch aufgelöst: \(names). Bitte die Unterensembles einzeln auswählen.")
            }
            if let match = canonical.first,
               let id = match.string("id").flatMap(UUID.init(uuidString:)),
               let canonicalName = match.string("name") {
                return EditorialEntity(
                    id: id, kind: kind, title: canonicalName,
                    subtitle: nil, editableSubtitle: nil, description: nil,
                    imageURL: nil, composerID: nil
                )
            }
        }

        // Eine in der nativen Redaktion eingegebene Alternativschreibweise
        // darf keinen zweiten Stammdatensatz erzeugen. Personen und noch nicht
        // als Familie erkannte Ensemble-Namen werden zentral aufgelöst.
        if kind == .person || kind == .ensemble {
            let matches: [JSONObject] = try await client.rpc(
                "resolve_entity_alias",
                parameters: [
                    "p_entity_type": .string(kind.rawValue),
                    "p_name": .string(cleanTitle)
                ],
                accessToken: token
            )
            if let match = matches.first,
               let id = match.string("id").flatMap(UUID.init(uuidString:)),
               let canonicalName = match.string("canonical_name") {
                return EditorialEntity(
                    id: id, kind: kind, title: canonicalName,
                    subtitle: nil, editableSubtitle: nil, description: nil,
                    imageURL: nil, composerID: nil
                )
            }
        }

        var values: JSONObject
        switch kind {
        case .person:
            values = [
                "slug": .string(uniqueSlug(for: cleanTitle)), "full_name": .string(cleanTitle),
                "instrument": subtitle.nilIfEmpty.map(JSONValue.string) ?? .null,
                "biography_de": description.nilIfEmpty.map(JSONValue.string) ?? .null,
                "photo_url": cleanImage.nilIfEmpty.map(JSONValue.string) ?? .null,
                "is_verified": .bool(false)
            ]
        case .ensemble:
            values = [
                "slug": .string(uniqueSlug(for: cleanTitle)), "name": .string(cleanTitle), "type": .string("sonstiges"),
                "description_de": description.nilIfEmpty.map(JSONValue.string) ?? .null,
                "photo_url": cleanImage.nilIfEmpty.map(JSONValue.string) ?? .null,
                "is_verified": .bool(false)
            ]
        case .work:
            values = [
                "title": .string(cleanTitle),
                "catalog_number": subtitle.nilIfEmpty.map(JSONValue.string) ?? .null,
                "description_de": description.nilIfEmpty.map(JSONValue.string) ?? .null,
                "composer_id": composerID.map { .string($0.uuidString) } ?? .null
            ]
        case .venue:
            throw EditorialError.validation("Venues benötigen Adresse und Geodaten und werden weiterhin im vollständigen Admin-Portal angelegt.")
        }

        let rows = try await client.insert(table: kind.table, values: values, accessToken: token, returning: true)
        guard let id = rows.first?.string("id").flatMap(UUID.init(uuidString:)) else { throw APIError.invalidResponse }
        await logNewEntity(kind: kind, id: id, actor: actor, after: values, token: token)
        return EditorialEntity(
            id: id, kind: kind, title: cleanTitle,
            subtitle: subtitle.nilIfEmpty,
            editableSubtitle: subtitle.nilIfEmpty, description: description.nilIfEmpty,
            imageURL: cleanImage.nilIfEmpty, composerID: composerID
        )
    }

    /// Löscht Venue/Person/Ensemble über die serverseitigen delete_*-RPCs
    /// (siehe 20261013000012/13_editorial_delete_rpcs*.sql) — die lösen dort
    /// zentral alle Fremdschlüssel-Bezüge, statt die mehrschrittige
    /// Reihenfolge hier in Swift zu duplizieren (Fehlerrisiko bei fehlenden
    /// ON DELETE CASCADE-Constraints). Werke sind hier bewusst nicht
    /// löschbar (Nutzervorgabe nannte nur Venues/Ensembles/Personen/
    /// Veranstaltungen) — die Duplikate-Zusammenführung im Web-Admin bleibt
    /// der richtige Weg, ein Werk verschwinden zu lassen.
    func deleteEntity(_ entity: EditorialEntity, actor: UUID, token: String) async throws {
        let function: String
        let parameterKey: String
        switch entity.kind {
        case .venue: function = "delete_venue"; parameterKey = "p_venue_id"
        case .person: function = "delete_person"; parameterKey = "p_person_id"
        case .ensemble: function = "delete_ensemble"; parameterKey = "p_ensemble_id"
        case .work: throw EditorialError.validation("Werke können hier nicht gelöscht werden — dafür die Werk-Duplikate-Zusammenführung im Web-Admin-Portal nutzen.")
        }
        let _: Bool = try await client.rpc(function, parameters: [parameterKey: .string(entity.id.uuidString)], accessToken: token)
        await logEntity(entity: entity, action: "native_editor_delete_\(entity.kind.rawValue)", actor: actor, after: [:], token: token)
    }

    /// Löscht eine Veranstaltung über delete_event() — räumt dabei auch eine
    /// jetzt leer gewordene Event-Gruppe (programs) mit auf, siehe
    /// Kommentar in der Migration.
    func deleteEvent(_ event: EditorialEvent, actor: UUID, token: String) async throws {
        let _: Bool = try await client.rpc("delete_event", parameters: ["p_event_id": .string(event.id.uuidString)], accessToken: token)
        await log(eventID: event.id, action: "native_editor_delete_event", actor: actor, before: snapshot(event), after: nil, token: token)
    }

    /// select um Feldparität mit event-form.tsx erweitert; event_genres ist
    /// eine separate Verknüpfungstabelle (kein Spaltenwert), daher ein
    /// eigener paralleler Abruf, dessen genre_ids anschließend ins Event
    /// gemergt werden.
    func detail(eventID: UUID, token: String) async throws -> EditorialEventDetail {
        let eventRows: [JSONObject] = try await client.get(table: "events", queryItems: [
            URLQueryItem(name: "select", value: "id,slug,title,subtitle,description_de,start_datetime,duration_minutes,has_intermission,venue_id,organizer_id,image_urls,ticket_url,price_min,price_max,is_free,remaining_tickets_status,doors_info,age_restriction,discount_info,presale_fee_info,status,venues(name)"),
            URLQueryItem(name: "id", value: "eq.\(eventID.uuidString)"),
            URLQueryItem(name: "limit", value: "1")
        ], accessToken: token)
        guard var event = eventRows.first.flatMap(Self.event) else { throw APIError.invalidResponse }

        async let participantRows: [JSONObject] = client.get(table: "event_participants", queryItems: [
            URLQueryItem(name: "select", value: "id,person_id,ensemble_id,role,role_label,display_order,persons(full_name),ensembles(name)"),
            URLQueryItem(name: "event_id", value: "eq.\(eventID.uuidString)"),
            URLQueryItem(name: "order", value: "display_order.asc")
        ], accessToken: token)
        async let workRows: [JSONObject] = client.get(table: "event_works", queryItems: [
            URLQueryItem(name: "select", value: "work_id,position,works(title,catalog_number,description_de,composer_id,composer:persons(full_name))"),
            URLQueryItem(name: "event_id", value: "eq.\(eventID.uuidString)"),
            URLQueryItem(name: "order", value: "position.asc")
        ], accessToken: token)
        async let genreRows: [JSONObject] = client.get(table: "event_genres", queryItems: [
            URLQueryItem(name: "select", value: "genre_id"),
            URLQueryItem(name: "event_id", value: "eq.\(eventID.uuidString)")
        ], accessToken: token)

        event.genreIDs = try await genreRows.compactMap { $0.string("genre_id").flatMap(UUID.init(uuidString:)) }

        return try await EditorialEventDetail(
            event: event,
            participants: participantRows.compactMap(Self.participant),
            works: workRows.compactMap(Self.work)
        )
    }

    func venues(token: String) async throws -> [EditorialOption] {
        try await options(table: "venues", selection: "id,name", titleKey: "name", token: token)
    }

    /// Nicht-blockierende Dublettenwarnung während des Tippens in
    /// EditorialCreateVenueView — die harte Sperre passiert zusätzlich
    /// serverseitig beim Speichern (RLS/Constraints bleiben unverändert).
    func findMatchingVenues(name: String, token: String) async throws -> [EditorialOption] {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanName.count >= 3 else { return [] }
        let rows: [JSONObject] = try await client.get(table: "venues", queryItems: [
            URLQueryItem(name: "select", value: "id,name"),
            URLQueryItem(name: "name", value: "ilike.*\(cleanName)*"),
            URLQueryItem(name: "limit", value: "5")
        ], accessToken: token)
        return rows.compactMap { row in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)), let title = row.string("name") else { return nil }
            return EditorialOption(id: id, title: title, subtitle: nil)
        }
    }

    func persons(token: String) async throws -> [EditorialOption] {
        try await options(table: "persons", selection: "id,full_name,instrument", titleKey: "full_name", subtitleKey: "instrument", token: token)
    }

    func ensembles(token: String) async throws -> [EditorialOption] {
        try await options(
            table: "ensembles", selection: "id,name,type", titleKey: "name", subtitleKey: "type", token: token,
            filters: [
                URLQueryItem(name: "is_resolution_placeholder", value: "eq.false"),
                URLQueryItem(name: "is_family_root", value: "eq.false")
            ]
        )
    }

    func organizers(token: String) async throws -> [EditorialOption] {
        try await options(table: "organizers", selection: "id,name", titleKey: "name", token: token)
    }

    func genres(token: String) async throws -> [EditorialOption] {
        try await options(table: "genres", selection: "id,label_de", titleKey: "label_de", token: token)
    }

    func works(token: String) async throws -> [EditorialOption] {
        let rows: [JSONObject] = try await client.get(table: "works", queryItems: [
            URLQueryItem(name: "select", value: "id,title,composer:persons(full_name)"),
            URLQueryItem(name: "order", value: "title.asc"),
            URLQueryItem(name: "limit", value: "2000")
        ], accessToken: token)
        return rows.compactMap { row in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)), let title = row.string("title") else { return nil }
            return EditorialOption(id: id, title: title, subtitle: row.object("composer")?.string("full_name"))
        }
    }

    func updateBasics(
        event: EditorialEvent,
        title: String,
        subtitle: String,
        startDate: Date,
        venueID: UUID,
        imageURL: String,
        actor: UUID,
        token: String
    ) async throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw EditorialError.validation("Der Titel darf nicht leer sein.") }
        let cleanImage = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanImage.isEmpty, URL(string: cleanImage)?.scheme?.hasPrefix("http") != true {
            throw EditorialError.validation("Die Bildadresse muss mit http:// oder https:// beginnen.")
        }
        let before = snapshot(event)
        let gallery = try await galleryImages(originType: "event", originID: event.id, token: token)
        let imageURLs = gallery.isEmpty ? (cleanImage.isEmpty ? [] : [cleanImage]) : gallery.map(\.url)
        let values: JSONObject = [
            "title": .string(cleanTitle),
            "subtitle": subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .null : .string(subtitle.trimmingCharacters(in: .whitespacesAndNewlines)),
            "start_datetime": .string(Self.isoString(from: startDate)),
            "venue_id": .string(venueID.uuidString),
            "image_urls": .array(imageURLs.map(JSONValue.string)),
            "updated_at": .string(Self.isoString(from: .now))
        ]
        try await client.update(table: "events", values: values, filters: [URLQueryItem(name: "id", value: "eq.\(event.id.uuidString)")], accessToken: token)
        await log(eventID: event.id, action: "native_editor_quick_update", actor: actor, before: before, after: values, token: token)
    }

    /// Feldparität mit event-form.tsx, ergänzend zu updateBasics() (dort
    /// bleiben Titel/Untertitel/Termin/Venue/Bild als "Schnellkorrektur"
    /// unverändert) — eigene Funktion für die übrigen Felder (Beschreibung,
    /// Dauer, Pause, Veranstalter, Genres, Preise, Ticket-Infos, Status),
    /// damit die bestehende Schnellkorrektur nicht mit einem noch größeren
    /// Parametersatz überladen wird. genre_ids werden komplett neu
    /// geschrieben (löschen + neu einfügen), wie syncGenres() im Web-Admin.
    func updateEventDetails(
        event: EditorialEvent, descriptionDe: String, durationMinutes: Int?, hasIntermission: Bool,
        organizerID: UUID?, genreIDs: [UUID], priceMin: Double?, priceMax: Double?, isFree: Bool,
        ticketURL: String, remainingTicketsStatus: String, doorsInfo: String, ageRestriction: String,
        discountInfo: String, presaleFeeInfo: String, status: String, actor: UUID, token: String
    ) async throws {
        let values: JSONObject = [
            "description_de": descriptionDe.nilIfEmpty.map(JSONValue.string) ?? .null,
            "duration_minutes": durationMinutes.map { .number(Double($0)) } ?? .null,
            "has_intermission": .bool(hasIntermission),
            "organizer_id": organizerID.map { .string($0.uuidString) } ?? .null,
            "price_min": priceMin.map(JSONValue.number) ?? .null,
            "price_max": priceMax.map(JSONValue.number) ?? .null,
            "is_free": .bool(isFree),
            "ticket_url": ticketURL.nilIfEmpty.map(JSONValue.string) ?? .null,
            "remaining_tickets_status": remainingTicketsStatus.nilIfEmpty.map(JSONValue.string) ?? .null,
            "doors_info": doorsInfo.nilIfEmpty.map(JSONValue.string) ?? .null,
            "age_restriction": ageRestriction.nilIfEmpty.map(JSONValue.string) ?? .null,
            "discount_info": discountInfo.nilIfEmpty.map(JSONValue.string) ?? .null,
            "presale_fee_info": presaleFeeInfo.nilIfEmpty.map(JSONValue.string) ?? .null,
            "status": .string(status),
            "updated_at": .string(Self.isoString(from: .now))
        ]
        try await client.update(table: "events", values: values, filters: [URLQueryItem(name: "id", value: "eq.\(event.id.uuidString)")], accessToken: token)

        try await client.delete(table: "event_genres", filters: [URLQueryItem(name: "event_id", value: "eq.\(event.id.uuidString)")], accessToken: token)
        for genreID in genreIDs {
            _ = try await client.insert(table: "event_genres", values: ["event_id": .string(event.id.uuidString), "genre_id": .string(genreID.uuidString)], accessToken: token)
        }

        await log(eventID: event.id, action: "native_editor_update_event_details", actor: actor, before: nil, after: values, token: token)
    }

    func deleteEventImages(event: EditorialEvent, actor: UUID, token: String) async throws {
        let before: JSONObject = ["image_urls": .array(event.imageURL.map { [.string($0)] } ?? [])]
        try await client.update(
            table: "events",
            values: ["image_urls": .array([]), "primary_image_id": .null, "updated_at": .string(Self.isoString(from: .now))],
            filters: [URLQueryItem(name: "id", value: "eq.\(event.id.uuidString)")],
            accessToken: token
        )
        try await client.delete(table: "images", filters: [
            URLQueryItem(name: "origin_type", value: "eq.event"),
            URLQueryItem(name: "origin_id", value: "eq.\(event.id.uuidString)")
        ], accessToken: token)
        await log(eventID: event.id, action: "native_editor_delete_event_images", actor: actor, before: before, after: ["image_urls": .array([])], token: token)
    }

    func addParticipant(eventID: UUID, option: EditorialOption, type: String, role: String, actor: UUID, token: String) async throws {
        var values: JSONObject = ["event_id": .string(eventID.uuidString), "role_label": role.isEmpty ? .null : .string(role)]
        values[type == "person" ? "person_id" : "ensemble_id"] = .string(option.id.uuidString)
        _ = try await client.insert(table: "event_participants", values: values, accessToken: token)
        await log(eventID: eventID, action: "native_editor_add_participant", actor: actor, before: nil, after: values, token: token)
    }

    func removeParticipant(eventID: UUID, participant: EditorialParticipant, actor: UUID, token: String) async throws {
        try await client.delete(table: "event_participants", filters: [URLQueryItem(name: "id", value: "eq.\(participant.id.uuidString)")], accessToken: token)
        await log(eventID: eventID, action: "native_editor_remove_participant", actor: actor, before: ["name": .string(participant.name)], after: nil, token: token)
    }

    func addWork(eventID: UUID, option: EditorialOption, position: Int, actor: UUID, token: String) async throws {
        let values: JSONObject = ["event_id": .string(eventID.uuidString), "work_id": .string(option.id.uuidString), "position": .number(Double(position))]
        _ = try await client.insert(table: "event_works", values: values, accessToken: token)
        await log(eventID: eventID, action: "native_editor_add_work", actor: actor, before: nil, after: values, token: token)
    }

    func removeWork(eventID: UUID, link: EditorialWorkLink, actor: UUID, token: String) async throws {
        try await client.delete(table: "event_works", filters: [
            URLQueryItem(name: "event_id", value: "eq.\(eventID.uuidString)"),
            URLQueryItem(name: "work_id", value: "eq.\(link.workID.uuidString)"),
            URLQueryItem(name: "position", value: "eq.\(link.position)")
        ], accessToken: token)
        await log(eventID: eventID, action: "native_editor_remove_work", actor: actor, before: ["title": .string(link.title)], after: nil, token: token)
    }

    private func options(table: String, selection: String, titleKey: String, subtitleKey: String? = nil, token: String, filters: [URLQueryItem] = []) async throws -> [EditorialOption] {
        let rows: [JSONObject] = try await client.get(table: table, queryItems: [
            URLQueryItem(name: "select", value: selection),
            URLQueryItem(name: "order", value: "\(titleKey).asc"),
            URLQueryItem(name: "limit", value: "2000")
        ] + filters, accessToken: token)
        return rows.compactMap { row in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)), let title = row.string(titleKey) else { return nil }
            return EditorialOption(id: id, title: title, subtitle: subtitleKey.flatMap(row.string))
        }
    }

    private func log(eventID: UUID, action: String, actor: UUID, before: JSONObject?, after: JSONObject?, token: String) async {
        var values: JSONObject = [
            "entity_type": .string("event"), "entity_id": .string(eventID.uuidString),
            "action": .string(action), "actor": .string(actor.uuidString)
        ]
        values["before"] = before.map(JSONValue.object) ?? .null
        values["after"] = after.map(JSONValue.object) ?? .null
        _ = try? await client.insert(table: "system_logs", values: values, accessToken: token)
    }

    private func logEntity(entity: EditorialEntity, action: String, actor: UUID, after: JSONObject, token: String) async {
        let before: JSONObject = ["title": .string(entity.title), "subtitle": entity.editableSubtitle.map(JSONValue.string) ?? .null,
                                  "description": entity.description.map(JSONValue.string) ?? .null, "image_url": entity.imageURL.map(JSONValue.string) ?? .null]
        let values: JSONObject = ["entity_type": .string(entity.kind.rawValue), "entity_id": .string(entity.id.uuidString),
                                  "action": .string(action), "actor": .string(actor.uuidString), "before": .object(before), "after": .object(after)]
        _ = try? await client.insert(table: "system_logs", values: values, accessToken: token)
    }

    private func logNewEntity(kind: EditorialEntityKind, id: UUID, actor: UUID, after: JSONObject, token: String) async {
        let values: JSONObject = ["entity_type": .string(kind.rawValue), "entity_id": .string(id.uuidString),
                                  "action": .string("native_editor_create_\(kind.rawValue)"), "actor": .string(actor.uuidString),
                                  "before": .null, "after": .object(after)]
        _ = try? await client.insert(table: "system_logs", values: values, accessToken: token)
    }

    private func logGallery(originType: String, originID: UUID, action: String, actor: UUID, count: Int, token: String) async {
        let values: JSONObject = [
            "entity_type": .string(originType), "entity_id": .string(originID.uuidString),
            "action": .string(action), "actor": .string(actor.uuidString),
            "after": .object(["image_count": .number(Double(count))])
        ]
        _ = try? await client.insert(table: "system_logs", values: values, accessToken: token)
    }

    private func syncLegacyPrimary(originType: String, originID: UUID, images: [EditorialGalleryImage], token: String) async throws {
        let firstURL = images.first?.url
        switch originType {
        case "event":
            try await client.update(table: "events", values: [
                "image_urls": .array(images.map { .string($0.url) }),
                "primary_image_id": images.first.map { .string($0.id.uuidString) } ?? .null,
                "updated_at": .string(Self.isoString(from: .now))
            ], filters: [URLQueryItem(name: "id", value: "eq.\(originID.uuidString)")], accessToken: token)
        case "venue":
            try await client.update(table: "venues", values: [
                "photo_url": firstURL.map(JSONValue.string) ?? .null,
                "updated_at": .string(Self.isoString(from: .now))
            ], filters: [URLQueryItem(name: "id", value: "eq.\(originID.uuidString)")], accessToken: token)
        case "person", "ensemble":
            // Profilfoto und Bildergalerie sind bewusst getrennt. Das erste
            // Galeriebild darf photo_url niemals ersetzen; dieses Feld treibt
            // alle runden und großen Künstler-/Ensemble-Miniaturen.
            break
        default:
            break
        }
    }

    private func uniqueSlug(for title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "ß", with: "ss")
            .lowercased()
        let base = folded.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(base.isEmpty ? "eintrag" : String(base.prefix(64)))-\(UUID().uuidString.lowercased().prefix(8))"
    }

    private func snapshot(_ event: EditorialEvent) -> JSONObject {
        ["title": .string(event.title), "subtitle": event.subtitle.map(JSONValue.string) ?? .null,
         "start_datetime": .string(Self.isoString(from: event.startDate)), "venue_id": .string(event.venueID.uuidString),
         "image_urls": .array(event.imageURL.map { [.string($0)] } ?? [])]
    }

    private static func event(_ row: JSONObject) -> EditorialEvent? {
        guard let id = row.string("id").flatMap(UUID.init(uuidString:)), let slug = row.string("slug"),
              let title = row.string("title"), let date = row.string("start_datetime").flatMap(FlexibleDateParser.date),
              let venueID = row.string("venue_id").flatMap(UUID.init(uuidString:)) else { return nil }
        var event = EditorialEvent(id: id, slug: slug, title: title, subtitle: row.string("subtitle"), startDate: date,
                              venueID: venueID, venueName: row.object("venues")?.string("name") ?? "Unbekannter Ort",
                              imageURL: row.strings("image_urls").first, status: row.string("status") ?? "scheduled")
        event.descriptionDe = row.string("description_de")
        event.durationMinutes = row.integer("duration_minutes")
        event.hasIntermission = row.bool("has_intermission") ?? false
        event.organizerID = row.string("organizer_id").flatMap(UUID.init(uuidString:))
        event.ticketURL = row.string("ticket_url")
        event.priceMin = row.number("price_min")
        event.priceMax = row.number("price_max")
        event.isFree = row.bool("is_free") ?? false
        event.remainingTicketsStatus = row.string("remaining_tickets_status")
        event.doorsInfo = row.string("doors_info")
        event.ageRestriction = row.string("age_restriction")
        event.discountInfo = row.string("discount_info")
        event.presaleFeeInfo = row.string("presale_fee_info")
        return event
    }

    private static func participant(_ row: JSONObject) -> EditorialParticipant? {
        guard let id = row.string("id").flatMap(UUID.init(uuidString:)) else { return nil }
        if let entityID = row.string("person_id").flatMap(UUID.init(uuidString:)), let name = row.object("persons")?.string("full_name") {
            return EditorialParticipant(id: id, entityID: entityID, entityType: "person", name: name, roleLabel: row.string("role_label") ?? row.string("role"))
        }
        guard let entityID = row.string("ensemble_id").flatMap(UUID.init(uuidString:)), let name = row.object("ensembles")?.string("name") else { return nil }
        return EditorialParticipant(id: id, entityID: entityID, entityType: "ensemble", name: name, roleLabel: row.string("role_label") ?? row.string("role"))
    }

    private static func work(_ row: JSONObject) -> EditorialWorkLink? {
        guard let id = row.string("work_id").flatMap(UUID.init(uuidString:)), let position = row.integer("position"),
              let work = row.object("works"), let title = work.string("title") else { return nil }
        return EditorialWorkLink(
            workID: id,
            title: title,
            composer: work.object("composer")?.string("full_name"),
            catalogNumber: work.string("catalog_number"),
            description: work.string("description_de"),
            composerID: work.string("composer_id").flatMap(UUID.init(uuidString:)),
            position: position
        )
    }

    private static func isoString(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let clean = trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}

enum EditorialError: LocalizedError {
    case validation(String)
    var errorDescription: String? { if case let .validation(message) = self { message } else { nil } }
}
