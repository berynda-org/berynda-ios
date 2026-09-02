import Foundation

public protocol CatalogRepository: Sendable {
    func works(search: String?, page: Int) async throws -> PaginatedResponse<WorkSummary>
    func editions(workID: UUID) async throws -> [EditionSummary]
}

public struct LiveCatalogRepository: CatalogRepository {
    private let client: BeryndaAPIClient

    public init(client: BeryndaAPIClient) {
        self.client = client
    }

    public func works(search: String?, page: Int) async throws -> PaginatedResponse<WorkSummary> {
        try await client.request(.works(search: search, page: page))
    }

    public func editions(workID: UUID) async throws -> [EditionSummary] {
        let response: EditionCollection = try await client.request(.editions(workID: workID))
        return response.values
    }
}

private struct EditionCollection: Decodable, Sendable {
    let values: [EditionSummary]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let page = try? container.decode(PaginatedResponse<EditionSummary>.self) {
            values = page.results
        } else {
            values = try container.decode([EditionSummary].self)
        }
    }
}
