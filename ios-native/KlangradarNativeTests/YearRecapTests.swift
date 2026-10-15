import XCTest
@testable import KlangradarNative

final class YearRecapTests: XCTestCase {
    private let mahler = UUID(), brahms = UUID(), hall = UUID(), opera = UUID()

    private func date(_ value: String) -> Date { FlexibleDateParser.date(from: value)! }

    private func visit(_ title: String, _ when: String, venueID: UUID, venue: String, works: [VisitedWork], genres: [String] = []) -> VisitedConcert {
        VisitedConcert(id: UUID(), title: title, venueID: venueID, venue: venue, city: "München", attendedAt: date(when), genres: genres, works: works, event: nil)
    }

    private func work(_ title: String, composer: UUID, name: String) -> VisitedWork {
        VisitedWork(id: UUID(), title: title, composerID: composer, composerName: name, compositionYear: nil)
    }

    func testRecapCountsOnlySelectedYearAndRanks() {
        let m2 = work("Sinfonie Nr. 2", composer: mahler, name: "Gustav Mahler")
        let m5 = work("Sinfonie Nr. 5", composer: mahler, name: "Gustav Mahler")
        let b4 = work("Sinfonie Nr. 4", composer: brahms, name: "Johannes Brahms")
        let visits = [
            visit("Auftakt", "2026-01-10T19:30:00+01:00", venueID: hall, venue: "Isarphilharmonie", works: [m2], genres: ["Sinfonik"]),
            visit("Mahler 5", "2026-03-02T19:30:00+01:00", venueID: hall, venue: "Isarphilharmonie", works: [m5, b4], genres: ["Sinfonik"]),
            visit("Oper", "2026-03-20T19:00:00+01:00", venueID: opera, venue: "Nationaltheater", works: [], genres: ["Oper"]),
            visit("Vorjahr", "2025-12-01T19:30:00+01:00", venueID: opera, venue: "Nationaltheater", works: [b4])
        ]
        let recap = YearRecap.make(year: 2026, visits: visits)
        XCTAssertEqual(recap.concerts, 3)
        XCTAssertEqual(recap.works, 3)
        XCTAssertEqual(recap.composers, 2)
        XCTAssertEqual(recap.venues, 2)
        XCTAssertEqual(recap.topComposer, .init(name: "Gustav Mahler", count: 2))
        XCTAssertEqual(recap.topVenue, .init(name: "Isarphilharmonie", count: 2))
        XCTAssertEqual(recap.busiestMonth, .init(name: "März", count: 2))
        XCTAssertEqual(recap.topGenre?.name, "Sinfonik")
        XCTAssertEqual(recap.firstConcert, "Auftakt")
        XCTAssertEqual(YearRecap.years(in: visits), [2026, 2025])
    }

    func testComposerCountedOncePerConcert() {
        let songs = (1...5).map { work("Lied \($0)", composer: brahms, name: "Johannes Brahms") }
        let visits = [
            visit("Liederabend", "2026-05-01T19:30:00+02:00", venueID: hall, venue: "Prinzregententheater", works: songs),
            visit("Mahler A", "2026-06-01T19:30:00+02:00", venueID: hall, venue: "Isarphilharmonie", works: [work("Sinfonie Nr. 1", composer: mahler, name: "Gustav Mahler")]),
            visit("Mahler B", "2026-07-01T19:30:00+02:00", venueID: hall, venue: "Isarphilharmonie", works: [work("Sinfonie Nr. 3", composer: mahler, name: "Gustav Mahler")])
        ]
        XCTAssertEqual(YearRecap.make(year: 2026, visits: visits).topComposer?.name, "Gustav Mahler")
    }
}
