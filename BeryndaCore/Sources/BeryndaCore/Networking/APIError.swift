import Foundation

public struct APIErrorContext: Equatable, Sendable {
    public let code: String?
    public let requestID: String?

    public init(code: String? = nil, requestID: String? = nil) {
        self.code = code
        self.requestID = requestID
    }
}

public enum APIError: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidResponse
    case unauthorized(APIErrorContext)
    case forbidden(APIErrorContext)
    case notFound(APIErrorContext)
    case rateLimited(retryAfter: TimeInterval?, context: APIErrorContext)
    case server(status: Int, context: APIErrorContext)
    case decoding
    case transport
    case unsupportedContentType(String?)
    case responseTooLarge
}

public extension APIError {
    var context: APIErrorContext? {
        switch self {
        case let .unauthorized(context), let .forbidden(context), let .notFound(context):
            context
        case let .rateLimited(_, context), let .server(_, context):
            context
        case .invalidConfiguration, .invalidResponse, .decoding, .transport,
             .unsupportedContentType, .responseTooLarge:
            nil
        }
    }
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration, .invalidResponse:
            return "Некоректна конфігурація сервісу."
        case .unauthorized:
            return "Потрібно увійти в обліковий запис."
        case .forbidden:
            return "Немає дозволу на цю дію."
        case .notFound:
            return "Матеріал не знайдено."
        case .rateLimited:
            return "Забагато запитів. Спробуйте трохи пізніше."
        case .server:
            return "Сервіс тимчасово недоступний."
        case .decoding:
            return "Сервіс повернув неочікувану відповідь."
        case .transport:
            return "Не вдалося з’єднатися з мережею."
        case .unsupportedContentType:
            return "Сервіс повернув непідтримуваний тип матеріалу."
        case .responseTooLarge:
            return "Матеріал завеликий для безпечного відкриття."
        }
    }
}
