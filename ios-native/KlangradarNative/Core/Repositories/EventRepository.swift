import Foundation

struct InspirationCategory: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let slug: String
    let title: String
    let symbol: String?
    let colorKey: String
    enum CodingKeys: String, CodingKey { case id, slug, title = "inspiration_title", symbol = "icon_name", colorKey = "color_key" }
}

extension InspirationCategory {
    /// Bleibt sichtbar, wenn die dynamische Attribut-Tabelle vorübergehend
    /// nicht erreichbar oder noch nicht migriert ist. Sobald der Server
    /// Kategorien liefert, werden diese Werte vollständig ersetzt.
    static let fallback: [InspirationCategory] = [
        item(1, "oper", "Oper & Musiktheater", "theatermasks.fill", "purple"),
        item(2, "kostenlos", "Freier Eintritt", "ticket.fill", "teal"),
        item(3, "kammermusik", "Kammermusik entdecken", "music.quarternote.3", "indigo"),
        item(4, "symphonik", "Große Symphonik", "music.note.house.fill", "blue"),
        item(5, "vokal", "Chor & Vokalmusik", "person.3.fill", "pink"),
        item(6, "neue_musik", "Neue Musik", "waveform", "orange"),
        item(7, "orgel", "Orgel entdecken", "pianokeys", "teal"),
        item(8, "lied", "Lied & Gesang", "music.mic", "purple"),
        item(9, "klavier", "Klavier Highlights", "pianokeys.inverse", "blue"),
        item(10, "streicher", "Violine & Streicher", "music.note", "pink"),
        item(11, "alte_musik", "Alte Musik", "scroll.fill", "orange"),
        item(12, "ballett_tanz", "Ballett & Tanz", "figure.dance", "purple"),
        item(13, "festival", "Festivals & Reihen", "sparkles", "indigo"),
        item(14, "familie", "Familienkonzerte", "figure.2.and.child.holdinghands", "teal"),
        item(15, "barock", "Barocke Klangwelten", "music.note", "orange"),
        item(16, "romantik", "Romantik pur", "heart.fill", "pink"),
        item(17, "solo", "Solo-Abende", "person.fill", "blue"),
        item(18, "open_air", "Open Air Konzerte", "sun.max.fill", "teal"),
        item(19, "matinee", "Matineen am Sonntag", "cup.and.saucer.fill", "orange"),
        item(20, "musik_20_jh", "Musik des 20. Jahrhunderts", "waveform", "indigo"),
        item(21, "geistlich", "Geistliche Musik", "building.columns.fill", "purple"),
        item(22, "blechblaeser", "Blechbläser & Brass", "music.note", "orange"),
        item(23, "schlagwerk", "Schlagwerk & Rhythmus", "circle.grid.cross.fill", "pink"),
        item(24, "zupfinstrumente", "Gitarre & Zupfinstrumente", "music.note", "teal"),
        item(25, "jazz", "Jazz trifft Klassik", "music.mic", "blue"),
        item(26, "dirigieren", "Dirigent:innen im Fokus", "figure.wave", "indigo"),
        item(27, "komponistin", "Komponistinnen entdecken", "person.fill", "purple"),
        item(28, "premiere", "Uraufführungen & Premieren", "star.fill", "pink")
    ]

    private static func item(_ number: Int, _ slug: String, _ title: String, _ symbol: String, _ color: String) -> InspirationCategory {
        InspirationCategory(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!,
            slug: slug,
            title: title,
            symbol: symbol,
            colorKey: color
        )
    }
}

protocol EventRepository: Sendable {
    func upcomingEvents(limit: Int, regionID: UUID?) async throws -> [ConcertEvent]
    func allUpcomingEvents(regionID: UUID?) async throws -> [ConcertEvent]
    func enrichingImages(in events: [ConcertEvent]) async throws -> [ConcertEvent]
    func eventDetail(slug: String) async throws -> JSONObject?
    /// Für antippbare Genre-Chips (siehe GenreFilterRouter) — kommende
    /// Veranstaltungen, die dieses Genre über event_genres verlinkt haben.
    func events(genreID: UUID, limit: Int) async throws -> [ConcertEvent]
    func inspirationEvents(attributeSlug: String, limit: Int) async throws -> [ConcertEvent]
    func inspirationCategories() async throws -> [InspirationCategory]
}

extension EventRepository {
    func upcomingEvents(limit: Int) async throws -> [ConcertEvent] {
        try await upcomingEvents(limit: limit, regionID: nil)
    }

    func allUpcomingEvents() async throws -> [ConcertEvent] {
        try await allUpcomingEvents(regionID: nil)
    }
}

struct LiveEventRepository: EventRepository {
    let client: SupabaseRESTClient

    func upcomingEvents(limit: Int = 40, regionID: UUID? = nil) async throws -> [ConcertEvent] {
        try await fetchEvents(limit: limit, offset: 0, regionID: regionID)
    }

    func allUpcomingEvents(regionID: UUID? = nil) async throws -> [ConcertEvent] {
        var result: [ConcertEvent] = []
        let pageSize = 500
        while true {
            let page = try await fetchEvents(limit: pageSize, offset: result.count, regionID: regionID)
            result.append(contentsOf: page)
            if page.count < pageSize { return result }
        }
    }

    /// `regionID` filtert per PostgREST-Embed-Filter auf `venues.city_id` --
    /// dafür muss der Embed als `venues!inner(...)` erfolgen (siehe
    /// app/lib/core/regions/calendar_providers.dart), sonst wird die
    /// eingebettete Tabelle nur mitgeliefert statt gefiltert.
    private func fetchEvents(limit: Int, offset: Int, regionID: UUID? = nil) async throws -> [ConcertEvent] {
        let venuesEmbed = regionID == nil ? "venues(id,name,photo_url)" : "venues!inner(id,name,photo_url)"
        var queryItems = [
            URLQueryItem(
                name: "select",
                value: "id,slug,title,subtitle,start_datetime,venue_detail,image_urls,updated_at,status,category,is_free,\(venuesEmbed),event_genres(genres(id,slug,label_de)),event_participants(persons(id,full_name,photo_url),ensembles(id,name,photo_url))"
            ),
            URLQueryItem(name: "status", value: "eq.scheduled"),
            URLQueryItem(
                name: "start_datetime",
                value: "gte.\(ISO8601DateFormatter().string(from: .now))"
            ),
            URLQueryItem(name: "order", value: "start_datetime.asc"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        if let regionID {
            queryItems.append(URLQueryItem(name: "venues.city_id", value: "eq.\(regionID.uuidString)"))
        }
        return try await client.get(table: "events", queryItems: queryItems)
    }

    func enrichingImages(in events: [ConcertEvent]) async throws -> [ConcertEvent] {
        let ids = Set(events.flatMap { event in
            [event.id, event.venues?.id].compactMap { $0 }
                + (event.eventParticipants ?? []).flatMap { [$0.persons?.id, $0.ensembles?.id].compactMap { $0 } }
        })
        guard !ids.isEmpty else { return events }
        var rows: [JSONObject] = []
        var currentEventRows: [JSONObject] = []
        let allIDs = Array(ids)
        for start in stride(from: 0, to: allIDs.count, by: 75) {
            let chunk = allIDs[start..<min(start + 75, allIDs.count)]
            let page: [JSONObject] = try await client.get(table: "images", queryItems: [
                URLQueryItem(name: "select", value: "origin_id,storage_path,source_url,sort_order,updated_at"),
                URLQueryItem(name: "origin_id", value: "in.(\(chunk.map(\.uuidString).joined(separator: ",")))"),
                URLQueryItem(name: "license_status", value: "in.(confirmed_free,confirmed_licensed)"),
                URLQueryItem(name: "quality_status", value: "eq.valid"),
                URLQueryItem(name: "order", value: "sort_order.asc")
            ])
            rows.append(contentsOf: page)
        }
        let eventIDs = events.map(\.id)
        for start in stride(from: 0, to: eventIDs.count, by: 75) {
            let chunk = eventIDs[start..<min(start + 75, eventIDs.count)]
            let page: [JSONObject] = try await client.get(table: "events", queryItems: [
                URLQueryItem(name: "select", value: "id,image_urls,updated_at"),
                URLQueryItem(name: "id", value: "in.(\(chunk.map(\.uuidString).joined(separator: ",")))")
            ])
            currentEventRows.append(contentsOf: page)
        }
        let currentByID = Dictionary(uniqueKeysWithValues: currentEventRows.compactMap { row -> (String, JSONObject)? in
            guard let id = row.string("id") else { return nil }
            return (id.lowercased(), row)
        })
        let galleryURLs = Dictionary(grouping: rows, by: { $0.string("origin_id") ?? "" }).mapValues { values in
            values.compactMap { row -> String? in
                let raw: String?
                if let path = row.string("storage_path") { raw = client.publicStorageURL(bucket: "ingested-images", path: path).absoluteString }
                else { raw = row.string("source_url") }
                guard let raw, var components = URLComponents(string: raw) else { return raw }
                if let version = row.string("updated_at") {
                    var items = components.queryItems ?? []
                    items.removeAll { $0.name == "kr_v" }
                    items.append(URLQueryItem(name: "kr_v", value: version))
                    components.queryItems = items
                }
                return components.url?.absoluteString ?? raw
            }
        }
        return events.map { event in
            let candidateIDs = [event.venues?.id].compactMap { $0 } + (event.eventParticipants ?? []).flatMap { [$0.persons?.id, $0.ensembles?.id].compactMap { $0 } }
            // PostgREST liefert origin_id klein geschrieben, UUID.uuidString liefert
            // GROSSBUCHSTABEN — ohne .lowercased() traf dieser Dictionary-Lookup nie,
            // eigene Event-/Venue-/Mitwirkenden-Galeriebilder (inkl. Event-Gruppen-
            // Bild) wurden dadurch still ignoriert und auf das Mitwirkenden-eigene
            // photo_url zurückgefallen (Nutzerfeedback: falsches Bild angezeigt).
            let fallback = candidateIDs.flatMap { galleryURLs[$0.uuidString.lowercased()] ?? [] }
            let current = currentByID[event.id.uuidString.lowercased()]
            return ConcertEvent(
                id: event.id,
                slug: event.slug,
                title: event.title,
                subtitle: event.subtitle,
                startDatetime: event.startDatetime,
                imageUrls: current?.strings("image_urls") ?? event.imageUrls,
                status: event.status,
                venues: event.venues,
                eventParticipants: event.eventParticipants,
                fallbackImageUrls: fallback,
                // Ein leeres Array ist hier absichtlich ein aktueller Zustand:
                // Ein zuvor vorhandenes, inzwischen gelöschtes Galeriebild
                // darf nicht aus dem alten Feedobjekt weiterleben.
                ownGalleryImageUrls: galleryURLs[event.id.uuidString.lowercased()] ?? [],
                category: event.category,
                genreIDs: event.genreIDs,
                genreLabels: event.genreLabels,
                isFree: event.isFree,
                venueDetail: event.venueDetail,
                updatedAt: current?.string("updated_at") ?? event.updatedAt
            )
        }
    }

    func events(genreID: UUID, limit: Int = 60) async throws -> [ConcertEvent] {
        try await client.get(
            table: "events",
            queryItems: [
                URLQueryItem(
                    name: "select",
                    value: "id,slug,title,subtitle,start_datetime,image_urls,updated_at,status,category,is_free,venues(id,name,photo_url),event_genres!inner(genre_id,genres(id,slug,label_de)),event_participants(persons(id,full_name,photo_url),ensembles(id,name,photo_url))"
                ),
                URLQueryItem(name: "status", value: "eq.scheduled"),
                // Filtert direkt auf der Spalte der eingebetteten Zwischentabelle
                // event_genres (genre_id) statt auf einer weiteren Verschachtelungs-
                // ebene (event_genres.genres.id) — einfacher und robuster gegenüber
                // PostgREST-Versionsunterschieden bei doppelt verschachtelten Filtern.
                URLQueryItem(name: "event_genres.genre_id", value: "eq.\(genreID.uuidString)"),
                URLQueryItem(
                    name: "start_datetime",
                    value: "gte.\(ISO8601DateFormatter().string(from: .now))"
                ),
                URLQueryItem(name: "order", value: "start_datetime.asc"),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        )
    }

    func inspirationEvents(attributeSlug: String, limit: Int = 60) async throws -> [ConcertEvent] {
        try await client.rpc("inspiration_events", parameters: [
            "p_attribute_slug": .string(attributeSlug),
            "p_result_limit": .number(Double(limit))
        ])
    }

    func inspirationCategories() async throws -> [InspirationCategory] {
        try await client.get(table: "attributes", queryItems: [
            URLQueryItem(name: "select", value: "id,slug,inspiration_title,icon_name,color_key"),
            URLQueryItem(name: "inspiration_enabled", value: "eq.true"),
            URLQueryItem(name: "order", value: "sort_order.asc")
        ])
    }

    func eventDetail(slug: String) async throws -> JSONObject? {
        let baseDetail: JSONObject?
        do {
            let rows: [JSONObject] = try await client.get(
                table: "events",
                queryItems: detailQuery(slug: slug, selection: Self.detailSelection)
            )
            baseDetail = rows.first
        } catch {
            do {
                // Keep program and participants available while the role_label
                // migration is still being rolled out to a backend.
                let rows: [JSONObject] = try await client.get(
                    table: "events",
                    queryItems: detailQuery(slug: slug, selection: Self.legacyDetailSelection)
                )
                baseDetail = rows.first
            } catch {
                // A schema extension must never leave the detail screen spinning.
                // Fall back to the stable core fields if one optional relation is unavailable.
                let rows: [JSONObject] = try await client.get(
                    table: "events",
                    queryItems: detailQuery(slug: slug, selection: Self.coreDetailSelection)
                )
                baseDetail = rows.first
            }
        }
        guard let baseDetail else { return nil }
        return await enrichingRelatedContent(baseDetail)
    }

    private func detailQuery(slug: String, selection: String) -> [URLQueryItem] {
        [
            URLQueryItem(name: "select", value: selection),
            URLQueryItem(name: "slug", value: "eq.\(slug)"),
            URLQueryItem(name: "status", value: "neq.draft"),
            URLQueryItem(name: "limit", value: "1")
        ]
    }

    private func enrichingRelatedContent(_ detail: JSONObject) async -> JSONObject {
        var enriched = detail
        let eventID = detail.string("id") ?? ""
        let programID = detail.string("program_id")
        let venueID = detail.object("venues")?.string("id")
        let venueCity = detail.object("venues")?.string("address_city")
        let genreID = detail.objects("event_genres").first?.object("genres")?.string("id")

        async let otherDates = optionalOtherDates(programID: programID, excluding: eventID)
        async let similarEvents = optionalSimilarEvents(
            eventID: eventID,
            genreID: genreID,
            venueID: venueID,
            city: venueCity
        )
        async let groupContent = optionalGroupContent(programID: programID, excluding: eventID)

        enriched["_other_dates"] = .array(await otherDates.map { .object($0) })
        enriched["_similar_events"] = .array(await similarEvents.map { .object($0) })

        if let sibling = await groupContent {
            if enriched.objects("event_works").isEmpty, !sibling.objects("event_works").isEmpty {
                enriched["event_works"] = sibling["event_works"]
            }
            if enriched.objects("event_participants").count < sibling.objects("event_participants").count {
                enriched["event_participants"] = sibling["event_participants"]
            }
            if enriched.string("program_notes_de") == nil, let notes = sibling["program_notes_de"] {
                enriched["program_notes_de"] = notes
            }
            if enriched.string("program_extraction_status") == nil,
               let status = sibling["program_extraction_status"] {
                enriched["program_extraction_status"] = status
            }
        }
        return await enrichingEntityImages(await enrichingParentEnsembles(enriched))
    }

    /// ensembles.parent_ensemble_id ist ein Self-Join (Ensemble->Ensemble) —
    /// PostgREST liefert dafür über Embedding zuverlässig nur die Rückwärts-
    /// Richtung ("hat als Unter-Ensemble" statt "gehört zu"), siehe Kommentar
    /// bei detailSelection. Deshalb wird hier für alle Mitwirkenden-Ensembles
    /// mit gesetzter parent_ensemble_id die übergeordnete Ensemble-Kurzform
    /// (slug, name) manuell nachgeladen und als "parent" angehängt.
    private func enrichingParentEnsembles(_ detail: JSONObject) async -> JSONObject {
        let ensembles = detail.objects("event_participants").compactMap { $0.object("ensembles") }
        let parentIDs = Set(ensembles.compactMap { $0.string("parent_ensemble_id") })
        guard !parentIDs.isEmpty else { return detail }

        let parentRows: [JSONObject] = (try? await client.get(table: "ensembles", queryItems: [
            URLQueryItem(name: "select", value: "id,slug,name"),
            URLQueryItem(name: "id", value: "in.(\(parentIDs.joined(separator: ",")))")
        ])) ?? []
        guard !parentRows.isEmpty else { return detail }
        let parentByID = Dictionary(uniqueKeysWithValues: parentRows.compactMap { row -> (String, JSONObject)? in
            guard let id = row.string("id") else { return nil }
            return (id, row)
        })

        var enriched = detail
        let participants = detail.objects("event_participants").map { original -> JSONObject in
            var row = original
            if var ensemble = row.object("ensembles"),
               let parentID = ensemble.string("parent_ensemble_id"),
               let parent = parentByID[parentID] {
                ensemble["parent"] = .object(parent)
                row["ensembles"] = .object(ensemble)
            }
            return row
        }
        enriched["event_participants"] = .array(participants.map(JSONValue.object))
        return enriched
    }

    private func enrichingEntityImages(_ detail: JSONObject) async -> JSONObject {
        let participantEntities = detail.objects("event_participants").flatMap { row in
            [row.object("persons"), row.object("ensembles")].compactMap { $0 }
        }
        let composers = detail.objects("event_works").compactMap {
            $0.object("works")?.object("composer")
        }
        let missingImageIDs = Set((participantEntities + composers).compactMap { entity -> UUID? in
            guard entity.string("photo_url") == nil else { return nil }
            return entity.string("id").flatMap(UUID.init(uuidString:))
        })
        guard !missingImageIDs.isEmpty else { return detail }

        let rows: [JSONObject]? = try? await client.get(table: "images", queryItems: [
            URLQueryItem(name: "select", value: "origin_id,storage_path,source_url,sort_order"),
            URLQueryItem(name: "origin_id", value: "in.(\(missingImageIDs.map(\.uuidString).joined(separator: ",")))"),
            URLQueryItem(name: "license_status", value: "in.(confirmed_free,confirmed_licensed)"),
            URLQueryItem(name: "order", value: "sort_order.asc")
        ])
        let imageByEntity = Dictionary(grouping: rows ?? [], by: { $0.string("origin_id") ?? "" })
            .compactMapValues { candidates -> String? in
                guard let image = candidates.first else { return nil }
                if let path = image.string("storage_path") {
                    return client.publicStorageURL(bucket: "ingested-images", path: path).absoluteString
                }
                return image.string("source_url")
            }
        guard !imageByEntity.isEmpty else { return detail }

        func withImage(_ entity: JSONObject?) -> JSONObject? {
            guard var entity else { return nil }
            if entity.string("photo_url") == nil,
               let id = entity.string("id"),
               let imageURL = imageByEntity[id] {
                entity["photo_url"] = .string(imageURL)
            }
            return entity
        }

        var enriched = detail
        let participants = detail.objects("event_participants").map { original -> JSONObject in
            var row = original
            if let person = withImage(row.object("persons")) { row["persons"] = .object(person) }
            if let ensemble = withImage(row.object("ensembles")) { row["ensembles"] = .object(ensemble) }
            return row
        }
        enriched["event_participants"] = .array(participants.map(JSONValue.object))

        let works = detail.objects("event_works").map { original -> JSONObject in
            var link = original
            guard var work = link.object("works") else { return link }
            if let composer = withImage(work.object("composer")) { work["composer"] = .object(composer) }
            link["works"] = .object(work)
            return link
        }
        enriched["event_works"] = .array(works.map(JSONValue.object))
        return enriched
    }

    private func optionalOtherDates(programID: String?, excluding eventID: String) async -> [JSONObject] {
        guard let programID else { return [] }
        let rows: [JSONObject]? = try? await client.get(table: "events", queryItems: [
            URLQueryItem(name: "select", value: "id,slug,title,subtitle,start_datetime,image_urls,status,venues(id,name,photo_url)"),
            URLQueryItem(name: "program_id", value: "eq.\(programID)"),
            URLQueryItem(name: "id", value: "neq.\(eventID)"),
            URLQueryItem(name: "status", value: "neq.draft"),
            URLQueryItem(name: "order", value: "start_datetime.asc")
        ])
        return rows ?? []
    }

    private func optionalSimilarEvents(eventID: String, genreID: String?, venueID: String?, city: String?) async -> [JSONObject] {
        guard !eventID.isEmpty, genreID != nil || venueID != nil,
              let city = city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty
        else { return [] }
        let rows: [JSONObject]? = try? await client.rpc("similar_events", parameters: [
            "p_event_id": .string(eventID),
            "p_genre_id": genreID.map(JSONValue.string) ?? .null,
            "p_venue_id": venueID.map(JSONValue.string) ?? .null,
            // Die RPC kennt die Stadt noch nicht. Mehr Kandidaten laden und
            // erst danach lokal auf die Stadt des Ausgangsevents begrenzen.
            "p_result_limit": .number(24)
        ])
        guard let rows, !rows.isEmpty else { return [] }

        let venueIDs = Set(rows.compactMap { $0.string("venue_id") })
        guard !venueIDs.isEmpty else { return [] }
        let venueRows: [JSONObject] = (try? await client.get(table: "venues", queryItems: [
            URLQueryItem(name: "select", value: "id,address_city"),
            URLQueryItem(name: "id", value: "in.(\(venueIDs.joined(separator: ",")))")
        ])) ?? []
        let normalizedCity = city.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let matchingVenueIDs = Set(venueRows.compactMap { venue -> String? in
            guard let candidateCity = venue.string("address_city")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current),
                  candidateCity == normalizedCity
            else { return nil }
            return venue.string("id")
        })
        return Array(rows.filter { row in
            row.string("venue_id").map(matchingVenueIDs.contains) == true
        }.prefix(6))
    }

    private func optionalGroupContent(programID: String?, excluding eventID: String) async -> JSONObject? {
        guard let programID else { return nil }
        let queryItems: (String) -> [URLQueryItem] = { selection in [
            URLQueryItem(name: "select", value: selection),
            URLQueryItem(name: "program_id", value: "eq.\(programID)"),
            URLQueryItem(name: "id", value: "neq.\(eventID)"),
            URLQueryItem(name: "status", value: "neq.draft")
        ] }
        let selection = "program_notes_de,program_extraction_status,event_works(position,after_intermission,works(id,title,catalog_number,key_signature,instrumentation,movements,composer:persons(id,slug,full_name,photo_url))),event_participants(role,role_label,persons(id,slug,full_name,photo_url,member_of:ensembles!member_of_ensemble_id(slug,name)),ensembles(id,slug,name,photo_url,parent_ensemble_id))"
        var rows: [JSONObject]? = try? await client.get(table: "events", queryItems: queryItems(selection))
        if rows == nil {
            rows = try? await client.get(table: "events", queryItems: queryItems(selection.replacingOccurrences(of: "role,role_label", with: "role")))
        }
        return rows?.max { lhs, rhs in
            lhs.objects("event_works").count + lhs.objects("event_participants").count
                < rhs.objects("event_works").count + rhs.objects("event_participants").count
        }
    }

    private static let coreDetailSelection = "id,slug,title,subtitle,category,description_de,program_notes_de,program_extraction_status,start_datetime,end_datetime,duration_minutes,has_intermission,venue_detail,ticket_url,price_min,price_max,price_currency,is_free,remaining_tickets_status,doors_info,age_restriction,discount_info,target_audience,performance_language,website_url,accessibility,status,image_urls,program_id,attribution_notice,attribution_license_url,last_verified_at,venues(id,slug,name,address_street,address_zip,address_city,photo_url,description_de)"

    // PostgREST lehnt echte Zeilenumbrüche innerhalb des select-Parameters ab
    // (PGRST100: "unexpected \"\n\""), sobald sie URL-kodiert übertragen werden —
    // ein reines Multiline-String-Literal ("""...""") schlug dadurch für JEDES
    // Event fehl (primär UND Legacy-Fallback), sodass die App still auf
    // coreDetailSelection zurückfiel, das event_works/event_participants gar
    // nicht erst enthält. Deshalb hier Zeilenumbrüche vor Verwendung entfernen,
    // statt den mehrzeiligen Aufbau (bessere Lesbarkeit im Quelltext) aufzugeben.
    private static let detailSelection = """
    id,slug,title,subtitle,category,description_de,program_notes_de,program_extraction_status,start_datetime,end_datetime,duration_minutes,has_intermission,
    ticket_url,price_min,price_max,price_currency,is_free,remaining_tickets_status,doors_info,
    age_restriction,discount_info,presale_fee_info,target_audience,performance_language,
    website_url,accessibility,status,image_urls,program_id,attribution_notice,
    attribution_license_url,last_verified_at,
    venues(id,slug,name,address_street,address_zip,address_city,photo_url,description_de),
    organizers(name),event_genres(genres(id,slug,label_de)),
    event_works(position,after_intermission,works(id,title,catalog_number,key_signature,instrumentation,movements,composer:persons(id,slug,full_name,photo_url))),
    event_participants(role,role_label,persons(id,slug,full_name,photo_url,member_of:ensembles!member_of_ensemble_id(slug,name)),ensembles(id,slug,name,photo_url,parent_ensemble_id))
    """
    .components(separatedBy: .newlines)
    .joined()

    private static let legacyDetailSelection = detailSelection.replacingOccurrences(
        of: "role,role_label",
        with: "role"
    )
}

struct PreviewEventRepository: EventRepository {
    func upcomingEvents(limit: Int = 40, regionID: UUID? = nil) async throws -> [ConcertEvent] {
        Array(SampleData.events.prefix(limit))
    }

    func allUpcomingEvents(regionID: UUID? = nil) async throws -> [ConcertEvent] { SampleData.events }

    func enrichingImages(in events: [ConcertEvent]) async throws -> [ConcertEvent] { events }

    func events(genreID: UUID, limit: Int = 60) async throws -> [ConcertEvent] {
        Array(SampleData.events.filter { $0.genreIDs.contains(genreID) }.prefix(limit))
    }

    func inspirationEvents(attributeSlug: String, limit: Int = 60) async throws -> [ConcertEvent] {
        Array(SampleData.events.prefix(limit))
    }
    func inspirationCategories() async throws -> [InspirationCategory] { [] }

    func eventDetail(slug: String) async throws -> JSONObject? {
        guard let event = SampleData.events.first(where: { $0.slug == slug }) else { return nil }
        return [
            "id": .string(event.id.uuidString), "slug": .string(event.slug),
            "title": .string(event.title), "subtitle": event.subtitle.map(JSONValue.string) ?? .null,
            "description_de": .string("Ein außergewöhnlicher Konzertabend mit einem sorgfältig zusammengestellten Programm."),
            "start_datetime": .string(event.startDatetime), "duration_minutes": .number(120),
            "has_intermission": .bool(true), "price_min": .number(18), "price_max": .number(62),
            "price_currency": .string("EUR"), "remaining_tickets_status": .string("available"),
            "venues": .object(["id": .string(event.venues?.id.uuidString ?? ""), "name": .string(event.venueName), "address_city": .string("München")]),
            "event_genres": .array([.object(["genres": .object(["label_de": .string("Klassik")])])]),
            "event_works": .array([.object(["position": .number(1), "works": .object(["title": .string("Symphonie fantastique"), "catalog_number": .string("op. 14"), "composer": .object(["full_name": .string("Hector Berlioz")])])])]),
            "event_participants": .array([.object(["role": .string("Orchester"), "ensembles": .object(["name": .string("Münchner Philharmoniker")])])]),
            "accessibility": .object(["wheelchair": .bool(true)])
        ]
    }
}
