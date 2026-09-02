import XCTest
@testable import BeryndaCore

final class AppRouteTests: XCTestCase {
    func testAllowsKnownUniversalLinkHost() {
        XCTAssertEqual(
            AppRoute(url: URL(string: "https://berynda.org/works/eneida")!),
            .work(slug: "eneida")
        )
    }

    func testRejectsLookalikeHost() {
        XCTAssertNil(AppRoute(url: URL(string: "https://berynda.org.example/works/eneida")!))
    }

    func testParsesCustomSchemeHostAsRouteComponent() {
        XCTAssertEqual(
            AppRoute(url: URL(string: "berynda://works/eneida")!),
            .work(slug: "eneida")
        )
    }

    func testValidatesReaderUUIDAndPositivePage() {
        let url = URL(string: "berynda://read/44444444-4444-4444-4444-444444444444?page=7")!
        XCTAssertEqual(
            AppRoute(url: url),
            .reader(fileID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!, page: 7)
        )
        XCTAssertNil(
            AppRoute(url: URL(string: "https://berynda.org/read/not-a-uuid?page=0")!)
        )
    }
}
