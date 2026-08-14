import Foundation

protocol ContentRepository: Sendable {
    func directory(kind: EntityKind) async throws -> [DirectoryItem]
    func detail(kind: EntityKind, identifier: String) async throws -> EntityDetail?
    func collections() async throws -> [EditorialCollection]
    func collection(slug: String) async throws -> EditorialCollection?
    func search(query: String, limit: Int) async throws -> [SearchHit]
    func venueLocations() async throws -> [VenueLocation]
    func venueEvents(venueID: UUID, limit: Int) async throws -> [ConcertEvent]
}

struct LiveContentRepository: ContentRepository {
    let client: SupabaseRESTClient

    func directory(kind: EntityKind) async throws -> [DirectoryItem] {
        let specification = directorySpecification(for: kind)
        var rows: [JSONObject] = []
        let pageSize = 500
        while true {
            var queryItems = [
                URLQueryItem(name: "select", value: specification.select),
                URLQueryItem(name: "order", value: "\(specification.order).asc"),
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(rows.count))
            ]
            if kind == .ensemble {
                queryItems.append(URLQueryItem(name: "is_resolution_placeholder", value: "eq.false"))
            }
            let page: [JSONObject] = try await client.get(
                table: specification.table,
                queryItems: queryItems
            )
            rows.append(contentsOf: page)
            if page.count < pageSize { break }
        }
        return await enrichingDirectoryImages(
            rows.compactMap { directoryItem(from: $0, kind: kind) },
            kind: kind
        )
    }

    private func enrichingDirectoryImages(_ items: [DirectoryItem], kind: EntityKind) async -> [DirectoryItem] {
        guard kind != .work else { return items }
        // Ensembles/Venues: das Admin-Galerie-Titelbild (sort_order 0) ist
        // verbindlich für Miniaturansicht UND Detailansicht und hat Vorrang
        // vor dem separaten photo_url-Feld — sonst änderte "Als Titelbild"
        // in der Admin-Galerie sichtbar nichts in der App (siehe analoger
        // Fix in app/lib/features/search/application/directory_providers.dart,
        // applyDirectoryCoverGalleryFirst). Bei Personen bleibt photo_url
        // weiterhin verbindlich, die Galerie nur Fallback bei fehlendem Foto.
        let galleryFirst = kind == .ensemble || kind == .venue
        let targetIDs = galleryFirst
            ? items.compactMap { UUID(uuidString: $0.id) }
            : items.filter { $0.imageURL == nil }.compactMap { UUID(uuidString: $0.id) }
        guard !targetIDs.isEmpty else { return items }

        var imageRows: [JSONObject] = []
        for start in stride(from: 0, to: targetIDs.count, by: 75) {
            let chunk = targetIDs[start..<min(start + 75, targetIDs.count)]
            let rows: [JSONObject]? = try? await client.get(table: "images", queryItems: [
                URLQueryItem(name: "select", value: "origin_id,storage_path,source_url,sort_order"),
                URLQueryItem(name: "origin_type", value: "eq.\(kind.rawValue)"),
                URLQueryItem(name: "origin_id", value: "in.(\(chunk.map(\.uuidString).joined(separator: ",")))"),
                URLQueryItem(name: "license_status", value: "in.(confirmed_free,confirmed_licensed)"),
                URLQueryItem(name: "order", value: "sort_order.asc")
            ])
            imageRows.append(contentsOf: rows ?? [])
        }
        let imageByID = Dictionary(grouping: imageRows, by: { $0.string("origin_id") ?? "" })
            .compactMapValues { candidates -> URL? in
                guard let image = candidates.first else { return nil }
                if let path = image.string("storage_path") {
                    return client.publicStorageURL(bucket: "ingested-images", path: path)
                }
                return image.string("source_url").flatMap(URL.init(string:))
            }
        return items.map { item in
            let coverURL = imageByID[item.id]
            let resolvedImageURL = galleryFirst ? (coverURL ?? item.imageURL) : (item.imageURL ?? coverURL)
            return DirectoryItem(
                id: item.id,
                kind: item.kind,
                slug: item.slug,
                title: item.title,
                subtitle: item.subtitle,
                imageURL: resolvedImageURL,
                // avatarCrop gehört zu photo_url — sobald ein Galerie-
                // Titelbild dessen Stelle einnimmt (galleryFirst mit
                // coverURL != nil), passt ein zuvor für photo_url gesetzter
                // Crop nicht mehr zum neuen Bild.
                avatarCrop: (galleryFirst && coverURL != nil) ? nil : item.avatarCrop
            )
        }
    }

    func detail(kind: EntityKind, identifier: String) async throws -> EntityDetail? {
        let specification = directorySpecification(for: kind)
        let idColumn = kind == .work || UUID(uuidString: identifier) != nil ? "id" : "slug"
        // member_of/parent: Nutzeranfrage, die Zugehörigkeit zu einem
        // übergeordneten Ensemble sichtbar zu machen (z.B. "Solist des
        // Tölzer Knabenchors" gehört zum Ensemble "Tölzer Knabenchor").
        // fields (der rohe JSONObject) landet direkt in EntityDetail, kein
        // Modell-Update nötig — siehe EntityDetailView.header.
        // ensembles.parent_ensemble_id ist ein Self-Join (Ensemble->Ensemble)
        // — PostgREST kann bei Self-Joins "gehört zu" (Vorwärts, ein Objekt)
        // nicht zuverlässig von "hat als Unter-Ensemble" (Rückwärts, mehrere)
        // unterscheiden und liefert über das Embedding immer die Rückwärts-
        // Richtung. Deshalb hier NUR die scalar-ID selektieren und weiter
        // unten manuell auflösen. person.member_of_ensemble_id betrifft
        // dagegen zwei VERSCHIEDENE Tabellen (persons/ensembles) und bleibt
        // ein normales, unproblematisches Embedding.
        let detailSelection: String
        switch kind {
        case .work: detailSelection = "*,composer:persons(id,slug,full_name)"
        case .person: detailSelection = "*,member_of:ensembles!member_of_ensemble_id(id,slug,name)"
        case .ensemble: detailSelection = "*"
        case .venue: detailSelection = "*"
        }
        let rows: [JSONObject] = try await client.get(
            table: specification.table,
            queryItems: [
                URLQueryItem(name: "select", value: detailSelection),
                URLQueryItem(name: idColumn, value: "eq.\(identifier)"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )
        guard var row = rows.first else { return nil }
        guard let entityID = row.string("id") else { return nil }

        if kind == .ensemble, let parentID = row.string("parent_ensemble_id") {
            let parentRows: [JSONObject] = (try? await client.get(
                table: "ensembles",
                queryItems: [
                    URLQueryItem(name: "select", value: "id,slug,name"),
                    URLQueryItem(name: "id", value: "eq.\(parentID)"),
                    URLQueryItem(name: "limit", value: "1")
                ]
            )) ?? []
            if let parent = parentRows.first {
                row["parent"] = .object(parent)
            }
        }
        if kind == .ensemble {
            let children: [JSONObject] = (try? await client.get(
                table: "ensembles",
                queryItems: [
                    URLQueryItem(name: "select", value: "id,slug,name,family_role"),
                    URLQueryItem(name: "parent_ensemble_id", value: "eq.\(entityID)"),
                    URLQueryItem(name: "is_resolution_placeholder", value: "eq.false"),
                    URLQueryItem(name: "order", value: "name.asc")
                ]
            )) ?? []
            row["children"] = .array(children.map(JSONValue.object))
        }

        async let galleryResult = optionalGallery(kind: kind, entityID: entityID)
        async let eventResult = optionalLinkedEvents(kind: kind, entityID: entityID)
        async let similarResult = optionalSimilarItems(kind: kind, row: row, entityID: entityID)
        async let latLngResult = optionalVenueLatLng(kind: kind, entityID: entityID)

        let latLng = await latLngResult
        return EntityDetail(
            id: entityID,
            kind: kind,
            slug: row.string("slug"),
            title: title(from: row, kind: kind),
            subtitle: subtitle(from: row, kind: kind),
            primaryImageURL: imageURL(from: row),
            fields: row,
            gallery: await galleryResult,
            events: await eventResult,
            similar: await similarResult,
            venueLatitude: latLng?.0,
            venueLongitude: latLng?.1
        )
    }

    private func optionalVenueLatLng(kind: EntityKind, entityID: String) async -> (Double, Double)? {
        guard kind == .venue else { return nil }
        struct LatLngRow: Decodable { let lat: Double?; let lng: Double? }
        let rows: [LatLngRow]? = try? await client.rpc("venue_with_latlng", parameters: ["p_id": .string(entityID)])
        guard let row = rows?.first, let lat = row.lat, let lng = row.lng else { return nil }
        return (lat, lng)
    }

    private func optionalGallery(kind: EntityKind, entityID: String) async -> [GalleryImage] {
        (try? await gallery(kind: kind, entityID: entityID)) ?? []
    }

    private func optionalLinkedEvents(kind: EntityKind, entityID: String) async -> [LinkedEvent] {
        (try? await linkedEvents(kind: kind, entityID: entityID)) ?? []
    }

    private func optionalSimilarItems(kind: EntityKind, row: JSONObject, entityID: String) async -> [DirectoryItem] {
        (try? await similarItems(kind: kind, row: row, entityID: entityID)) ?? []
    }

    func collections() async throws -> [EditorialCollection] {
        let rows: [JSONObject] = try await client.get(
            table: "editorial_collections",
            queryItems: [
                URLQueryItem(
                    name: "select",
                    value: "id,slug,title,subtitle,description_de,cover_image_url"
                ),
                URLQueryItem(name: "is_published", value: "eq.true"),
                URLQueryItem(name: "order", value: "sort_order.asc")
            ]
        )
        return rows.compactMap { collection(from: $0, events: []) }
    }

    func collection(slug: String) async throws -> EditorialCollection? {
        let rows: [JSONObject] = try await client.get(
            table: "editorial_collections",
            queryItems: [
                URLQueryItem(
                    name: "select",
                    value: "id,slug,title,subtitle,description_de,cover_image_url"
                ),
                URLQueryItem(name: "slug", value: "eq.\(slug)"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )
        guard let row = rows.first, let collectionID = row.string("id") else {
            return nil
        }

        let links: [JSONObject] = try await client.get(
            table: "editorial_collection_events",
            queryItems: [
                URLQueryItem(name: "select", value: "position,events(id,slug,title,subtitle,start_datetime,image_urls,status,venues(id,name))"),
                URLQueryItem(name: "collection_id", value: "eq.\(collectionID)"),
                URLQueryItem(name: "order", value: "position.asc")
            ]
        )
        let events = links.compactMap { link -> ConcertEvent? in
            guard let event = link.object("events") else { return nil }
            return ConcertEvent(json: event)
        }
        return collection(from: row, events: events)
    }

    func search(query: String, limit: Int = 20) async throws -> [SearchHit] {
        let rows: [JSONObject] = try await client.rpc(
            "search_all",
            parameters: [
                "q": .string(query),
                "result_limit": .number(Double(limit))
            ]
        )
        let ensembleIDs = rows.filter { $0.string("result_type") == EntityKind.ensemble.rawValue }
            .compactMap { $0.string("id") }
        var visibleEnsembleIDs = Set(ensembleIDs)
        if !ensembleIDs.isEmpty {
            let visible: [JSONObject] = (try? await client.get(
                table: "ensembles",
                queryItems: [
                    URLQueryItem(name: "select", value: "id"),
                    URLQueryItem(name: "id", value: "in.(\(ensembleIDs.joined(separator: ",")))"),
                    URLQueryItem(name: "is_resolution_placeholder", value: "eq.false")
                ]
            )) ?? []
            visibleEnsembleIDs = Set(visible.compactMap { $0.string("id") })
        }
        return rows.compactMap { row in
            guard let id = row.string("id"), let title = row.string("title") else {
                return nil
            }
            if row.string("result_type") == EntityKind.ensemble.rawValue,
               !visibleEnsembleIDs.contains(id) {
                return nil
            }
            return SearchHit(
                id: id,
                kind: row.string("result_type").flatMap(EntityKind.init(rawValue:)),
                slug: row.string("slug"),
                title: title,
                subtitle: row.string("subtitle")
            )
        }
    }

    func venueLocations() async throws -> [VenueLocation] {
        let rows: [JSONObject] = try await client.rpc("venues_with_latlng")
        return rows.compactMap { row in
            guard
                let id = row.string("id").flatMap(UUID.init(uuidString:)),
                let name = row.string("name"),
                let latitude = row.number("lat"),
                let longitude = row.number("lng")
            else { return nil }
            return VenueLocation(
                id: id,
                name: name,
                slug: row.string("slug"),
                city: row.string("address_city"),
                upcomingEventCount: row.integer("upcoming_event_count") ?? 0,
                latitude: latitude,
                longitude: longitude
            )
        }
    }

    func venueEvents(venueID: UUID, limit: Int = 5) async throws -> [ConcertEvent] {
        let rows: [JSONObject] = try await client.get(table: "events", queryItems: [
            URLQueryItem(name: "select", value: "id,slug,title,subtitle,start_datetime,image_urls,status,venues(id,name,photo_url)"),
            URLQueryItem(name: "venue_id", value: "eq.\(venueID.uuidString)"),
            URLQueryItem(name: "status", value: "neq.draft"),
            URLQueryItem(name: "start_datetime", value: "gte.\(ISO8601DateFormatter().string(from: .now))"),
            URLQueryItem(name: "order", value: "start_datetime.asc"),
            URLQueryItem(name: "limit", value: String(limit))
        ])
        return rows.compactMap(ConcertEvent.init(json:))
    }

    private func gallery(kind: EntityKind, entityID: String) async throws -> [GalleryImage] {
        let rows: [JSONObject] = try await client.get(
            table: "images",
            queryItems: [
                URLQueryItem(name: "select", value: "id,storage_path,source_url,alt_text,photographer,license_name"),
                URLQueryItem(name: "origin_type", value: "eq.\(kind.rawValue)"),
                URLQueryItem(name: "origin_id", value: "eq.\(entityID)"),
                URLQueryItem(name: "license_status", value: "in.(confirmed_free,confirmed_licensed)"),
                URLQueryItem(name: "order", value: "sort_order.asc")
            ]
        )
        return rows.compactMap { row in
            guard let id = row.string("id") else { return nil }
            let url: URL?
            if let path = row.string("storage_path") { url = client.publicStorageURL(bucket: "ingested-images", path: path) }
            else { url = row.string("source_url").flatMap(URL.init(string:)) }
            guard let url else { return nil }
            return GalleryImage(
                id: id,
                url: url,
                altText: row.string("alt_text"),
                photographer: row.string("photographer"),
                license: row.string("license_name")
            )
        }
    }

    private func linkedEvents(kind: EntityKind, entityID: String) async throws -> [LinkedEvent] {
        let table: String
        let filter: String
        switch kind {
        case .person:
            table = "event_participants"
            filter = "person_id"
        case .ensemble:
            table = "event_participants"
            filter = "ensemble_id"
        case .work:
            table = "event_works"
            filter = "work_id"
        case .venue:
            let rows: [JSONObject] = try await client.get(
                table: "events",
                queryItems: [
                    URLQueryItem(name: "select", value: "id,slug,title,start_datetime,image_urls,venues(id,name,photo_url)"),
                    URLQueryItem(name: "venue_id", value: "eq.\(entityID)"),
                    URLQueryItem(name: "status", value: "neq.draft"),
                    URLQueryItem(name: "order", value: "start_datetime.asc")
                ]
            )
            return rows.compactMap { linkedEvent(from: $0, role: nil) }
        }

        let selection = kind == .work
            ? "position,events(id,slug,title,start_datetime,image_urls,venues(id,name,photo_url))"
            : "role,role_label,events(id,slug,title,start_datetime,image_urls,venues(id,name,photo_url))"
        let queryItems: (String) -> [URLQueryItem] = { selectedColumns in [
                URLQueryItem(name: "select", value: selectedColumns),
                URLQueryItem(name: filter, value: "eq.\(entityID)")
            ]
        }
        let rows: [JSONObject]
        do {
            rows = try await client.get(table: table, queryItems: queryItems(selection))
        } catch where kind != .work {
            rows = try await client.get(
                table: table,
                queryItems: queryItems(selection.replacingOccurrences(of: "role,role_label", with: "role"))
            )
        }
        return rows.compactMap { row in
            guard let event = row.object("events") else { return nil }
            return linkedEvent(
                from: event,
                role: row.string("role_label") ?? row.string("role").map(personRoleLabel)
            )
        }
    }

    private func similarItems(
        kind: EntityKind,
        row: JSONObject,
        entityID: String
    ) async throws -> [DirectoryItem] {
        guard kind == .person || kind == .ensemble else { return [] }
        let specification = directorySpecification(for: kind)
        let rows: [JSONObject] = try await client.get(
            table: specification.table,
            queryItems: [
                URLQueryItem(name: "select", value: specification.select),
                URLQueryItem(name: "id", value: "neq.\(entityID)"),
                URLQueryItem(name: "limit", value: "8")
            ]
        )
        return rows.compactMap { directoryItem(from: $0, kind: kind) }
    }

    private func directorySpecification(for kind: EntityKind) -> (table: String, select: String, order: String) {
        switch kind {
        case .person: ("persons", "id,slug,full_name,roles,instrument,photo_url,avatar_crop_x,avatar_crop_y,avatar_crop_width,avatar_crop_height", "full_name")
        case .ensemble: ("ensembles", "id,slug,name,photo_url,avatar_crop_x,avatar_crop_y,avatar_crop_width,avatar_crop_height", "name")
        case .venue: ("venues", "id,slug,name,address_city,photo_url", "name")
        case .work: (
            "works",
            "id,title,catalog_number,genre,key_signature,duration_minutes,composition_year,instrumentation,composer:persons(id,slug,full_name,photo_url,avatar_crop_x,avatar_crop_y,avatar_crop_width,avatar_crop_height)",
            "title"
        )
        }
    }

    private func directoryItem(from row: JSONObject, kind: EntityKind) -> DirectoryItem? {
        guard let id = row.string("id") else { return nil }
        return DirectoryItem(
            id: id,
            kind: kind,
            slug: row.string("slug"),
            title: title(from: row, kind: kind),
            subtitle: subtitle(from: row, kind: kind),
            imageURL: imageURL(from: row),
            avatarCrop: avatarCrop(from: row),
            composer: kind == .work ? composerRef(from: row) : nil
        )
    }

    private func composerRef(from row: JSONObject) -> DirectoryItem.ComposerRef? {
        guard let composer = row.object("composer"), let id = composer.string("id"), let name = composer.string("full_name") else { return nil }
        return DirectoryItem.ComposerRef(
            id: id,
            slug: composer.string("slug"),
            name: name,
            imageURL: composer.string("photo_url").flatMap(URL.init(string:)),
            avatarCrop: avatarCrop(from: composer)
        )
    }

    /// Runder Avatar-Fokuspunkt aus avatar_crop_x/y/width/height (siehe
    /// DirectoryItem.avatarCrop) — nur bei person/ensemble in der Select-
    /// Spalte enthalten, bei anderen kinds liefert row.number(...) einfach
    /// nil.
    private func avatarCrop(from row: JSONObject) -> CropRect? {
        guard
            let x = row.number("avatar_crop_x"),
            let y = row.number("avatar_crop_y"),
            let width = row.number("avatar_crop_width"),
            let height = row.number("avatar_crop_height")
        else { return nil }
        return CropRect(x: x, y: y, width: width, height: height)
    }

    private func title(from row: JSONObject, kind: EntityKind) -> String {
        if kind == .person { return row.string("full_name") ?? "Unbekannte Person" }
        let value = row.string("name") ?? row.string("title") ?? "Ohne Titel"
        return kind == .work ? value.cleanedWorkTitle : value
    }

    private func subtitle(from row: JSONObject, kind: EntityKind) -> String? {
        switch kind {
        case .person:
            return [
                row.strings("roles").map(personRoleLabel).joined(separator: ", "),
                row.string("instrument"),
            ]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case .ensemble: return nil
        case .venue: return row.string("address_city")
        case .work:
            return [
                row.object("composer")?.string("full_name"),
                row.string("catalog_number"),
                row.string("key_signature"),
                row.integer("composition_year").map(String.init),
                row.integer("duration_minutes").map { "\($0) Min." }
            ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    private func imageURL(from row: JSONObject) -> URL? {
        [row.string("photo_url"), row.string("image_url")]
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .first
    }

    private func linkedEvent(from row: JSONObject, role: String?) -> LinkedEvent? {
        guard
            let id = row.string("id"),
            let slug = row.string("slug"),
            let title = row.string("title")
        else { return nil }
        return LinkedEvent(
            id: id,
            slug: slug,
            title: title,
            startDate: row.string("start_datetime").flatMap(FlexibleDateParser.date(from:)),
            venueName: row.object("venues")?.string("name"),
            role: role,
            imageURLs: row.strings("image_urls"),
            venueID: row.object("venues")?.string("id").flatMap(UUID.init(uuidString:)),
            venuePhotoURL: row.object("venues")?.string("photo_url")
        )
    }

    private func collection(from row: JSONObject, events: [ConcertEvent]) -> EditorialCollection? {
        guard
            let id = row.string("id"),
            let slug = row.string("slug"),
            let title = row.string("title")
        else { return nil }
        return EditorialCollection(
            id: id,
            slug: slug,
            title: title,
            subtitle: row.string("subtitle"),
            description: row.string("description_de"),
            coverImageURL: row.string("cover_image_url").flatMap(URL.init(string:)),
            events: events
        )
    }
}

struct PreviewContentRepository: ContentRepository {
    func directory(kind: EntityKind) async throws -> [DirectoryItem] {
        SampleData.directory.filter { $0.kind == kind }
    }

    func detail(kind: EntityKind, identifier: String) async throws -> EntityDetail? {
        SampleData.entityDetails.first { $0.kind == kind && ($0.slug == identifier || $0.id == identifier) }
    }

    func collections() async throws -> [EditorialCollection] { SampleData.collections }
    func collection(slug: String) async throws -> EditorialCollection? { SampleData.collections.first { $0.slug == slug } }
    func search(query: String, limit: Int) async throws -> [SearchHit] {
        SampleData.directory.filter { $0.title.localizedStandardContains(query) }.prefix(limit).map {
            SearchHit(id: $0.id, kind: $0.kind, slug: $0.slug, title: $0.title, subtitle: $0.subtitle)
        }
    }
    func venueLocations() async throws -> [VenueLocation] { SampleData.venues }
    func venueEvents(venueID: UUID, limit: Int) async throws -> [ConcertEvent] {
        Array(SampleData.events.filter { $0.venues?.id == venueID }.prefix(limit))
    }
}
