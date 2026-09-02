import Foundation

public struct WorkAuthor: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

public struct WorkSummary: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let slug: String
    public let title: String
    public let subtitle: String?
    public let language: String?
    public let firstPublishedYear: Int?
    public let authors: [WorkAuthor]
    public let editionsCount: Int
    public let hasTextFile: Bool
    public let coverImageURL: URL?
    public let coverTone: String?
    public let coverVariant: String?
    public let coverGlyph: String?

    enum CodingKeys: String, CodingKey {
        case id, slug, title, subtitle, language, authors
        case firstPublishedYear = "first_published_year"
        case editionsCount = "editions_count"
        case hasTextFile = "has_text_file"
        case coverImageURL = "cover_image_url"
        case coverTone = "cover_tone"
        case coverVariant = "cover_variant"
        case coverGlyph = "cover_glyph"
    }
}
