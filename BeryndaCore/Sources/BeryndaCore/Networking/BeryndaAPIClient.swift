import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor BeryndaAPIClient {
    private let baseURL: URL
    private let transport: any HTTPTransport
    private let decoder: JSONDecoder
    private let language: @Sendable () -> String

    public init(
        baseURL: URL,
        transport: any HTTPTransport = URLSessionTransport(),
        language: @escaping @Sendable () -> String = { "uk" }
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.language = language
        self.decoder = JSONDecoder()
    }

    public func request<Response: Decodable & Sendable>(
        _ endpoint: APIEndpoint,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let payload = try await data(
            endpoint,
            accept: "application/json",
            maximumBytes: 5 * 1_024 * 1_024
        )
        guard payload.contentType == "application/json"
                || payload.contentType?.hasSuffix("+json") == true
        else {
            throw APIError.unsupportedContentType(payload.contentType)
        }
        do {
            return try decoder.decode(Response.self, from: payload.data)
        } catch {
            throw APIError.decoding
        }
    }

    public func data(
        _ endpoint: APIEndpoint,
        accept: String = "*/*",
        maximumBytes: Int? = nil
    ) async throws -> HTTPPayload {
        guard let url = endpoint.url(relativeTo: baseURL) else {
            throw APIError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(language(), forHTTPHeaderField: "Accept-Language")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as APIError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError.transport
        }

        switch response.statusCode {
        case 200..<300:
            let payload = HTTPPayload(
                data: data,
                contentType: response.value(forHTTPHeaderField: "Content-Type")?
                    .split(separator: ";", maxSplits: 1)
                    .first
                    .map { String($0).lowercased() },
                expectedLength: response.expectedContentLength >= 0
                    ? response.expectedContentLength
                    : nil
            )
            if let maximumBytes {
                if let expectedLength = payload.expectedLength,
                   expectedLength > Int64(maximumBytes) {
                    throw APIError.responseTooLarge
                }
                guard payload.data.count <= maximumBytes else {
                    throw APIError.responseTooLarge
                }
            }
            return payload
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 429:
            let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw APIError.rateLimited(retryAfter: retry)
        default:
            throw APIError.server(
                status: response.statusCode,
                requestID: response.value(forHTTPHeaderField: "X-Request-ID")
            )
        }
    }
}

public struct HTTPPayload: Sendable, Equatable {
    public let data: Data
    public let contentType: String?
    public let expectedLength: Int64?

    public init(data: Data, contentType: String?, expectedLength: Int64?) {
        self.data = data
        self.contentType = contentType
        self.expectedLength = expectedLength
    }
}
