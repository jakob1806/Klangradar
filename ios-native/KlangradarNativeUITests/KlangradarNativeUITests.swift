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
        // Seit der englischen Oberfläche (String-Katalog) heißen die Tabs auf
        // englischen Simulatoren „Search“ usw. – Tests laufen immer auf Deutsch.
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
    }

    /// Tab-Knopf in der Tab-Leiste, sonst irgendwo (Seitenleiste/schwebende Leiste ab iOS 18).
    private func tabButton(_ name: String) -> XCUIElement {
        let inBar = app.tabBars.buttons[name]
        if inBar.waitForExistence(timeout: 5) { return inBar }
        return app.buttons[name].firstMatch
    }

    func testAllTabsOpen() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        for (tab, marker) in [("Suche", "Suche"), ("Karte", "Karte"), ("Kalender", "Kalender"), ("Profil", "Profil"), ("Home", "Klangradar")] {
            tabButton(tab).tap()
            XCTAssertTrue(app.staticTexts[marker].firstMatch.waitForExistence(timeout: 15) || app.navigationBars[marker].exists, "Tab \(tab) zeigt keinen Inhalt")
        }
    }

    func testHomeOpensEventDetail() {
        let hero = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Symphonie fantastique")).firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        hero.tap()
        XCTAssertTrue(app.staticTexts["Symphonie fantastique"].firstMatch.waitForExistence(timeout: 15))
    }

    func testCalendarMonthNavigation() {
        tabButton("Kalender").tap()
        let next = app.buttons["Nächster Monat"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        next.tap()
        app.buttons["Vorheriger Monat"].tap()
        XCTAssertTrue(app.staticTexts["Kalender"].firstMatch.exists)
    }

    func testSearchAcceptsInput() {
        tabButton("Suche").tap()
        let field = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("Bach")
        XCTAssertTrue((field.value as? String)?.hasPrefix("B") == true, "Suchfeld nimmt keine Eingabe an")
    }

    func testPlusPaywallOpensAndCloses() {
        tabButton("Profil").tap()
        let plus = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Klangradar Plus")).firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 15))
        plus.tap()
        XCTAssertTrue(app.staticTexts["Mehr aus jedem Konzertabend."].waitForExistence(timeout: 15))
        app.buttons["Schließen"].tap()
        XCTAssertTrue(plus.waitForExistence(timeout: 15))
    }
}
