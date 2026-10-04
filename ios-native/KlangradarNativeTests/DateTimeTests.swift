import XCTest
@testable import KlangradarNative

final class DateTimeTests: XCTestCase {
    func testParsesFractionalAndPlainISO8601() {
        let a = FlexibleDateParser.date(from: "2026-08-09T19:30:00.000+02:00")
        let b = FlexibleDateParser.date(from: "2026-08-09T19:30:00+02:00")
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b)
    }

    func testFormatsInBerlinTimeRegardlessOfDeviceZone() {
        // 17:30 UTC im Sommer = 19:30 MESZ
        let date = FlexibleDateParser.date(from: "2026-08-09T17:30:00Z")!
        XCTAssertEqual(KlangradarDateTime.string(date, format: "HH:mm"), "19:30")
    }

    func testWinterTimeUsesCET() {
        let date = FlexibleDateParser.date(from: "2026-12-20T18:30:00Z")!
        XCTAssertEqual(KlangradarDateTime.string(date, format: "HH:mm"), "19:30")
    }

    func testDateOnlyValueKeepsBerlinDay() {
        let date = FlexibleDateParser.date(from: "1990-05-17")!
        XCTAssertEqual(KlangradarDateTime.string(date, format: "yyyy-MM-dd"), "1990-05-17")
    }

    func testLateEveningEventStaysOnSameCalendarDay() {
        // 23:30 MESZ = 21:30 UTC -> muss im Kalender noch der 9. sein
        let date = FlexibleDateParser.date(from: "2026-08-09T21:30:00Z")!
        let day = FlexibleDateParser.date(from: "2026-08-09")!
        XCTAssertTrue(KlangradarDateTime.calendar.isDate(date, inSameDayAs: day))
    }

    func testInvalidInputReturnsNil() {
        XCTAssertNil(FlexibleDateParser.date(from: "bald"))
        XCTAssertNil(FlexibleDateParser.date(from: ""))
    }
}
