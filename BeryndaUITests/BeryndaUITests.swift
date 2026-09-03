import XCTest

final class BeryndaUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Каталог"].waitForExistence(timeout: 10))
    }

    func testLaunchShowsAnonymousCatalog() {
        XCTAssertTrue(app.staticTexts["Кобзар"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Каталог"].isSelected)
    }

    func testUkrainianSearchReturnsMatchingWork() {
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))

        searchField.tap()
        searchField.typeText("Кобзар")

        XCTAssertTrue(app.staticTexts["Кобзар"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Лісова пісня"].exists)
    }

    func testCatalogLoadsTheNextPage() {
        let finalWork = app.staticTexts["Слово о полку Ігоревім"]
        if !finalWork.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(finalWork.waitForExistence(timeout: 5))
    }

    func testReadableEditionOpensAndTurnsPage() {
        openWork(named: "Кобзар")

        let readButton = app.buttons["Читати видання"]
        XCTAssertTrue(readButton.waitForExistence(timeout: 5))
        readButton.tap()

        XCTAssertTrue(app.staticTexts["I · с. 1 з 3"].waitForExistence(timeout: 5))
        let nextButton = app.buttons["reader.next-page"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap()
        XCTAssertTrue(app.staticTexts["II · с. 2 з 3"].waitForExistence(timeout: 5))
    }

    func testRestrictedEditionExplainsWhyItCannotOpen() {
        openWork(named: "Лісова пісня")

        XCTAssertTrue(
            app.staticTexts["Читання обмежено правовласником"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.buttons["Читати видання"].exists)
    }

    func testEditionWithoutAFileDegradesSafely() {
        let work = app.staticTexts["Слово о полку Ігоревім"]
        if !work.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(work.waitForExistence(timeout: 5))
        work.tap()

        XCTAssertTrue(
            app.staticTexts["Файл для читання недоступний"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.buttons["Читати видання"].exists)
    }

    func testSignInUnlocksProfileAndLibrary() {
        app.tabBars.buttons["Профіль"].tap()
        let authenticate = app.buttons["profile.authenticate"]
        XCTAssertTrue(authenticate.waitForExistence(timeout: 5))
        authenticate.tap()

        let email = app.textFields["auth.email"]
        let password = app.secureTextFields["auth.password"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("reader@example.org")
        password.tap()
        password.typeText("password123")
        app.buttons["auth.submit"].tap()

        XCTAssertTrue(app.buttons["Редагувати профіль"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Бібліотека"].tap()
        XCTAssertTrue(
            app.staticTexts["Відкрийте видання — воно з’явиться тут."]
                .waitForExistence(timeout: 5)
        )
    }

    private func openWork(named title: String) {
        let work = app.staticTexts[title]
        XCTAssertTrue(work.waitForExistence(timeout: 5))
        work.tap()
        XCTAssertTrue(app.staticTexts["Видання"].waitForExistence(timeout: 5))
    }
}
