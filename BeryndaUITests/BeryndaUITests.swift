import XCTest

final class BeryndaUITests: XCTestCase {
    func testLaunchShowsCatalog() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Каталог"].waitForExistence(timeout: 10))
    }
}
