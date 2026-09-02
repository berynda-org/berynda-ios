import Foundation

public struct AuthTokens: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let access: String
    public let refresh: String

    public init(access: String, refresh: String) throws {
        guard Self.isValidJWT(access), Self.isValidJWT(refresh) else {
            throw SessionError.invalidToken
        }
        self.access = access
        self.refresh = refresh
    }

    public var description: String { "AuthTokens(<redacted>)" }
    public var debugDescription: String { description }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let access = try container.decode(String.self, forKey: .access)
        let refresh = try container.decode(String.self, forKey: .refresh)
        guard Self.isValidJWT(access), Self.isValidJWT(refresh) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid token representation")
            )
        }
        self.access = access
        self.refresh = refresh
    }

    static func isValidJWT(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 16_384 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
            && value.split(separator: ".", omittingEmptySubsequences: false).count == 3
    }
}

public struct UserProfile: Codable, Equatable, Sendable {
    public let id: UUID
    public let email: String
    public let displayName: String?

    public init(id: UUID, email: String, displayName: String?) {
        self.id = id
        self.email = email
        self.displayName = displayName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
    }
}

public struct AuthSession: Equatable, Sendable {
    public let tokens: AuthTokens
    public let user: UserProfile

    public init(tokens: AuthTokens, user: UserProfile) {
        self.tokens = tokens
        self.user = user
    }
}

public enum SessionState: Equatable, Sendable {
    case anonymous
    case authenticated
    case expired
}

public enum SessionError: Error, Equatable, Sendable {
    case invalidCredentials
    case invalidToken
    case expired
    case invalidResponse
    case unavailable
    case storage
}

extension SessionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "Неправильна електронна адреса або пароль."
        case .invalidToken, .expired:
            "Сеанс завершився. Увійдіть знову."
        case .invalidResponse:
            "Сервіс повернув неочікувану відповідь."
        case .unavailable:
            "Не вдалося з’єднатися із сервісом."
        case .storage:
            "Не вдалося безпечно зберегти сеанс."
        }
    }
}
