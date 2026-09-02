import SwiftUI

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
    // Nutzerfeedback: der Entdecken-Kachel in der Suche stand fest "KONZERT"
    // über jedem Titel, auch über einer Oper — jetzt pro Karte einstellbar.
    var categoryLabel: String

    init(id: UUID = UUID(), sourceEventID: UUID? = nil, imagePath: String? = nil, title: String, subtitle: String, categoryLabel: String = "KONZERT") {
        self.id = id
        self.sourceEventID = sourceEventID
        self.imagePath = imagePath
        self.title = title
        self.subtitle = subtitle
        self.categoryLabel = categoryLabel
    }

    private enum CodingKeys: String, CodingKey { case id, sourceEventID, imagePath, title, subtitle, categoryLabel }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sourceEventID = try container.decodeIfPresent(UUID.self, forKey: .sourceEventID)
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decode(String.self, forKey: .subtitle)
        categoryLabel = try container.decodeIfPresent(String.self, forKey: .categoryLabel) ?? "KONZERT"
    }
}

struct MarketingModuleData: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var events: [MarketingEventData]

    /// Nutzerfeedback: "Gefolgte Personen"/"Gefolgte Ensembles" sollen die
    /// bereits genutzten runden Avatar-Kacheln zeigen, keine rechteckigen
    /// Event-Karten -- exakt wie `EntityRail` auf der echten Startseite
    /// (siehe HomeView.swift). Über den Titel erkannt statt eines eigenen
    /// gespeicherten Felds, damit bestehende Inhalte kompatibel bleiben.
    var isEntityRail: Bool { title == "Gefolgte Personen" || title == "Gefolgte Ensembles" }
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

    /// Für den Schnell-Editor beim direkten Antippen einer Karte in
    /// Home/Suche (statt über den Umweg des großen Formulars): findet die
    /// Karte anhand ihrer `MarketingEventData.id` in Modulen oder Suche und
    /// liefert eine schreibende Bindung darauf, oder `nil`, falls die Karte
    /// zwischenzeitlich entfernt wurde.
    func binding(forCardID id: UUID) -> Binding<MarketingEventData>? {
        for moduleIndex in content.modules.indices {
            if let eventIndex = content.modules[moduleIndex].events.firstIndex(where: { $0.id == id }) {
                return Binding(
                    get: { self.content.modules[moduleIndex].events[eventIndex] },
                    set: { self.content.modules[moduleIndex].events[eventIndex] = $0 }
                )
            }
        }
        if let eventIndex = content.search.events.firstIndex(where: { $0.id == id }) {
            return Binding(
                get: { self.content.search.events[eventIndex] },
                set: { self.content.search.events[eventIndex] = $0 }
            )
        }
        return nil
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

    // Nutzerfeedback: "auf dem Homescreen werden nicht alle Kategorien
    // angezeigt, die auch auf dem echten Homescreen angezeigt werden" -- der
    // Default hatte nur zwei frei erfundene Kategorien statt der
    // tatsächlichen Home-Reihen. Jetzt eine Kategorie pro Eintrag in
    // `HomeRecommendationCategory.defaultOrder` (HomeView.swift), mit dem
    // echten Titel -- Reihenfolge und Zusammensetzung entspricht damit dem,
    // was Nutzer:innen auf der echten Startseite sehen. Inhalte bleiben wie
    // gehabt frei bearbeitbar/löschbar.
    private static let sampleModuleEvents: [MarketingEventData] = [
        MarketingEventData(
            imagePath: "https://images.unsplash.com/photo-1465847899084-d164df4dedc6?w=1200&q=80",
            title: "Symphonieorchester des Bayerischen Rundfunks",
            subtitle: "Do., 1. Okt. 20:00 · Isarphilharmonie"
        ),
        MarketingEventData(
            imagePath: "https://images.unsplash.com/photo-1514320291840-2e0a9bf2a9ae?w=1200&q=80",
            title: "Sir Simon Rattle | Beethoven 9",
            subtitle: "Do., 24. Sept. 19:00 · Herkulessaal"
        )
    ]

    static let defaultContent = MarketingContent(
        hero: MarketingHeroData(
            sourceEventID: UUID(uuidString: "1c0802e6-7462-4a7a-976d-7839766b88c8"),
            imagePath: "https://www.brso.de/wp-content/uploads/sites/2/sir-simon-rattle-dirigiert-mahler-c-peter-meisel-1200x675.jpg",
            dateLabel: "SA., 7. NOV. · 19:00",
            title: "Sir Simon Rattle | Mahler 2: »Auferstehungssymphonie«",
            venue: "Isarphilharmonie (Gasteig HP8)"
        ),
        // Nutzerfeedback: "auf dem Homescreen werden nicht alle Kategorien
        // angezeigt, die auch auf dem echten Homescreen angezeigt werden" --
        // eine Kategorie pro Eintrag in HomeRecommendationCategory.defaultOrder
        // (HomeView.swift) statt fest verdrahteter Beispiel-Kategorien.
        modules: HomeRecommendationCategory.defaultOrder.map { category in
            MarketingModuleData(
                title: category.title,
                events: sampleModuleEvents.map { MarketingEventData(imagePath: $0.imagePath, title: $0.title, subtitle: $0.subtitle) }
            )
        },
        search: defaultSearch
    )
}
