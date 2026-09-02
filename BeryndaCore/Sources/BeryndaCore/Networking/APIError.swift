import Foundation

public enum APIError: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int, requestID: String?)
    case decoding
    case transport
    case unsupportedContentType(String?)
    case responseTooLarge
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
