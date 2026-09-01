import Foundation

/// Editierbarer Inhalt für `MarketingHomeScreenView`/`MarketingContentEditorView`
/// — persistiert lokal (UserDefaults + Documents-Ordner für importierte
/// Fotos), damit Kategorien/Veranstaltungen/Texte/Bilder direkt im
/// Simulator angepasst werden können, bevor ein Screenshot gemacht wird.
/// Rein clientseitig, kein Supabase-Zugriff.

struct MarketingHeroData: Codable, Equatable {
    /// Optionaler Bezug zu einem echten Klangradar-Event. Die frei wählbaren
    /// Texte/Bilder bleiben dennoch für eine Aufnahme überschreibbar.
    var sourceEventID: UUID?
    var imagePath: String?
    var dateLabel: String
    var title: String
    var venue: String

    init(sourceEventID: UUID? = nil, imagePath: String?, dateLabel: String, title: String, venue: String) {
        self.sourceEventID = sourceEventID
        self.imagePath = imagePath
        self.dateLabel = dateLabel
        self.title = title
        self.venue = venue
    }

    private enum CodingKeys: String, CodingKey { case sourceEventID, imagePath, dateLabel, title, venue }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceEventID = try container.decodeIfPresent(UUID.self, forKey: .sourceEventID)
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        dateLabel = try container.decode(String.self, forKey: .dateLabel)
        title = try container.decode(String.self, forKey: .title)
        venue = try container.decode(String.self, forKey: .venue)
    }
}

struct MarketingEventData: Codable, Equatable, Hashable, Identifiable {
    var id: UUID = UUID()
    /// Ist gesetzt, wenn die Marketing-Karte ein echtes Klangradar-Event
    /// repräsentiert. Dann öffnet ein Tap dessen vollwertige Detailansicht.
    var sourceEventID: UUID?
    var imagePath: String?
    var title: String
    var subtitle: String

    init(id: UUID = UUID(), sourceEventID: UUID? = nil, imagePath: String? = nil, title: String, subtitle: String) {
        self.id = id
        self.sourceEventID = sourceEventID
        self.imagePath = imagePath
        self.title = title
        self.subtitle = subtitle
    }

    private enum CodingKeys: String, CodingKey { case id, sourceEventID, imagePath, title, subtitle }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sourceEventID = try container.decodeIfPresent(UUID.self, forKey: .sourceEventID)
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decode(String.self, forKey: .subtitle)
    }
}

struct MarketingModuleData: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var events: [MarketingEventData]
}

struct MarketingSearchContent: Codable, Equatable {
    var headline: String
    var events: [MarketingEventData]
}

struct MarketingContent: Codable, Equatable {
    var hero: MarketingHeroData
    var modules: [MarketingModuleData]
    var search: MarketingSearchContent

    private enum CodingKeys: String, CodingKey { case hero, modules, search }

    init(hero: MarketingHeroData, modules: [MarketingModuleData], search: MarketingSearchContent) {
        self.hero = hero
        self.modules = modules
        self.search = search
    }

    // Bereits gespeicherte Marketing-Inhalte aus der ersten Version hatten
    // noch keinen eigenen Suche-Tab. Sie bleiben beim Update verwendbar und
    // bekommen ohne sichtbaren Bruch die Standard-Suche ergänzt.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hero = try container.decode(MarketingHeroData.self, forKey: .hero)
        modules = try container.decode([MarketingModuleData].self, forKey: .modules)
        search = try container.decodeIfPresent(MarketingSearchContent.self, forKey: .search)
            ?? MarketingSearchContent(
                headline: "Konzerte entdecken",
                events: [
                    MarketingEventData(title: "Symphonieorchester des Bayerischen Rundfunks", subtitle: "Do., 1. Okt. 20:00 · Isarphilharmonie"),
                    MarketingEventData(title: "Sir Simon Rattle | Beethoven 9", subtitle: "Do., 24. Sept. 19:00 · Herkulessaal")
                ]
            )
    }
}

@MainActor
final class MarketingContentStore: ObservableObject {
    @Published var content: MarketingContent {
        didSet { persist() }
    }

    private static let storageKey = "marketingContent.v2"
    private static let imagesDirectoryName = "MarketingImages"

    init() {
        content = Self.loadPersisted() ?? Self.defaultContent
    }

    func resetToDefaults() {
        content = Self.defaultContent
    }

    /// Speichert importierte Foto-Daten unter Documents/MarketingImages und
    /// liefert den relativen Dateinamen, der in `imagePath` abgelegt wird —
    /// `resolvedURL(for:)` unterscheidet daran lokale Dateien von http(s)-URLs.
    func saveImportedImage(_ data: Data) -> String? {
        let filename = "\(UUID().uuidString).jpg"
        let url = Self.imagesDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            return filename
        } catch { return nil }
    }

    static func resolvedURL(for imagePath: String?) -> URL? {
        guard let imagePath, !imagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if imagePath.hasPrefix("http://") || imagePath.hasPrefix("https://") {
            return URL(string: imagePath)
        }
        return imagesDirectory.appendingPathComponent(imagePath)
    }

    private static var imagesDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(imagesDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(content) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func loadPersisted() -> MarketingContent? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(MarketingContent.self, from: data)
    }

    static let defaultSearch = MarketingSearchContent(
        headline: "Münchens große Orchester",
        events: [
            MarketingEventData(
                sourceEventID: UUID(uuidString: "fdf33157-749a-4958-968c-f1e30861f3ee"),
                imagePath: "https://www.brso.de/wp-content/uploads/sites/2/16-9-simon-rattle-c-br-astrid-ackermann.jpg",
                title: "Sir Simon Rattle | Beethoven 9",
                subtitle: "Do., 24. Sept. 19:00 · Herkulessaal"
            ),
            MarketingEventData(
                sourceEventID: UUID(uuidString: "016bd554-d049-4093-9026-bfb8c03cc2cc"),
                imagePath: "https://www.mphil.de/fileadmin/_processed_/0/0/csm_Martha_Argerich_Lahav_Shani_credit_Caroline_Doutre_1000x1000_d1e5296819.jpg",
                title: "Martha Argerich & Lahav Shani",
                subtitle: "Fr., 18. Sept. 19:30 · Isarphilharmonie"
            )
        ]
    )

    static let defaultContent = MarketingContent(
        hero: MarketingHeroData(
            sourceEventID: UUID(uuidString: "1c0802e6-7462-4a7a-976d-7839766b88c8"),
            imagePath: "https://www.brso.de/wp-content/uploads/sites/2/sir-simon-rattle-dirigiert-mahler-c-peter-meisel-1200x675.jpg",
            dateLabel: "SA., 7. NOV. · 19:00",
            title: "Sir Simon Rattle | Mahler 2: »Auferstehungssymphonie«",
            venue: "Isarphilharmonie (Gasteig HP8)"
        ),
        modules: [
            MarketingModuleData(title: "Highlights der Saison", events: [
                MarketingEventData(
                    sourceEventID: UUID(uuidString: "fdf33157-749a-4958-968c-f1e30861f3ee"),
                    imagePath: "https://www.brso.de/wp-content/uploads/sites/2/16-9-simon-rattle-c-br-astrid-ackermann.jpg",
                    title: "Sir Simon Rattle | Beethoven 9",
                    subtitle: "Do., 24. Sept. 19:00 · Herkulessaal"
                ),
                MarketingEventData(
                    sourceEventID: UUID(uuidString: "016bd554-d049-4093-9026-bfb8c03cc2cc"),
                    imagePath: "https://www.mphil.de/fileadmin/_processed_/0/0/csm_Martha_Argerich_Lahav_Shani_credit_Caroline_Doutre_1000x1000_d1e5296819.jpg",
                    title: "Martha Argerich & Lahav Shani",
                    subtitle: "Fr., 18. Sept. 19:30 · Isarphilharmonie"
                )
            ]),
            MarketingModuleData(title: "Münchner Philharmoniker", events: [
                MarketingEventData(
                    sourceEventID: UUID(uuidString: "fa53c97b-c8e6-4862-b079-20c7ec7708d8"),
                    imagePath: "https://www.mphil.de/fileadmin/_processed_/8/8/csm_Zubin_Mehta_credit_Co_Merz_1400x1400_a8ca6a3e30.jpg",
                    title: "Zubin Mehta | Mozart & Weber",
                    subtitle: "Do., 8. Okt. 19:30 · Isarphilharmonie"
                ),
                MarketingEventData(
                    sourceEventID: UUID(uuidString: "98f7c0b1-3780-467b-aaa1-2ba78a72f298"),
                    imagePath: "https://www.mphil.de/fileadmin/_processed_/2/1/csm_Anja_Bihlmaier_credit_Neda_Navaee_1000x1000_95a76bcd42.jpg",
                    title: "Anja Bihlmaier | Ravel & Schostakowitsch",
                    subtitle: "Fr., 16. Okt. 19:30 · Isarphilharmonie"
                )
            ])
        ],
        search: defaultSearch
    )
}
