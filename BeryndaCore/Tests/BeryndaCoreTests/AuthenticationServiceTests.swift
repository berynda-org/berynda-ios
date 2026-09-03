import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import BeryndaCore

private struct AuthStubResponse: Sendable {
    let status: Int
    let data: Data
    let headers: [String: String]

    init(status: Int, data: Data = Data(), headers: [String: String] = [:]) {
        self.status = status
        self.data = data
        self.headers = headers
    }
}

private struct RecordedAuthRequest: Sendable {
    let url: URL?
    let method: String?
    let headers: [String: String]
    let body: Data?
    let maximumBytes: Int
}

private actor AuthTransportStub: HTTPTransport {
    private var responses: [AuthStubResponse]
    private var requests: [RecordedAuthRequest] = []

    init(_ responses: [AuthStubResponse]) {
        self.responses = responses
    }

    func data(
        for request: URLRequest,
        maximumBytes: Int
    ) async throws -> (Data, HTTPURLResponse) {
        requests.append(
            RecordedAuthRequest(
                url: request.url,
                method: request.httpMethod,
                headers: request.allHTTPHeaderFields ?? [:],
                body: request.httpBody,
                maximumBytes: maximumBytes
            )
        )
        let next = responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: next.status,
            httpVersion: nil,
            headerFields: next.headers
        )!
        return (next.data, response)
    }

    func recordedRequests() -> [RecordedAuthRequest] { requests }
}

final class AuthenticationServiceTests: XCTestCase {
    func testLoginRefreshAndLogoutMatchMobileBodyContract() async throws {
        let access1 = "header.access-one.signature"
        let refresh1 = "header.refresh-one.signature"
        let access2 = "header.access-two.signature"
        let refresh2 = "header.refresh-two.signature"
        let loginData = Data(
            """
            {"access":"\(access1)","refresh":"\(refresh1)","user":{"id":"11111111-1111-1111-1111-111111111111","email":"reader@example.org","display_name":"Reader"}}
            """.utf8
        )
        let refreshData = Data(
            "{\"access\":\"\(access2)\",\"refresh\":\"\(refresh2)\"}".utf8
        )
        let transport = AuthTransportStub([
            AuthStubResponse(
                status: 200,
                data: loginData,
                headers: ["Content-Type": "application/json"]
            ),
            AuthStubResponse(
                status: 200,
                data: refreshData,
                headers: ["Content-Type": "application/json"]
            ),
            AuthStubResponse(status: 204),
        ])
        let service = LiveAuthenticationService(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        let session = try await service.login(
            email: "  reader@example.org  ",
            password: "correct horse battery staple"
        )
        let rotated = try await service.refresh(refreshToken: session.tokens.refresh)
        try await service.logout(
            accessToken: rotated.access,
            refreshToken: rotated.refresh
        )

        XCTAssertEqual(session.tokens, try AuthTokens(access: access1, refresh: refresh1))
        XCTAssertEqual(session.user.email, "reader@example.org")
        XCTAssertEqual(rotated, try AuthTokens(access: access2, refresh: refresh2))

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://berynda.org/api/v1/auth/login/",
            "https://berynda.org/api/v1/auth/token/refresh/",
            "https://berynda.org/api/v1/auth/logout/",
        ])
        XCTAssertEqual(requests.map(\.method), ["POST", "POST", "POST"])
        XCTAssertTrue(requests.allSatisfy { $0.maximumBytes == 1 * 1_024 * 1_024 })
        XCTAssertTrue(requests.allSatisfy { $0.headers["Content-Type"] == "application/json" })
        XCTAssertNil(requests[0].headers["Authorization"])
        XCTAssertNil(requests[1].headers["Authorization"])
        XCTAssertEqual(requests[2].headers["Authorization"], "Bearer \(access2)")

        let loginBody = try jsonObject(requests[0].body)
        let refreshBody = try jsonObject(requests[1].body)
        let logoutBody = try jsonObject(requests[2].body)
        XCTAssertEqual(loginBody["email"] as? String, "reader@example.org")
        XCTAssertEqual(loginBody["password"] as? String, "correct horse battery staple")
        XCTAssertEqual(refreshBody["refresh"] as? String, refresh1)
        XCTAssertEqual(logoutBody["refresh"] as? String, refresh2)
    }

    func testLogin401IsInvalidCredentialsWithoutReturningServerDetail() async {
        let privateBody = Data(
            #"{"error":{"code":"CREDENTIALS_INVALID","message":"private server detail"}}"#.utf8
        )
        let transport = AuthTransportStub([
            AuthStubResponse(
                status: 401,
                data: privateBody,
                headers: ["Content-Type": "application/json"]
            ),
        ])
        let service = LiveAuthenticationService(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        do {
            _ = try await service.login(email: "reader@example.org", password: "wrong")
            XCTFail("Expected invalid credentials")
        } catch {
            XCTAssertEqual(error as? SessionError, .invalidCredentials)
            XCTAssertFalse(error.localizedDescription.contains("private server detail"))
        }
    }

    func testRefresh401ExpiresSession() async {
        let transport = AuthTransportStub([AuthStubResponse(status: 401)])
        let service = LiveAuthenticationService(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        do {
            _ = try await service.refresh(refreshToken: "header.refresh.signature")
            XCTFail("Expected expiry")
        } catch {
            XCTAssertEqual(error as? SessionError, .expired)
        }
    }

    func testSuccessfulHTMLLoginIsRejected() async {
        let transport = AuthTransportStub([
            AuthStubResponse(
                status: 200,
                data: Data("<html></html>".utf8),
                headers: ["Content-Type": "text/html"]
            ),
        ])
        let service = LiveAuthenticationService(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        do {
            _ = try await service.login(email: "reader@example.org", password: "secret")
            XCTFail("Expected invalid response")
        } catch {
            XCTAssertEqual(error as? SessionError, .invalidResponse)
        }
    }

    func testRegistrationAndPasswordResetUseNativeJSONContracts() async throws {
        let registration = Data(
            #"{"id":"11111111-1111-1111-1111-111111111111","email":"reader@example.org","activation":"email_confirmation_required"}"#.utf8
        )
        let transport = AuthTransportStub([
            AuthStubResponse(status: 201, data: registration, headers: ["Content-Type": "application/json"]),
            AuthStubResponse(status: 200, data: Data(#"{"status":"ok"}"#.utf8), headers: ["Content-Type": "application/json"]),
        ])
        let service = LiveAuthenticationService(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        let result = try await service.register(
            email: " reader@example.org ",
            password: "password123",
            displayName: " Читач "
        )
        try await service.requestPasswordReset(email: " reader@example.org ")

        XCTAssertTrue(result.requiresEmailConfirmation)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.path }, [
            "/api/v1/auth/register/",
            "/api/v1/auth/password-reset/",
        ])
        let registrationBody = try jsonObject(requests[0].body)
        XCTAssertEqual(registrationBody["email"] as? String, "reader@example.org")
        XCTAssertEqual(registrationBody["display_name"] as? String, "Читач")
        XCTAssertEqual(registrationBody["password"] as? String, "password123")
        let resetBody = try jsonObject(requests[1].body)
        XCTAssertEqual(resetBody["email"] as? String, "reader@example.org")
    }

    private func jsonObject(_ data: Data?) throws -> [String: Any] {
        let data = try XCTUnwrap(data)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
