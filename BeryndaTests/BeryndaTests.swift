import XCTest
@testable import Berynda

final class BeryndaTests: XCTestCase {
    func testAppConfigurationUsesHTTPS() {
        XCTAssertEqual(AppConfiguration.supportURL.scheme, "https")
        XCTAssertEqual(AppConfiguration.privacyURL.scheme, "https")
    }

    func testReopeningTheSameReaderCreatesANewPresentation() {
        let fileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let first = ReaderPresentation(fileID: fileID, fallbackTitle: "First", initialPage: 2)
        let second = ReaderPresentation(fileID: fileID, fallbackTitle: "Second", initialPage: 7)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first, second)
    }
}
