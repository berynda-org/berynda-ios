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
        let url = URL(string: "berynda://read/44444444-4444-4444-4444-444444444444?p=7")!
        XCTAssertEqual(
            AppRoute(url: url),
            .reader(fileID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!, page: 7)
        )

        XCTAssertEqual(
            AppRoute(
                url: URL(
                    string: "https://berynda.org/read/44444444-4444-4444-4444-444444444444?page=8"
                )!
            ),
            .reader(fileID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!, page: 8)
        )
    }

    func testAllowsReaderLinkWithoutPDFPage() {
        XCTAssertEqual(
            AppRoute(
                url: URL(
                    string: "https://berynda.org/read/44444444-4444-4444-4444-444444444444?cfi=epubcfi%28%2F6%2F2%29"
                )!
            ),
            .reader(fileID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!, page: nil)
        )
    }

    func testRejectsMalformedOrAmbiguousReaderPages() {
        let invalidURLs = [
            "https://berynda.org/read/not-a-uuid",
            "https://berynda.org/read/44444444-4444-4444-4444-444444444444?p=",
            "https://berynda.org/read/44444444-4444-4444-4444-444444444444?p=zero",
            "https://berynda.org/read/44444444-4444-4444-4444-444444444444?p=0",
            "https://berynda.org/read/44444444-4444-4444-4444-444444444444?p=-1",
            "https://berynda.org/read/44444444-4444-4444-4444-444444444444?p=1000001",
            "https://berynda.org/read/44444444-4444-4444-4444-444444444444?p=2&page=3",
            "https://berynda.org/read/44444444-4444-4444-4444-444444444444?p=2&p=3",
        ]

        for rawURL in invalidURLs {
            XCTAssertNil(AppRoute(url: URL(string: rawURL)!), rawURL)
        }
    }

    func testRejectsUnsafeURLShapesAndWorkIdentifiers() {
        let invalidURLs = [
            "http://berynda.org/works/eneida",
            "https://user@berynda.org/works/eneida",
            "https://berynda.org:8443/works/eneida",
            "https://berynda.org/works/eneida/extra",
            "https://berynda.org/works/not_allowed",
            "berynda://works:99/eneida",
        ]

        for rawURL in invalidURLs {
            XCTAssertNil(AppRoute(url: URL(string: rawURL)!), rawURL)
        }
    }
}
