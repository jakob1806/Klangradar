import XCTest
@testable import KlangradarNative

final class ConcertEventTests: XCTestCase {
    func testDecodesSupabaseEventShape() throws {
        let json = #"""
        {
          "id": "A1000000-0000-0000-0000-000000000001",
          "slug": "symphonie-fantastique",
          "title": "Symphonie fantastique",
          "subtitle": "Münchner Philharmoniker",
          "start_datetime": "2026-08-09T19:30:00.000+02:00",
          "image_urls": ["https://example.com/event.jpg"],
          "status": "scheduled",
          "venues": {
            "id": "B1000000-0000-0000-0000-000000000001",
            "name": "Gasteig HP8"
          }
        }
        """#.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let event = try decoder.decode(ConcertEvent.self, from: json)

        XCTAssertEqual(event.title, "Symphonie fantastique")
        XCTAssertEqual(event.venueName, "Gasteig HP8")
        XCTAssertNotNil(event.startDate)
    }

    func testPreviewRepositoryProvidesEvents() async throws {
        let events = try await PreviewEventRepository().upcomingEvents(limit: 2)
        XCTAssertEqual(events.count, 2)
    }

    func testEventUsesGalleryFallbackWhenOwnImageIsMissing() {
        let event = ConcertEvent(
            id: UUID(), slug: "fallback", title: "Fallback", subtitle: nil,
            startDatetime: "2026-08-09T19:30:00+02:00", imageUrls: [], status: "scheduled",
            venues: nil, fallbackImageUrls: ["https://example.com/gallery.jpg"]
        )
        XCTAssertEqual(event.primaryImageURL?.absoluteString, "https://example.com/gallery.jpg")
    }

    func testPreviewDetailContainsProgramAndParticipants() async throws {
        let detail = try await PreviewEventRepository().eventDetail(slug: "symphonie-fantastique")
        XCTAssertFalse(detail?.objects("event_works").isEmpty ?? true)
        XCTAssertFalse(detail?.objects("event_participants").isEmpty ?? true)
    }
}
