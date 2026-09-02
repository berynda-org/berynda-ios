import Foundation
import XCTest
@testable import BeryndaCore

final class APIEndpointTests: XCTestCase {
    private let baseURL = URL(string: "https://berynda.org/api/v1/")!
    private let fileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    func testReaderInfoURLIsAbsoluteAndPreservesBasePath() throws {
        let url = try XCTUnwrap(APIEndpoint.readerInfo(fileID: fileID).url(relativeTo: baseURL))

        XCTAssertEqual(url.baseURL, nil)
        XCTAssertEqual(
            url.absoluteString,
            "https://berynda.org/api/v1/files/44444444-4444-4444-4444-444444444444/reader-info/"
        )
    }

    func testPageImageClampsParametersOnAbsoluteURL() throws {
        let url = try XCTUnwrap(
            APIEndpoint.pageImage(fileID: fileID, page: -9, width: 9_000)
                .url(relativeTo: baseURL)
        )
        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )

        XCTAssertEqual(
            components.path,
            "/api/v1/files/44444444-4444-4444-4444-444444444444/pages/1/"
        )
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "width" })?.value,
            "2000"
        )
    }
}
