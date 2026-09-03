import Foundation

public protocol LibraryRepository: Sendable {
    func continueReading(limit: Int) async throws -> ContinueReadingResponse
    func bibliographyLists() async throws -> [BibliographyList]
    func createList(title: String) async throws -> BibliographyList
    func quickAdd(
        workID: UUID?,
        fileID: UUID?,
        positionType: String?,
        positionValue: String?,
        pageNumber: Int?
    ) async throws -> BibliographyItem
    func publicCollections() async throws -> [PublicCollectionSummary]
    func savedCollections() async throws -> [PublicCollectionSummary]
    func setCollectionSaved(slug: String, saved: Bool) async throws
}

public struct LiveLibraryRepository: LibraryRepository {
    private let client: BeryndaAPIClient

    public init(client: BeryndaAPIClient) {
        self.client = client
    }

    public func continueReading(limit: Int = 20) async throws -> ContinueReadingResponse {
        try await client.request(.continueReading(limit: limit))
    }

    public func bibliographyLists() async throws -> [BibliographyList] {
        try await client.request(.bibliographyLists)
    }

    public func createList(title: String) async throws -> BibliographyList {
        try await client.request(
            .bibliographyLists,
            method: .post,
            body: CreateListBody(title: title.trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }

    public func quickAdd(
        workID: UUID?,
        fileID: UUID?,
        positionType: String?,
        positionValue: String?,
        pageNumber: Int?
    ) async throws -> BibliographyItem {
        try await client.request(
            .bibliographyQuickAdd,
            method: .post,
            body: QuickAddBody(
                work: workID,
                file: fileID,
                positionType: positionType,
                positionValue: positionValue,
                pageNumber: pageNumber
            )
        )
    }

    public func publicCollections() async throws -> [PublicCollectionSummary] {
        try await client.request(.publicCollections)
    }

    public func savedCollections() async throws -> [PublicCollectionSummary] {
        try await client.request(.savedCollections)
    }

    public func setCollectionSaved(slug: String, saved: Bool) async throws {
        _ = try await client.send(.collectionSave(slug: slug), method: saved ? .post : .delete)
    }
}

private struct CreateListBody: Encodable, Sendable {
    let title: String
}

private struct QuickAddBody: Encodable, Sendable {
    let work: UUID?
    let file: UUID?
    let positionType: String?
    let positionValue: String?
    let pageNumber: Int?

    enum CodingKeys: String, CodingKey {
        case work, file
        case positionType = "position_type"
        case positionValue = "position_value"
        case pageNumber = "page_number"
    }
}
