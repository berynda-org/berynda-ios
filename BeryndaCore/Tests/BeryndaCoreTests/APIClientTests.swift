import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import BeryndaCore

private struct StubTransport: HTTPTransport {
    let handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try handler(request)
    }
}

final class APIClientTests: XCTestCase {
    func testAddsLanguageAndRequestIDWithoutCredentials() async throws {
        let data = try fixture("works-page")
        let transport = StubTransport { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Language"), "uk")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Request-ID"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (data, Self.response(url: request.url!, status: 200))
        }
        let client = BeryndaAPIClient(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        let page: PaginatedResponse<WorkSummary> = try await client.request(
            .works(search: "Енеїда", page: 1)
        )
        XCTAssertEqual(page.results.count, 1)
    }

    func testMapsForbiddenWithoutDecodingBody() async {
        let transport = StubTransport { request in
            (Data("secret detail".utf8), Self.response(url: request.url!, status: 403))
        }
        let client = BeryndaAPIClient(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        do {
            let _: PaginatedResponse<WorkSummary> = try await client.request(.works(search: nil, page: 1))
            XCTFail("Expected forbidden")
        } catch {
            XCTAssertEqual(error as? APIError, .forbidden)
        }
    }

    func testBinaryPayloadNormalizesContentType() async throws {
        let transport = StubTransport { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "Application/PDF; charset=binary"]
            )!
            return (Data("%PDF".utf8), response)
        }
        let client = BeryndaAPIClient(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        let payload = try await client.data(.readerContent(fileID: UUID(), structuredText: false))
        XCTAssertEqual(payload.contentType, "application/pdf")
    }

    func testTypedJSONRejectsSuccessfulHTMLResponse() async {
        let transport = StubTransport { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/html"]
            )!
            return (Data("<html></html>".utf8), response)
        }
        let client = BeryndaAPIClient(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        do {
            let _: PaginatedResponse<WorkSummary> = try await client.request(
                .works(search: nil, page: 1)
            )
            XCTFail("Expected content-type validation failure")
        } catch {
            XCTAssertEqual(error as? APIError, .unsupportedContentType("text/html"))
        }
    }

    func testTypedJSONRejectsOversizedDeclaredResponse() async {
        let transport = StubTransport { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json",
                    "Content-Length": "6000000",
                ]
            )!
            return (Data("{}".utf8), response)
        }
        let client = BeryndaAPIClient(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        do {
            let _: PaginatedResponse<WorkSummary> = try await client.request(
                .works(search: nil, page: 1)
            )
            XCTFail("Expected size validation failure")
        } catch {
            XCTAssertEqual(error as? APIError, .responseTooLarge)
        }
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private static func response(url: URL, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}
