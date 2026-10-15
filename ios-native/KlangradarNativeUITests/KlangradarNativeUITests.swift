import XCTest

/// Hauptabläufe mit festen Beispieldaten (KLANGRADAR_UI_TEST=1).
/// Ausführen: ios-native/run-ui-tests.sh
@MainActor
final class KlangradarNativeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["KLANGRADAR_UI_TEST"] = "1"
        app.launchArguments += ["-didCompleteOnboarding", "YES", "-appearance", "light"]
        app.launch()
    }

    func testAllTabsOpen() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        for (tab, marker) in [("Suche", "Suche"), ("Karte", "Karte"), ("Kalender", "Kalender"), ("Profil", "Profil"), ("Home", "Klangradar")] {
            tabBar.buttons[tab].tap()
            XCTAssertTrue(app.staticTexts[marker].firstMatch.waitForExistence(timeout: 5) || app.navigationBars[marker].exists, "Tab \(tab) zeigt keinen Inhalt")
        }
    }

    func testHomeOpensEventDetail() {
        let hero = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Symphonie fantastique")).firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        hero.tap()
        XCTAssertTrue(app.staticTexts["Symphonie fantastique"].firstMatch.waitForExistence(timeout: 5))
    }

    func testCalendarMonthNavigation() {
        app.tabBars.buttons["Kalender"].tap()
        let next = app.buttons["Nächster Monat"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        app.buttons["Vorheriger Monat"].tap()
        XCTAssertTrue(app.staticTexts["Kalender"].firstMatch.exists)
    }

    func testSearchAcceptsInput() {
        app.tabBars.buttons["Suche"].tap()
        let field = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Bach")
        XCTAssertEqual(field.value as? String, "Bach")
    }

    func testPlusPaywallOpensAndCloses() {
        app.tabBars.buttons["Profil"].tap()
        let plus = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Klangradar Plus")).firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        plus.tap()
        XCTAssertTrue(app.staticTexts["Mehr aus jedem Konzertabend."].waitForExistence(timeout: 5))
        app.buttons["Schließen"].tap()
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
    }
}
