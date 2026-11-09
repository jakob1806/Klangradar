// Erstellt von Claude Code (09.11.2026): Platzerkennung v3 – Testfälle
// je Ticketanbieter.
import XCTest
@testable import KlangradarNative

final class SeatParserTests: XCTestCase {
    /// München Ticket / Münchner Philharmoniker (Isarphilharmonie).
    func testMuenchenTicketIsarphilharmonie() {
        let text = """
        München
        Ticket
        9009498100000063882836500
        Mittwoch, 16.12.2026 19:30 Uhr
        1. Abonnementkonzert H4
        Isarphilharmonie im Gasteig HP8
        Hans-Preißinger-Straße 8
        81379 München
        U30
        Rang Mitte
        Reihe: 1
        Sitz: 7
        Tür M, 2. OG
        Kat. V U30-Ticket
        Preis: 11,00 EUR
        Ticketnummer:
        290326182937-1
        MPHILweb//8329620//290326182937-1
        """
        let seat = TicketStore.parseSeat(text)
        XCTAssertEqual(seat.block, "Rang Mitte")
        XCTAssertEqual(seat.row, "1")
        XCTAssertEqual(seat.seat, "7")
        XCTAssertEqual(seat.seatLabel, "Sitz")
        XCTAssertEqual(seat.entrance, "M")
        XCTAssertEqual(seat.entranceLabel, "Tür")
        XCTAssertEqual(seat.extras.first?.value, "2. OG")
        XCTAssertFalse(seat.summary.contains("8"), "Hausnummer/PLZ dürfen nicht als Platz erscheinen")
    }

    /// Eventim-Tabelle: Kopfzeile, Werte darunter.
    func testTableHeader() {
        let seat = TicketStore.parseSeat("Eingang Block Reihe Platz\nWest C 14 22\nPreis 49,00 EUR")
        XCTAssertEqual(seat.entrance, "West")
        XCTAssertEqual(seat.block, "C")
        XCTAssertEqual(seat.row, "14")
        XCTAssertEqual(seat.seat, "22")
    }

    func testInlinePairsAndSlash() {
        XCTAssertEqual(TicketStore.parseSeat("Parkett links Reihe 5 Platz 12").row, "5")
        let slash = TicketStore.parseSeat("Reihe/Platz 14/22")
        XCTAssertEqual(slash.row, "14")
        XCTAssertEqual(slash.seat, "22")
    }

    func testRankWithoutLabel() {
        let seat = TicketStore.parseSeat("2. Rang links\nReihe 3\nPlatz 18")
        XCTAssertEqual(seat.block, "2. Rang links")
        XCTAssertEqual(seat.summary, "2. Rang links · Reihe 3 · Platz 18")
    }

    func testExclusionsNeverBecomeSeat() {
        let seat = TicketStore.parseSeat("Kat. 2 Platz\nPreis: 35 EUR\n80333 München")
        XCTAssertTrue(seat.row.isEmpty)
        XCTAssertNotEqual(seat.seat, "80333")
    }

    func testLegacySeatDecodes() throws {
        let data = Data(#"{"entrance":"A","block":"B","row":"3","seat":"9"}"#.utf8)
        let seat = try JSONDecoder().decode(ConcertSeat.self, from: data)
        XCTAssertEqual(seat.summary, "Block B · Reihe 3 · Platz 9 · Eingang A")
    }
}

final class SeatParserRegressionTests: XCTestCase {
    /// „Zeigen Sie einfach den QR-Code digital am Einlass vor.“ ist kein Eingang „vor“.
    func testEinlassSentenceIsNoEntrance() {
        let seat = TicketStore.parseSeat("Sie einfach den QR-Code\ndigital am Einlass vor.\nEinlass wird kontrolliert!\nSitz : 7")
        XCTAssertTrue(seat.entrance.isEmpty)
        XCTAssertEqual(seat.seat, "7")
    }

    /// Bezeichnung und Wert als getrennte Texterkennungs-Zeilen nebeneinander.
    func testValueBesideLabelWithBoxes() {
        let lines = [
            SeatParser.Line(text: "Sitz:", box: CGRect(x: 0.62, y: 0.40, width: 0.05, height: 0.012)),
            SeatParser.Line(text: "7", box: CGRect(x: 0.69, y: 0.40, width: 0.01, height: 0.012))
        ]
        XCTAssertEqual(SeatParser.parse(lines).seat, "7")
    }
}
