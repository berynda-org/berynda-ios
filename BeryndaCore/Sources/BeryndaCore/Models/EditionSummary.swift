import Foundation

public struct EditionSummary: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let work: UUID
    public let displayTitle: String
    public let language: String
    public let year: Int?
    public let publisherName: String?
    public let publicationPlace: String?
    public let pageCount: Int?
    public let readableFileID: UUID?
    public let canRead: Bool
    public let canDownload: Bool
    public let restrictionReason: String?

    enum CodingKeys: String, CodingKey {
        case id, work, language, year
        case displayTitle = "display_title"
        case publisherName = "publisher_name"
        case publicationPlace = "publication_place"
        case pageCount = "page_count"
        case readableFileID = "readable_file_id"
        case canRead = "can_read"
        case canDownload = "can_download"
        case restrictionReason = "restriction_reason"
    }
}
