import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol AuthenticationServing: Sendable {
    func login(email: String, password: String) async throws -> AuthSession
    func refresh(refreshToken: String) async throws -> AuthTokens
    func logout(accessToken: String, refreshToken: String) async throws
}

public actor LiveAuthenticationService: AuthenticationServing {
    private let baseURL: URL
    private let transport: any HTTPTransport
    private let language: @Sendable () -> String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        baseURL: URL,
        transport: any HTTPTransport = URLSessionTransport(),
        language: @escaping @Sendable () -> String = { "uk" }
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.language = language
    }

    public func login(email: String, password: String) async throws -> AuthSession {
        let body = LoginBody(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
        let response: LoginResponse = try await post(
            path: "auth/login/",
            body: body,
            bearerToken: nil,
            unauthorizedError: .invalidCredentials
        )
        let tokens = try AuthTokens(access: response.access, refresh: response.refresh)
        return AuthSession(tokens: tokens, user: response.user)
    }

    public func refresh(refreshToken: String) async throws -> AuthTokens {
        guard AuthTokens.isValidJWT(refreshToken) else { throw SessionError.invalidToken }
        let response: RefreshResponse = try await post(
            path: "auth/token/refresh/",
            body: RefreshBody(refresh: refreshToken),
            bearerToken: nil,
            unauthorizedError: .expired
        )
        return try AuthTokens(access: response.access, refresh: response.refresh)
    }

    public func logout(accessToken: String, refreshToken: String) async throws {
        guard AuthTokens.isValidJWT(accessToken), AuthTokens.isValidJWT(refreshToken) else {
            throw SessionError.invalidToken
        }
        let _: EmptyResponse = try await post(
            path: "auth/logout/",
            body: RefreshBody(refresh: refreshToken),
            bearerToken: accessToken,
            unauthorizedError: .expired,
            acceptsEmptyResponse: true
        )
    }

    private func post<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body,
        bearerToken: String?,
        unauthorizedError: SessionError,
        acceptsEmptyResponse: Bool = false
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw SessionError.invalidResponse
        }

        let requestData: Data
        do {
            requestData = try encoder.encode(body)
        } catch {
            throw SessionError.invalidResponse
        }
        guard requestData.count <= 64 * 1_024 else { throw SessionError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = requestData
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(language(), forHTTPHeaderField: "Accept-Language")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await transport.data(for: request, maximumBytes: 1 * 1_024 * 1_024)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw SessionError.unavailable
        }

        switch http.statusCode {
        case 200..<300:
            if acceptsEmptyResponse, data.isEmpty, let empty = EmptyResponse() as? Response {
                return empty
            }
            let contentType = http.value(forHTTPHeaderField: "Content-Type")?
                .split(separator: ";", maxSplits: 1)
                .first
                .map { String($0).lowercased() }
            guard contentType == "application/json" || contentType?.hasSuffix("+json") == true else {
                throw SessionError.invalidResponse
            }
            do {
                return try decoder.decode(Response.self, from: data)
            } catch let error as SessionError {
                throw error
            } catch {
                throw SessionError.invalidResponse
            }
        case 401:
            throw unauthorizedError
        default:
            throw SessionError.unavailable
        }
    }
}

private struct LoginBody: Encodable {
    let email: String
    let password: String
}

private struct RefreshBody: Encodable {
    let refresh: String
}

private struct LoginResponse: Decodable {
    let access: String
    let refresh: String
    let user: UserProfile
}

private struct RefreshResponse: Decodable {
    let access: String
    let refresh: String
}

private struct EmptyResponse: Decodable {
    init() {}
}
