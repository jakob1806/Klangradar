import Foundation

enum SampleData {
    static let events: [ConcertEvent] = [
        ConcertEvent(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!,
            slug: "symphonie-fantastique",
            title: "Symphonie fantastique",
            subtitle: "Münchner Philharmoniker",
            startDatetime: "2026-08-09T19:30:00+02:00",
            imageUrls: [
                "https://images.unsplash.com/photo-1465847899084-d164df4dedc6?auto=format&fit=crop&w=1600&q=85"
            ],
            status: "scheduled",
            venues: VenueSummary(
                id: UUID(uuidString: "B1000000-0000-0000-0000-000000000001")!,
                name: "Gasteig HP8"
            )
        ),
        ConcertEvent(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000002")!,
            slug: "klavierabend",
            title: "Klavierabend",
            subtitle: "Werke von Schubert und Ravel",
            startDatetime: "2026-08-10T20:00:00+02:00",
            imageUrls: [
                "https://images.unsplash.com/photo-1520523839897-bd0b52f945a0?auto=format&fit=crop&w=1200&q=85"
            ],
            status: "scheduled",
            venues: VenueSummary(
                id: UUID(uuidString: "B1000000-0000-0000-0000-000000000002")!,
                name: "Prinzregententheater"
            )
        ),
        ConcertEvent(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000003")!,
            slug: "mozart-matinee",
            title: "Mozart Matinee",
            subtitle: "Kammerorchester München",
            startDatetime: "2026-08-11T11:00:00+02:00",
            imageUrls: [
                "https://images.unsplash.com/photo-1509824227185-9c5a01ceba0d?auto=format&fit=crop&w=1200&q=85"
            ],
            status: "scheduled",
            venues: VenueSummary(
                id: UUID(uuidString: "B1000000-0000-0000-0000-000000000003")!,
                name: "Residenz München"
            )
        )
    ]

    static let venues: [VenueLocation] = [
        VenueLocation(
            id: UUID(uuidString: "B1000000-0000-0000-0000-000000000001")!,
            name: "Gasteig HP8",
            latitude: 48.1114,
            longitude: 11.5538
        ),
        VenueLocation(
            id: UUID(uuidString: "B1000000-0000-0000-0000-000000000002")!,
            name: "Prinzregententheater",
            latitude: 48.1396,
            longitude: 11.6053
        ),
        VenueLocation(
            id: UUID(uuidString: "B1000000-0000-0000-0000-000000000003")!,
            name: "Residenz München",
            latitude: 48.1413,
            longitude: 11.5784
        )
    ]

    static let directory: [DirectoryItem] = [
        DirectoryItem(
            id: "person-anna",
            kind: .person,
            slug: "anna-muster",
            title: "Anna Muster",
            subtitle: "Dirigentin · Violine",
            imageURL: URL(string: "https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&w=900&q=85")
        ),
        DirectoryItem(
            id: "ensemble-kammerorchester",
            kind: .ensemble,
            slug: "kammerorchester-muenchen",
            title: "Kammerorchester München",
            subtitle: "Kammerorchester",
            imageURL: URL(string: "https://images.unsplash.com/photo-1465847899084-d164df4dedc6?auto=format&fit=crop&w=1200&q=85")
        ),
        DirectoryItem(
            id: "venue-gasteig",
            kind: .venue,
            slug: "gasteig-hp8",
            title: "Gasteig HP8",
            subtitle: "München",
            imageURL: URL(string: "https://images.unsplash.com/photo-1503095396549-807759245b35?auto=format&fit=crop&w=1200&q=85")
        ),
        DirectoryItem(
            id: "work-symphonie-fantastique",
            kind: .work,
            slug: nil,
            title: "Symphonie fantastique",
            subtitle: "Hector Berlioz · op. 14",
            imageURL: nil
        )
    ]

    static let entityDetails: [EntityDetail] = directory.map { item in
        EntityDetail(
            id: item.id,
            kind: item.kind,
            slug: item.slug,
            title: item.title,
            subtitle: item.subtitle,
            primaryImageURL: item.imageURL,
            fields: [
                "description_de": .string("Ein redaktionell gepflegter Eintrag aus Klangradar. In der Live-App werden hier Biografie, Hintergrund, Programmbezug und weitere verifizierte Angaben aus Supabase angezeigt.")
            ],
            gallery: [],
            events: SampleData.events.prefix(2).map {
                LinkedEvent(
                    id: $0.id.uuidString,
                    slug: $0.slug,
                    title: $0.title,
                    startDate: $0.startDate,
                    venueName: $0.venueName,
                    role: item.kind == .person ? "Mitwirkende" : nil
                )
            },
            similar: directory.filter { $0.kind == item.kind && $0.id != item.id }
        )
    }

    static let collections: [EditorialCollection] = [
        EditorialCollection(
            id: "collection-week",
            slug: "diese-woche",
            title: "Diese Woche hören",
            subtitle: "Ausgewählt von der Klangradar-Redaktion",
            description: "Konzerte und Programme, die in den nächsten Tagen besonders neugierig machen.",
            coverImageURL: events.first?.primaryImageURL,
            events: events
        )
    ]
}
