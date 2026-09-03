import Foundation

public struct WorkAuthor: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

public struct WorkSummary: Decodable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let slug: String
    public let title: String
    public let subtitle: String?
    public let description: String?
    public let language: String?
    public let firstPublishedYear: Int?
    public let workType: String?
    public let rightsSummary: String?
    public let pdStatus: String?
    public let pages: Int?
    public let authors: [WorkAuthor]
    public let editionsCount: Int
    public let hasTextFile: Bool
    public let coverImageURL: URL?
    public let coverTone: String?
    public let coverVariant: String?
    public let coverGlyph: String?

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        slug = try container.decode(String.self, forKey: .slug)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        firstPublishedYear = try container.decodeIfPresent(Int.self, forKey: .firstPublishedYear)
        workType = try container.decodeIfPresent(String.self, forKey: .workType)
        rightsSummary = try container.decodeIfPresent(String.self, forKey: .rightsSummary)
        pdStatus = try container.decodeIfPresent(String.self, forKey: .pdStatus)
        pages = try container.decodeIfPresent(Int.self, forKey: .pages)
        editionsCount = (try? container.decode(Int.self, forKey: .editionsCount)) ?? 0
        hasTextFile = (try? container.decode(Bool.self, forKey: .hasTextFile)) ?? false
        coverImageURL = try container.decodeIfPresent(URL.self, forKey: .coverImageURL)
        coverTone = try container.decodeIfPresent(String.self, forKey: .coverTone)
        coverVariant = try container.decodeIfPresent(String.self, forKey: .coverVariant)
        coverGlyph = try container.decodeIfPresent(String.self, forKey: .coverGlyph)
        if let listAuthors = try? container.decode([WorkAuthor].self, forKey: .authors) {
            authors = listAuthors
        } else {
            let contributions = (try? container.decode([WorkContribution].self, forKey: .contributions)) ?? []
            authors = contributions
                .filter { $0.role == "author" || $0.role == "translator" || $0.role == "editor" || $0.role == "compiler" }
                .map { WorkAuthor(id: $0.personID, displayName: $0.displayName) }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, slug, title, subtitle, description, language, authors, pages
        case workType = "work_type"
        case rightsSummary = "rights_summary"
        case pdStatus = "pd_status"
        case firstPublishedYear = "first_published_year"
        case editionsCount = "editions_count"
        case hasTextFile = "has_text_file"
        case coverImageURL = "cover_image_url"
        case coverTone = "cover_tone"
        case coverVariant = "cover_variant"
        case coverGlyph = "cover_glyph"
        case contributions
    }
}

private struct WorkContribution: Decodable {
    let personID: UUID
    let role: String
    let personDisplayName: String
    let displayNameOverride: String?

    var displayName: String { displayNameOverride?.nilIfEmpty ?? personDisplayName }

    enum CodingKeys: String, CodingKey {
        case personID = "person_id"
        case role
        case personDisplayName = "person_display_name"
        case displayNameOverride = "display_name_override"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
