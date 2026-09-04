import Foundation
import XCTest
import BeryndaCore
@testable import Berynda

final class BeryndaTests: XCTestCase {
    func testAppConfigurationUsesHTTPS() {
        XCTAssertEqual(AppConfiguration.apiBaseURL.scheme, "https")
        XCTAssertTrue(AppConfiguration.apiBaseURL.absoluteString.hasSuffix("/api/v1/"))
        XCTAssertEqual(AppConfiguration.supportURL.scheme, "https")
        XCTAssertEqual(AppConfiguration.privacyURL.scheme, "https")
    }

    func testReopeningTheSameReaderCreatesANewPresentation() {
        let fileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let first = ReaderPresentation(fileID: fileID, fallbackTitle: "First", initialPage: 2)
        let second = ReaderPresentation(fileID: fileID, fallbackTitle: "Second", initialPage: 7)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first, second)
    }

    func testProtectedReadingPositionSurvivesStoreRestartAndCanBeCleared() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeryndaTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let fileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

        let firstStore = LocalReadingPositionStore(directory: directory)
        await firstStore.save(page: 7, totalPages: 20, for: fileID)

        let relaunchedStore = LocalReadingPositionStore(directory: directory)
        let restored = await relaunchedStore.position(for: fileID)
        XCTAssertEqual(restored?.page, 7)
        XCTAssertEqual(restored?.totalPages, 20)

        await relaunchedStore.clearAll()
        let cleared = await relaunchedStore.position(for: fileID)
        XCTAssertNil(cleared)
    }

    @MainActor
    func testCatalogLoadsAndAppendsASecondPage() async throws {
        let firstPage = try decodePage(
            id: "11111111-1111-1111-1111-111111111111",
            title: "Енеїда",
            count: 2,
            next: "https://berynda.org/api/v1/works/?page=2"
        )
        let secondPage = try decodePage(
            id: "22222222-2222-2222-2222-222222222222",
            title: "Кобзар",
            count: 2,
            next: nil
        )
        let repository = CatalogRepositoryStub(pages: [1: firstPage, 2: secondPage])
        let model = CatalogViewModel(repository: repository)

        await model.load()
        guard case let .loaded(firstWorks, firstCount) = model.state else {
            return XCTFail("Expected the first page")
        }
        XCTAssertEqual(firstWorks.map(\.title), ["Енеїда"])
        XCTAssertEqual(firstCount, 2)

        await model.loadNextPageIfNeeded(after: firstWorks[0])
        guard case let .loaded(allWorks, totalCount) = model.state else {
            return XCTFail("Expected both pages")
        }
        XCTAssertEqual(allWorks.map(\.title), ["Енеїда", "Кобзар"])
        XCTAssertEqual(totalCount, 2)
        let requests = await repository.requests
        XCTAssertEqual(requests.map(\.page), [1, 2])
    }

    @MainActor
    func testWorkDetailEnrichesAThinListRowAndLoadsEditions() async throws {
        let summary = try Self.listRow()
        let repository = WorkDetailRepositoryStub(detail: try Self.detailRecord())
        let model = WorkDetailViewModel(work: summary, repository: repository)

        XCTAssertFalse(model.work.isDetailed)
        await model.load()

        XCTAssertTrue(model.work.isDetailed)
        XCTAssertEqual(model.work.contributorsByRole.map(\.role), ["author", "translator"])
        XCTAssertEqual(model.work.literaryForm?.name, "Драма")
        guard case let .loaded(editions) = model.editions else {
            return XCTFail("Expected editions, got \(model.editions)")
        }
        XCTAssertEqual(editions.count, 1)
        let identifiers = await repository.detailRequests
        XCTAssertEqual(identifiers, ["lisova-pisnia"])
    }

    @MainActor
    func testWorkDetailKeepsTheSummaryWhenEnrichmentFails() async throws {
        let summary = try Self.listRow()
        let repository = WorkDetailRepositoryStub(detail: nil)
        let model = WorkDetailViewModel(work: summary, repository: repository)

        await model.load()

        // A failed enrichment must not blank a page that already renders.
        XCTAssertEqual(model.work.title, summary.title)
        XCTAssertFalse(model.work.isDetailed)
        XCTAssertFalse(model.isEnriching)
        guard case .loaded = model.editions else {
            return XCTFail("Editions must still load when enrichment fails")
        }
    }

    @MainActor
    func testWorkDetailDoesNotRefetchARecordThatIsAlreadyDetailed() async throws {
        let detail = try Self.detailRecord()
        let repository = WorkDetailRepositoryStub(detail: detail)
        let model = WorkDetailViewModel(work: detail, repository: repository)

        await model.load()

        let identifiers = await repository.detailRequests
        XCTAssertTrue(identifiers.isEmpty)
    }

    @MainActor
    func testWorkDetailRetriesOnlyTheEditionsSection() async throws {
        let summary = try Self.listRow()
        let repository = WorkDetailRepositoryStub(detail: nil, editionsFailures: 1)
        let model = WorkDetailViewModel(work: summary, repository: repository)

        await model.load()
        guard case .failed = model.editions else {
            return XCTFail("Expected a failed editions section")
        }

        await model.loadEditions()
        guard case let .loaded(editions) = model.editions else {
            return XCTFail("Expected the retry to succeed")
        }
        XCTAssertEqual(editions.count, 1)
    }

    private static func listRow() throws -> WorkSummary {
        let json = """
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "slug": "lisova-pisnia",
          "title": "Лісова пісня",
          "subtitle": null,
          "language": "uk",
          "first_published_year": 1912,
          "authors": [{"id": "88888888-8888-8888-8888-888888888888", "display_name": "Леся Українка"}],
          "editions_count": 1,
          "has_text_file": true,
          "cover_image_url": null,
          "cover_tone": null,
          "cover_variant": null,
          "cover_glyph": null
        }
        """
        return try JSONDecoder().decode(WorkSummary.self, from: Data(json.utf8))
    }

    private static func detailRecord() throws -> WorkSummary {
        let json = """
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "slug": "lisova-pisnia",
          "title": "Лісова пісня",
          "original_title": "Лїсова пісня",
          "language": "uk",
          "first_published_year": 1912,
          "editions_count": 1,
          "literary_form": {"id": "44444444-4444-4444-4444-444444444444", "name": "Драма"},
          "genres": [],
          "topics": [],
          "contributions": [
            {"person_id": "88888888-8888-8888-8888-888888888888", "role": "author",
             "person_display_name": "Леся Українка", "display_name_override": null},
            {"person_id": "99999999-9999-9999-9999-999999999999", "role": "translator",
             "person_display_name": "Jerzy Litwiniuk", "display_name_override": null}
          ]
        }
        """
        return try JSONDecoder().decode(WorkSummary.self, from: Data(json.utf8))
    }

    private func decodePage(
        id: String,
        title: String,
        count: Int,
        next: String?
    ) throws -> PaginatedResponse<WorkSummary> {
        let nextJSON = next.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
          "count": \(count),
          "next": \(nextJSON),
          "previous": null,
          "results": [{
            "id": "\(id)",
            "slug": "\(id)",
            "title": "\(title)",
            "subtitle": null,
            "language": "uk",
            "first_published_year": null,
            "authors": [],
            "editions_count": 1,
            "has_text_file": true,
            "cover_image_url": null,
            "cover_tone": "oxblood",
            "cover_variant": "frame",
            "cover_glyph": null
          }]
        }
        """
        return try JSONDecoder().decode(
            PaginatedResponse<WorkSummary>.self,
            from: Data(json.utf8)
        )
    }
}

private actor CatalogRepositoryStub: CatalogRepository {
    struct Request: Sendable {
        let search: String?
        let page: Int
    }

    let pages: [Int: PaginatedResponse<WorkSummary>]
    private(set) var requests: [Request] = []

    init(pages: [Int: PaginatedResponse<WorkSummary>]) {
        self.pages = pages
    }

    func works(search: String?, page: Int) async throws -> PaginatedResponse<WorkSummary> {
        requests.append(Request(search: search, page: page))
        guard let response = pages[page] else { throw StubError.missingPage }
        return response
    }

    func work(identifier: String) async throws -> WorkSummary {
        throw StubError.unsupported
    }

    func editions(workID: UUID) async throws -> [EditionSummary] {
        throw StubError.unsupported
    }

    enum StubError: Error {
        case missingPage
        case unsupported
    }
}

private actor WorkDetailRepositoryStub: CatalogRepository {
    private let detail: WorkSummary?
    private var remainingEditionsFailures: Int
    private(set) var detailRequests: [String] = []

    init(detail: WorkSummary?, editionsFailures: Int = 0) {
        self.detail = detail
        self.remainingEditionsFailures = editionsFailures
    }

    func works(search: String?, page: Int) async throws -> PaginatedResponse<WorkSummary> {
        throw StubError.unsupported
    }

    func work(identifier: String) async throws -> WorkSummary {
        detailRequests.append(identifier)
        guard let detail else { throw StubError.unsupported }
        return detail
    }

    func editions(workID: UUID) async throws -> [EditionSummary] {
        if remainingEditionsFailures > 0 {
            remainingEditionsFailures -= 1
            throw StubError.unsupported
        }
        let json = """
        [{
          "id": "aaaaaaaa-0000-0000-0000-000000000001",
          "work": "\(workID.uuidString.lowercased())",
          "display_title": "Київ, 1963",
          "language": "uk",
          "year": 1963,
          "publisher_name": "Дніпро",
          "publication_place": "Київ",
          "page_count": 240,
          "readable_file_id": null,
          "can_read": false,
          "can_download": false,
          "restriction_reason": "Файл ще не оцифровано"
        }]
        """
        return try JSONDecoder().decode([EditionSummary].self, from: Data(json.utf8))
    }

    enum StubError: Error {
        case unsupported
    }
}
