import Foundation

enum EditorialEntityKind: String, CaseIterable, Identifiable, Sendable {
    case venue, person, ensemble, work
    var id: String { rawValue }
    var title: String { switch self { case .venue: "Venues"; case .person: "Personen"; case .ensemble: "Ensembles"; case .work: "Werke" } }
    var singularTitle: String { switch self { case .venue: "Venue"; case .person: "Person"; case .ensemble: "Ensemble"; case .work: "Werk" } }
    var symbol: String { switch self { case .venue: "building.columns"; case .person: "person"; case .ensemble: "person.3"; case .work: "music.note" } }
    var table: String { switch self { case .venue: "venues"; case .person: "persons"; case .ensemble: "ensembles"; case .work: "works" } }
}

struct EditorialEntity: Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: EditorialEntityKind
    let title: String
    let subtitle: String?
    let editableSubtitle: String?
    let description: String?
    let imageURL: String?
    let composerID: UUID?
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

struct EditorialRepository: Sendable {
    let client: SupabaseRESTClient

    func hasAccess(token: String) async -> Bool {
        let result: Bool? = try? await client.rpc("is_admin_or_editor", accessToken: token)
        return result == true
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

    func events(search: String, token: String) async throws -> [EditorialEvent] {
        var query = [
            URLQueryItem(name: "select", value: "id,slug,title,subtitle,start_datetime,venue_id,image_urls,status,venues(name)"),
            URLQueryItem(name: "start_datetime", value: "gte.\(Self.isoString(from: KlangradarDateTime.calendar.startOfDay(for: .now)))"),
            URLQueryItem(name: "order", value: "start_datetime.asc"),
            URLQueryItem(name: "limit", value: "150")
        ]
        let clean = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            let escaped = clean.replacingOccurrences(of: ",", with: " ")
            query.append(URLQueryItem(name: "or", value: "(title.ilike.*\(escaped)*,subtitle.ilike.*\(escaped)*)"))
        }
        let rows: [JSONObject] = try await client.get(table: "events", queryItems: query, accessToken: token)
        return rows.compactMap(Self.event)
    }

    func entities(kind: EditorialEntityKind, token: String) async throws -> [EditorialEntity] {
        let selection: String
        let order: String
        switch kind {
        case .venue: selection = "id,name,address_city,description_de,photo_url"; order = "name.asc"
        case .person: selection = "id,full_name,instrument,biography_de,photo_url"; order = "full_name.asc"
        case .ensemble: selection = "id,name,type,description_de,photo_url"; order = "name.asc"
        case .work: selection = "id,title,catalog_number,description_de,composer_id,composer:persons(full_name)"; order = "title.asc"
        }
        let rows: [JSONObject] = try await client.get(table: kind.table, queryItems: [
            URLQueryItem(name: "select", value: selection),
            URLQueryItem(name: "order", value: order),
            URLQueryItem(name: "limit", value: "3000")
        ], accessToken: token)
        return rows.compactMap { row in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)), let title = row.string(kind == .person ? "full_name" : kind == .work ? "title" : "name") else { return nil }
            let subtitle: String? = switch kind {
            case .venue: row.string("address_city")
            case .person: row.string("instrument")
            case .ensemble: row.string("type")
            case .work: [row.object("composer")?.string("full_name"), row.string("catalog_number")].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
            }
            return EditorialEntity(
                id: id, kind: kind, title: title, subtitle: subtitle, editableSubtitle: kind == .work ? row.string("catalog_number") : subtitle,
                description: row.string(kind == .person ? "biography_de" : "description_de"),
                imageURL: row.string("photo_url"), composerID: row.string("composer_id").flatMap(UUID.init(uuidString:))
            )
        }
    }

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

    func detail(eventID: UUID, token: String) async throws -> EditorialEventDetail {
        let eventRows: [JSONObject] = try await client.get(table: "events", queryItems: [
            URLQueryItem(name: "select", value: "id,slug,title,subtitle,start_datetime,venue_id,image_urls,status,venues(name)"),
            URLQueryItem(name: "id", value: "eq.\(eventID.uuidString)"),
            URLQueryItem(name: "limit", value: "1")
        ], accessToken: token)
        guard let event = eventRows.first.flatMap(Self.event) else { throw APIError.invalidResponse }

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

        return try await EditorialEventDetail(
            event: event,
            participants: participantRows.compactMap(Self.participant),
            works: workRows.compactMap(Self.work)
        )
    }

    func venues(token: String) async throws -> [EditorialOption] {
        try await options(table: "venues", selection: "id,name", titleKey: "name", token: token)
    }

    func persons(token: String) async throws -> [EditorialOption] {
        try await options(table: "persons", selection: "id,full_name,instrument", titleKey: "full_name", subtitleKey: "instrument", token: token)
    }

    func ensembles(token: String) async throws -> [EditorialOption] {
        try await options(table: "ensembles", selection: "id,name,type", titleKey: "name", subtitleKey: "type", token: token)
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

    private func options(table: String, selection: String, titleKey: String, subtitleKey: String? = nil, token: String) async throws -> [EditorialOption] {
        let rows: [JSONObject] = try await client.get(table: table, queryItems: [
            URLQueryItem(name: "select", value: selection),
            URLQueryItem(name: "order", value: "\(titleKey).asc"),
            URLQueryItem(name: "limit", value: "2000")
        ], accessToken: token)
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
        return EditorialEvent(id: id, slug: slug, title: title, subtitle: row.string("subtitle"), startDate: date,
                              venueID: venueID, venueName: row.object("venues")?.string("name") ?? "Unbekannter Ort",
                              imageURL: row.strings("image_urls").first, status: row.string("status") ?? "scheduled")
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
