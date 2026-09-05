import Foundation
import XCTest
import BeryndaCore
import ReadiumShared
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

    @MainActor
    func testServerRefusalToRecordStopsLocalAndRemoteSaves() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeryndaTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let store = LocalReadingPositionStore(directory: directory)
        let repository = ReaderPersistenceStub(recorded: false)
        let model = try await makeReaderModel(repository: repository, store: store)

        model.selectPage(2)
        await model.flushPosition()

        // The server keeps no history for this reader, so the client must not
        // keep a local resume copy either.
        let saved = await store.position(for: ReaderPersistenceStub.fileID)
        XCTAssertNil(saved)

        // And it must stop asking: a refusal holds for the rest of the session.
        model.selectPage(3)
        await model.flushPosition()
        let attempts = await repository.saveAttempts
        XCTAssertEqual(attempts, 1)
    }

    @MainActor
    func testPositionIsKeptWhenTheServerRecordsIt() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeryndaTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let store = LocalReadingPositionStore(directory: directory)
        let repository = ReaderPersistenceStub(recorded: true)
        let model = try await makeReaderModel(repository: repository, store: store)

        model.selectPage(2)
        await model.flushPosition()

        let saved = await store.position(for: ReaderPersistenceStub.fileID)
        XCTAssertEqual(saved?.page, 2)
    }

    @MainActor
    func testTransientSaveFailureIsNotTreatedAsAPolicyRefusal() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeryndaTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let store = LocalReadingPositionStore(directory: directory)
        let repository = ReaderPersistenceStub(recorded: nil)
        let model = try await makeReaderModel(repository: repository, store: store)

        model.selectPage(2)
        await model.flushPosition()

        // A thrown error says nothing about the reader's history policy, so
        // the local resume survives and the client keeps trying.
        let saved = await store.position(for: ReaderPersistenceStub.fileID)
        XCTAssertEqual(saved?.page, 2)

        model.selectPage(3)
        await model.flushPosition()
        let attempts = await repository.saveAttempts
        XCTAssertEqual(attempts, 2)
    }

    func testPageCacheEvictsLeastRecentlyUsedBeyondItsPageLimit() async {
        let cache = ReaderPageCache(maximumPages: 3, maximumBytes: 10 * 1_024 * 1_024)
        for page in 1...3 {
            await cache.store(.image(Data(repeating: 0x41, count: 16)), for: page)
        }
        // Touching page 1 makes page 2 the least recently used.
        _ = await cache.content(for: 1)
        await cache.store(.image(Data(repeating: 0x41, count: 16)), for: 4)

        let cached = await cache.cachedPages
        XCTAssertEqual(cached, [1, 3, 4])
    }

    func testPageCacheHonoursItsByteCeiling() async {
        let cache = ReaderPageCache(maximumPages: 100, maximumBytes: 1_000)
        for page in 1...10 {
            await cache.store(.image(Data(repeating: 0x41, count: 400)), for: page)
        }

        let bytes = await cache.byteCount
        let count = await cache.pageCount
        XCTAssertLessThanOrEqual(bytes, 1_000)
        XCTAssertEqual(count, 2)
    }

    func testPageCacheSkipsAnEntryLargerThanTheWholeBudget() async {
        let cache = ReaderPageCache(maximumPages: 8, maximumBytes: 1_000)
        await cache.store(.image(Data(repeating: 0x41, count: 4_000)), for: 1)

        let count = await cache.pageCount
        let bytes = await cache.byteCount
        XCTAssertEqual(count, 0)
        XCTAssertEqual(bytes, 0)
    }

    @MainActor
    func testTurningTwoHundredPagesKeepsMemoryAndRequestsBounded() async throws {
        let repository = PagedReaderStub(totalPages: 200)
        let model = try await makeReaderModel(repository: repository, store: nil)

        for page in 2...200 {
            model.selectPage(page)
            await model.settle()
        }

        // The cache is what stops a long session from growing without limit.
        let cachedPages = await model.cachedPageCountForTesting
        XCTAssertLessThanOrEqual(cachedPages, 8)

        // Every page fetched at most a bounded number of times: once on
        // display, plus at most one prefetch of the same page from a
        // neighbour. Unbounded refetching would show up here as a large max.
        let perPage = await repository.requestsPerPage
        let worst = perPage.values.max() ?? 0
        XCTAssertLessThanOrEqual(worst, 3, "page requested \(worst) times: \(perPage)")
    }

    @MainActor
    func testPagingBackToACachedPageDoesNotRefetchIt() async throws {
        let repository = PagedReaderStub(totalPages: 10)
        let model = try await makeReaderModel(repository: repository, store: nil)

        model.selectPage(2)
        await model.settle()
        let afterFirstVisit = await repository.requestsPerPage[2] ?? 0

        model.selectPage(3)
        await model.settle()
        model.selectPage(2)
        await model.settle()

        let afterReturn = await repository.requestsPerPage[2] ?? 0
        XCTAssertEqual(afterReturn, afterFirstVisit)
    }

    @MainActor
    func testAPageRequestPastTheLastPageDoesNotWedgeNavigation() async throws {
        let repository = PagedReaderStub(totalPages: 10)
        let model = try await makeReaderModel(repository: repository, store: nil)

        model.selectPage(999)
        await model.settle()

        // The request is clamped, so the completion guard matches and the
        // loading flag clears; previously it stayed true and both page
        // buttons went permanently dead.
        XCTAssertEqual(model.currentPage, 10)
        XCTAssertFalse(model.pageIsLoading)
        XCTAssertTrue(model.canGoBackward)
    }

    @MainActor
    func testReleasingCachedPagesKeepsTheVisiblePageOnScreen() async throws {
        let repository = PagedReaderStub(totalPages: 10)
        let model = try await makeReaderModel(repository: repository, store: nil)

        model.selectPage(4)
        await model.settle()
        await model.releaseCachedPages()

        let emptied = await model.cachedPageCountForTesting
        XCTAssertEqual(emptied, 0)

        await model.recoverIfNeeded()
        // Content was never cleared, so there is nothing to recover and no
        // redundant refetch is issued.
        XCTAssertNotNil(model.content)
    }

    @MainActor
    private func makeReaderModel(
        repository: any ReaderRepository,
        store: LocalReadingPositionStore?
    ) async throws -> ReaderViewModel {
        // Not `let store = store ?? …`: a local shadowing a parameter cannot
        // reference it in its own initializer.
        let positionStore = try store ?? makeTemporaryPositionStore()
        let authentication = UITestAuthenticationService()
        let session = SessionController(
            tokenStore: UITestTokenStore(),
            authentication: authentication
        )
        _ = try await session.signIn(email: "reader@example.org", password: "password123")

        let account = AccountViewModel(
            session: session,
            authentication: authentication,
            repository: UITestAccountRepository(),
            localPositions: positionStore
        )
        let model = ReaderViewModel(
            fileID: ReaderPersistenceStub.fileID,
            repository: repository,
            session: session,
            account: account,
            localPositions: positionStore
        )
        await model.load()
        return model
    }

    @MainActor
    func testSpreadShowsAFacingPageAndAdvancesTwoAtATime() async throws {
        let repository = PagedReaderStub(totalPages: 10)
        let model = try await makeReaderModel(repository: repository, store: nil)

        XCTAssertTrue(model.supportsSpread)
        XCTAssertEqual(model.pageStep, 1)

        await model.setSpreadEnabled(true)
        XCTAssertNotNil(model.facingContent)
        XCTAssertEqual(model.pageStep, 2)

        model.selectPage(model.currentPage + model.pageStep)
        await model.settle()
        XCTAssertEqual(model.currentPage, 3)
        XCTAssertNotNil(model.facingContent)
    }

    @MainActor
    func testSpreadDropsTheFacingPageAtTheEndOfTheDocument() async throws {
        let repository = PagedReaderStub(totalPages: 4)
        let model = try await makeReaderModel(repository: repository, store: nil)
        await model.setSpreadEnabled(true)

        model.selectPage(4)
        await model.settle()

        // Nothing faces the last page, so the spread collapses to one page
        // and forward navigation stops.
        XCTAssertNil(model.facingContent)
        XCTAssertEqual(model.pageStep, 1)
        XCTAssertFalse(model.canGoForward)
    }

    @MainActor
    func testForwardStopsWhenTheSpreadAlreadyShowsTheLastPage() async throws {
        let repository = PagedReaderStub(totalPages: 4)
        let model = try await makeReaderModel(repository: repository, store: nil)
        await model.setSpreadEnabled(true)

        model.selectPage(3)
        await model.settle()

        // Pages 3 and 4 are both on screen, so there is nowhere further to go.
        XCTAssertNotNil(model.facingContent)
        XCTAssertFalse(model.canGoForward)
    }

    @MainActor
    func testDisablingSpreadClearsTheFacingPage() async throws {
        let repository = PagedReaderStub(totalPages: 10)
        let model = try await makeReaderModel(repository: repository, store: nil)

        await model.setSpreadEnabled(true)
        XCTAssertNotNil(model.facingContent)

        await model.setSpreadEnabled(false)
        XCTAssertNil(model.facingContent)
        XCTAssertEqual(model.pageStep, 1)
    }

    @MainActor
    func testTextReaderNeverOffersASpread() async throws {
        let repository = ReaderPersistenceStub(recorded: true)
        let model = try await makeReaderModel(repository: repository, store: nil)

        // Text reflows, so there is no facing page to show.
        XCTAssertFalse(model.supportsSpread)
        await model.setSpreadEnabled(true)
        XCTAssertNil(model.facingContent)
    }

    @MainActor
    func testExportAndPrintAreOfferedForAPermittedFullDocument() async throws {
        let repository = RightsReaderStub(
            pageDelivery: "client_full",
            canDownloadFile: true,
            canPrint: true
        )
        let model = try await makeReaderModel(repository: repository, store: nil)

        XCTAssertTrue(model.canExportDocument)
        XCTAssertTrue(model.canPrintDocument)
    }

    @MainActor
    func testExportAndPrintAreWithheldWithoutTheRight() async throws {
        let repository = RightsReaderStub(
            pageDelivery: "client_full",
            canDownloadFile: false,
            canPrint: false
        )
        let model = try await makeReaderModel(repository: repository, store: nil)

        XCTAssertFalse(model.canExportDocument)
        XCTAssertFalse(model.canPrintDocument)
    }

    @MainActor
    func testPerPageDeliveryNeverOffersAWholeDocument() async throws {
        // Even with the download right granted, per-page delivery means the
        // app never holds the complete file, so it must not offer one.
        let repository = RightsReaderStub(
            pageDelivery: "client_per_page",
            canDownloadFile: true,
            canPrint: true
        )
        let model = try await makeReaderModel(repository: repository, store: nil)

        XCTAssertFalse(model.canExportDocument)
        XCTAssertFalse(model.canPrintDocument)
    }

    @MainActor
    func testPagedTextTurnsPagesWithoutRefetching() async throws {
        let repository = PagedTextStub(
            body: "Сторінка перша. Сторінка друга. Сторінка третя.",
            pageOffsets: [0, 16, 32]
        )
        let model = try await makeReaderModel(repository: repository, store: nil)

        XCTAssertTrue(model.supportsTextPaging)
        XCTAssertEqual(model.textPageCount, 3)
        guard case let .text(continuous, _) = try XCTUnwrap(model.content) else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(continuous, "Сторінка перша. Сторінка друга. Сторінка третя.")

        model.setTextPaged(true)
        guard case let .text(firstPage, _) = try XCTUnwrap(model.content) else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(firstPage, "Сторінка перша. ")

        model.selectPage(3)
        guard case let .text(thirdPage, _) = try XCTUnwrap(model.content) else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(thirdPage, "Сторінка третя.")

        // The body was fetched once; paging is pure slicing.
        let fetches = await repository.textFetches
        XCTAssertEqual(fetches, 1)
    }

    @MainActor
    func testLeavingPagedTextRestoresTheWholeBody() async throws {
        let repository = PagedTextStub(
            body: "Перша. Друга.",
            pageOffsets: [0, 7]
        )
        let model = try await makeReaderModel(repository: repository, store: nil)

        model.setTextPaged(true)
        model.selectPage(2)
        model.setTextPaged(false)

        guard case let .text(body, _) = try XCTUnwrap(model.content) else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(body, "Перша. Друга.")
        // The page is kept, so returning to paged mode lands where it was.
        XCTAssertEqual(model.currentPage, 2)
    }

    @MainActor
    func testPlainTextOffersNoPaging() async throws {
        let repository = PagedTextStub(body: "Суцільний текст", pageOffsets: [])
        let model = try await makeReaderModel(repository: repository, store: nil)

        XCTAssertFalse(model.supportsTextPaging)
        model.setTextPaged(true)
        XCTAssertFalse(model.isTextPaged)
        XCTAssertFalse(model.canGoForward)
    }

    @MainActor
    func testPagedTextBoundsNavigationToItsPageCount() async throws {
        let repository = PagedTextStub(body: "Перша. Друга.", pageOffsets: [0, 7])
        let model = try await makeReaderModel(repository: repository, store: nil)
        model.setTextPaged(true)

        XCTAssertEqual(model.navigablePageCount, 2)
        XCTAssertTrue(model.canGoForward)

        model.selectPage(99)
        XCTAssertEqual(model.currentPage, 2)
        XCTAssertFalse(model.canGoForward)
        XCTAssertTrue(model.canGoBackward)
    }

    @MainActor
    func testPublicationNeverOverwritesTheServerPositionWithAPageNumber() async throws {
        let repository = PublicationReaderStub()
        let model = try await makeReaderModel(repository: repository, store: nil)

        await model.flushPosition()

        // A publication has no page of its own, and the web reader stores an
        // epub_cfi for these. Sending "page 1" would destroy the reader's real
        // position on every other client.
        let attempts = await repository.saveAttempts
        XCTAssertEqual(attempts, 0)
    }

    @MainActor
    func testPublicationContentsFlattenNestedChaptersIntoIndentLevels() {
        let toc = [
            ReadiumShared.Link(
                href: "chapter1.xhtml",
                title: "Розділ перший",
                children: [
                    ReadiumShared.Link(href: "chapter1.xhtml#s1", title: "Частина 1"),
                    ReadiumShared.Link(href: "chapter1.xhtml#s2", title: "Частина 2"),
                ]
            ),
            ReadiumShared.Link(href: "chapter2.xhtml", title: "Розділ другий"),
        ]

        let entries = EPUBReaderController.flatten(toc)

        XCTAssertEqual(
            entries.map(\.title),
            ["Розділ перший", "Частина 1", "Частина 2", "Розділ другий"]
        )
        XCTAssertEqual(entries.map(\.level), [0, 1, 1, 0])
    }

    @MainActor
    func testPublicationContentsFallBackToTheHrefWhenATitleIsMissing() {
        let entries = EPUBReaderController.flatten([
            ReadiumShared.Link(href: "nav.xhtml", title: nil),
            ReadiumShared.Link(href: "blank.xhtml", title: "   "),
        ])

        XCTAssertEqual(entries.map(\.title), ["nav.xhtml", "blank.xhtml"])
    }

    @MainActor
    func testPublicationContentsEntriesAreUniquelyIdentified() {
        // The same href at two depths must not collide, or the list would
        // drop rows.
        let entries = EPUBReaderController.flatten([
            ReadiumShared.Link(href: "a.xhtml", title: "A", children: [ReadiumShared.Link(href: "a.xhtml", title: "A again")]),
        ])

        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
    }

    func testRecentlyViewedKeepsMostRecentFirstWithoutDuplicates() async throws {
        let store = try makeRecentlyViewedStore()
        let first = try Self.recentWork(id: "11111111-1111-1111-1111-111111111111", title: "Кобзар")
        let second = try Self.recentWork(id: "22222222-2222-2222-2222-222222222222", title: "Енеїда")

        await store.record(first, at: Date(timeIntervalSince1970: 100))
        await store.record(second, at: Date(timeIntervalSince1970: 200))
        // Re-opening moves a work to the front rather than duplicating it.
        await store.record(first, at: Date(timeIntervalSince1970: 300))

        let recent = await store.recent()
        XCTAssertEqual(recent.map(\.title), ["Кобзар", "Енеїда"])
    }

    func testRecentlyViewedIsBounded() async throws {
        let store = try makeRecentlyViewedStore(limit: 3)
        for index in 1...6 {
            let work = try Self.recentWork(
                id: "0000000\(index)-1111-1111-1111-111111111111",
                title: "Твір \(index)"
            )
            await store.record(work, at: Date(timeIntervalSince1970: TimeInterval(index)))
        }

        let recent = await store.recent()
        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent.map(\.title), ["Твір 6", "Твір 5", "Твір 4"])
    }

    func testRecentlyViewedSurvivesAStoreRestartAndCanBeCleared() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeryndaTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let store = RecentlyViewedStore(directory: directory)
        await store.record(try Self.recentWork(
            id: "11111111-1111-1111-1111-111111111111",
            title: "Кобзар"
        ))

        let relaunched = RecentlyViewedStore(directory: directory)
        let restored = await relaunched.recent()
        XCTAssertEqual(restored.map(\.title), ["Кобзар"])

        await relaunched.clear()
        let cleared = await relaunched.recent()
        XCTAssertTrue(cleared.isEmpty)
    }

    @MainActor
    func testCatalogFallsBackToRecentlyViewedWhenTheRequestNeverCompletes() async throws {
        let store = try makeRecentlyViewedStore()
        await store.record(try Self.recentWork(
            id: "11111111-1111-1111-1111-111111111111",
            title: "Кобзар"
        ))
        let model = CatalogViewModel(
            repository: FailingCatalogStub(failure: .transport),
            recentlyViewed: store
        )

        await model.load()

        guard case let .offlineFallback(recent) = model.state else {
            return XCTFail("Expected the offline fallback, got \(model.state)")
        }
        XCTAssertEqual(recent.map(\.title), ["Кобзар"])
    }

    @MainActor
    func testARemovedWorkReportsTheFailureRatherThanShowingStaleRows() async throws {
        let store = try makeRecentlyViewedStore()
        await store.record(try Self.recentWork(
            id: "11111111-1111-1111-1111-111111111111",
            title: "Кобзар"
        ))
        let model = CatalogViewModel(
            repository: FailingCatalogStub(failure: .notFound(APIErrorContext())),
            recentlyViewed: store
        )

        await model.load()

        // A 404 is a real answer about the catalog: showing previously opened
        // works here would imply they are still available.
        guard case .failed = model.state else {
            return XCTFail("Expected a failure, got \(model.state)")
        }
    }

    @MainActor
    func testOfflineFallbackIsSkippedWhenNothingWasEverOpened() async throws {
        let model = CatalogViewModel(
            repository: FailingCatalogStub(failure: .transport),
            recentlyViewed: try makeRecentlyViewedStore()
        )

        await model.load()

        guard case .failed = model.state else {
            return XCTFail("Expected a failure, got \(model.state)")
        }
    }

    private func makeRecentlyViewedStore(limit: Int = 20) throws -> RecentlyViewedStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeryndaTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return RecentlyViewedStore(directory: directory, limit: limit)
    }

    private static func recentWork(id: String, title: String) throws -> WorkSummary {
        let json = """
        {
          "id": "\(id)",
          "slug": "\(title.lowercased())",
          "title": "\(title)",
          "language": "uk",
          "authors": [{"id": "88888888-8888-8888-8888-888888888888", "display_name": "Автор"}],
          "editions_count": 1,
          "has_text_file": true,
          "cover_image_url": null,
          "cover_tone": "burgundy",
          "cover_variant": "frame",
          "cover_glyph": null
        }
        """
        return try JSONDecoder().decode(WorkSummary.self, from: Data(json.utf8))
    }

    func testPaletteMatchesTheNormativePrototype() {
        // Transcribed from web/public/ios-mockups/styles.css — :root and the
        // body[data-app-theme="dark"] override. The dark set had drifted in
        // five of seven tokens before this was pinned down.
        XCTAssertEqual(BeryndaPalette.paper.light, 0xF4F3ED)
        XCTAssertEqual(BeryndaPalette.paper.dark, 0x171312)
        XCTAssertEqual(BeryndaPalette.surface.light, 0xFFFDF8)
        XCTAssertEqual(BeryndaPalette.surface.dark, 0x211A18)
        XCTAssertEqual(BeryndaPalette.ink.light, 0x251F1D)
        XCTAssertEqual(BeryndaPalette.ink.dark, 0xF1EAE1)
        XCTAssertEqual(BeryndaPalette.mutedInk.light, 0x6B6660)
        XCTAssertEqual(BeryndaPalette.mutedInk.dark, 0xB4AAA0)
        XCTAssertEqual(BeryndaPalette.border.light, 0xD9D8CD)
        XCTAssertEqual(BeryndaPalette.border.dark, 0x453A35)
        XCTAssertEqual(BeryndaPalette.accent.light, 0x95271D)
        XCTAssertEqual(BeryndaPalette.accent.dark, 0xE77B49)
        XCTAssertEqual(BeryndaPalette.deepAccent.light, 0x60241E)
        XCTAssertEqual(BeryndaPalette.deepAccent.dark, 0xF1A37E)
    }

    func testBodyTextClearsAAAContrastInBothAppearances() {
        // Reading is the whole product, so body text is held to AAA rather
        // than the AA minimum.
        XCTAssertGreaterThanOrEqual(
            BeryndaPalette.contrastRatio(BeryndaPalette.ink.light, BeryndaPalette.paper.light),
            7
        )
        XCTAssertGreaterThanOrEqual(
            BeryndaPalette.contrastRatio(BeryndaPalette.ink.dark, BeryndaPalette.paper.dark),
            7
        )
        XCTAssertGreaterThanOrEqual(
            BeryndaPalette.contrastRatio(BeryndaPalette.ink.light, BeryndaPalette.surface.light),
            7
        )
        XCTAssertGreaterThanOrEqual(
            BeryndaPalette.contrastRatio(BeryndaPalette.ink.dark, BeryndaPalette.surface.dark),
            7
        )
    }

    func testMutedTextClearsAAContrastNormallyAndAAAUnderIncreasedContrast() {
        XCTAssertGreaterThanOrEqual(
            BeryndaPalette.contrastRatio(BeryndaPalette.mutedInk.light, BeryndaPalette.paper.light),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            BeryndaPalette.contrastRatio(BeryndaPalette.mutedInk.dark, BeryndaPalette.paper.dark),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            BeryndaPalette.contrastRatio(
                BeryndaPalette.mutedInk.lightIncreased,
                BeryndaPalette.paper.light
            ),
            7
        )
        XCTAssertGreaterThanOrEqual(
            BeryndaPalette.contrastRatio(
                BeryndaPalette.mutedInk.darkIncreased,
                BeryndaPalette.paper.dark
            ),
            7
        )
    }

    func testIncreasedContrastMakesBordersPerceivableBoundaries() {
        // The prototype's borders are decorative, about 1.3:1. Under Increase
        // Contrast they have to become real boundaries: WCAG 1.4.11 asks 3:1
        // of a UI component edge, on both surfaces a border can sit against.
        for background in [BeryndaPalette.paper.light, BeryndaPalette.surface.light] {
            XCTAssertGreaterThanOrEqual(
                BeryndaPalette.contrastRatio(BeryndaPalette.border.lightIncreased, background),
                3
            )
        }
        for background in [BeryndaPalette.paper.dark, BeryndaPalette.surface.dark] {
            XCTAssertGreaterThanOrEqual(
                BeryndaPalette.contrastRatio(BeryndaPalette.border.darkIncreased, background),
                3
            )
        }
    }

    func testIncreasedContrastNeverWeakensAToken() {
        let tokens = [
            BeryndaPalette.mutedInk,
            BeryndaPalette.border,
            BeryndaPalette.ink,
            BeryndaPalette.accent,
        ]
        for token in tokens {
            let light = BeryndaPalette.contrastRatio(token.light, BeryndaPalette.paper.light)
            let lightIncreased = BeryndaPalette.contrastRatio(
                token.lightIncreased,
                BeryndaPalette.paper.light
            )
            XCTAssertGreaterThanOrEqual(lightIncreased, light)

            let dark = BeryndaPalette.contrastRatio(token.dark, BeryndaPalette.paper.dark)
            let darkIncreased = BeryndaPalette.contrastRatio(
                token.darkIncreased,
                BeryndaPalette.paper.dark
            )
            XCTAssertGreaterThanOrEqual(darkIncreased, dark)
        }
    }

    func testEveryCoverToneIsLegibleAgainstItsOwnInk() {
        // Cover ink sits on the cover's own background, not on the app's, and
        // the glyph is large display type — 3:1 is the applicable floor.
        for tone in CoverTone.allCases {
            let pair = BeryndaColor.coverHexPair(for: tone)
            XCTAssertGreaterThanOrEqual(
                BeryndaPalette.contrastRatio(pair.ink, pair.background),
                3,
                "\(tone.rawValue) cover glyph is not legible on its background"
            )
        }
    }

    private func makeTemporaryPositionStore() throws -> LocalReadingPositionStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeryndaTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return LocalReadingPositionStore(directory: directory)
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

/// Reader repository that records how often a position save was attempted and
/// what the server answered. `recorded: nil` throws instead, standing in for a
/// transient network failure.
private actor ReaderPersistenceStub: ReaderRepository {
    static let fileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    private let recorded: Bool?
    private(set) var saveAttempts = 0

    init(recorded: Bool?) {
        self.recorded = recorded
    }

    func info(fileID: UUID) async throws -> ReaderInfo {
        try JSONDecoder().decode(ReaderInfo.self, from: Data(Self.readerInfoJSON.utf8))
    }

    func text(fileID: UUID) async throws -> TextReaderContent {
        try JSONDecoder().decode(
            TextReaderContent.self,
            from: Data(#"{"body":"Тестовий текст","page_offsets":[]}"#.utf8)
        )
    }

    func epubDocument(fileID: UUID) async throws -> Data { throw StubError.unsupported }
    func fullDocument(fileID: UUID) async throws -> Data { throw StubError.unsupported }
    func pagePDF(fileID: UUID, page: Int) async throws -> Data { throw StubError.unsupported }
    func pageImage(fileID: UUID, page: Int, width: Int) async throws -> Data {
        throw StubError.unsupported
    }

    func savePosition(
        fileID: UUID,
        positionType: String,
        positionValue: String,
        progressPercent: Int?,
        totalPages: Int?
    ) async throws -> Bool {
        saveAttempts += 1
        guard let recorded else { throw StubError.unsupported }
        return recorded
    }

    enum StubError: Error {
        case unsupported
    }

    static let readerInfoJSON = """
    {
      "file_id": "44444444-4444-4444-4444-444444444444",
      "edition_id": "33333333-3333-3333-3333-333333333333",
      "work_id": "11111111-1111-1111-1111-111111111111",
      "book": {"title": "Енеїда", "authors": ["Іван Котляревський"]},
      "mime_type": "text/plain",
      "rendering_mode": "txt",
      "page_delivery": "client_full",
      "pages_extracted": false,
      "split_pending": false,
      "split_failed": false,
      "has_toc": false,
      "total_pages": 10,
      "access_mode": "read_only",
      "download_allowed": false,
      "toc": [],
      "reading_position": null,
      "rights": {
        "can_read": true,
        "can_download_file": false,
        "can_download_page": false,
        "can_copy_text": true,
        "can_print": false,
        "can_share": true,
        "restriction_reason": null
      },
      "page_labels": []
    }
    """
}

/// Reader repository serving per-page PDFs and counting how often each page was
/// asked for, so prefetch and cache behaviour can be asserted exactly.
private actor PagedReaderStub: ReaderRepository {
    static let fileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    private let totalPages: Int
    private(set) var requestsPerPage: [Int: Int] = [:]

    init(totalPages: Int) {
        self.totalPages = totalPages
    }

    func info(fileID: UUID) async throws -> ReaderInfo {
        try JSONDecoder().decode(
            ReaderInfo.self,
            from: Data(Self.readerInfoJSON(totalPages: totalPages).utf8)
        )
    }

    func text(fileID: UUID) async throws -> TextReaderContent { throw StubError.unsupported }
    func epubDocument(fileID: UUID) async throws -> Data { throw StubError.unsupported }
    func fullDocument(fileID: UUID) async throws -> Data { throw StubError.unsupported }

    func pagePDF(fileID: UUID, page: Int) async throws -> Data {
        requestsPerPage[page, default: 0] += 1
        var data = Data("%PDF-".utf8)
        data.append(Data(repeating: 0x20, count: 64))
        return data
    }

    func pageImage(fileID: UUID, page: Int, width: Int) async throws -> Data {
        throw StubError.unsupported
    }

    func savePosition(
        fileID: UUID,
        positionType: String,
        positionValue: String,
        progressPercent: Int?,
        totalPages: Int?
    ) async throws -> Bool { true }

    enum StubError: Error {
        case unsupported
    }

    static func readerInfoJSON(totalPages: Int) -> String {
        """
        {
          "file_id": "44444444-4444-4444-4444-444444444444",
          "edition_id": "33333333-3333-3333-3333-333333333333",
          "work_id": "11111111-1111-1111-1111-111111111111",
          "book": {"title": "Кобзар", "authors": []},
          "mime_type": "application/pdf",
          "rendering_mode": "pdf",
          "page_delivery": "client_per_page",
          "pages_extracted": true,
          "split_pending": false,
          "split_failed": false,
          "has_toc": false,
          "total_pages": \(totalPages),
          "access_mode": "read_only",
          "download_allowed": false,
          "toc": [],
          "reading_position": null,
          "rights": {
            "can_read": true,
            "can_download_file": false,
            "can_download_page": true,
            "can_copy_text": true,
            "can_print": false,
            "can_share": true,
            "restriction_reason": null
          },
          "page_labels": []
        }
        """
    }
}

/// Reader repository whose rights and delivery mode are configurable, for
/// asserting that export and print stay deny-by-default.
private actor RightsReaderStub: ReaderRepository {
    private let pageDelivery: String
    private let canDownloadFile: Bool
    private let canPrint: Bool

    init(pageDelivery: String, canDownloadFile: Bool, canPrint: Bool) {
        self.pageDelivery = pageDelivery
        self.canDownloadFile = canDownloadFile
        self.canPrint = canPrint
    }

    func info(fileID: UUID) async throws -> ReaderInfo {
        let json = """
        {
          "file_id": "44444444-4444-4444-4444-444444444444",
          "edition_id": "33333333-3333-3333-3333-333333333333",
          "work_id": "11111111-1111-1111-1111-111111111111",
          "book": {"title": "Кобзар", "authors": []},
          "mime_type": "application/pdf",
          "rendering_mode": "pdf",
          "page_delivery": "\(pageDelivery)",
          "pages_extracted": true,
          "split_pending": false,
          "split_failed": false,
          "has_toc": false,
          "total_pages": 10,
          "access_mode": "read_only",
          "download_allowed": \(canDownloadFile),
          "toc": [],
          "reading_position": null,
          "rights": {
            "can_read": true,
            "can_download_file": \(canDownloadFile),
            "can_download_page": true,
            "can_copy_text": true,
            "can_print": \(canPrint),
            "can_share": true,
            "restriction_reason": null
          },
          "page_labels": []
        }
        """
        return try JSONDecoder().decode(ReaderInfo.self, from: Data(json.utf8))
    }

    func text(fileID: UUID) async throws -> TextReaderContent { throw StubError.unsupported }
    func epubDocument(fileID: UUID) async throws -> Data { throw StubError.unsupported }

    func fullDocument(fileID: UUID) async throws -> Data { Self.pdfBytes }
    func pagePDF(fileID: UUID, page: Int) async throws -> Data { Self.pdfBytes }
    func pageImage(fileID: UUID, page: Int, width: Int) async throws -> Data {
        Data([0xff, 0xd8, 0xff])
    }

    func savePosition(
        fileID: UUID,
        positionType: String,
        positionValue: String,
        progressPercent: Int?,
        totalPages: Int?
    ) async throws -> Bool { true }

    private static var pdfBytes: Data {
        var data = Data("%PDF-".utf8)
        data.append(Data(repeating: 0x20, count: 32))
        return data
    }

    enum StubError: Error {
        case unsupported
    }
}

/// Text reader whose body and page offsets are configurable, and which counts
/// how often the body was fetched so paging can be shown to be pure slicing.
private actor PagedTextStub: ReaderRepository {
    private let body: String
    private let pageOffsets: [Int]
    private(set) var textFetches = 0

    init(body: String, pageOffsets: [Int]) {
        self.body = body
        self.pageOffsets = pageOffsets
    }

    func info(fileID: UUID) async throws -> ReaderInfo {
        // A text file has no document page count of its own: any pagination
        // comes from the derivative's offsets.
        let json = """
        {
          "file_id": "44444444-4444-4444-4444-444444444444",
          "edition_id": "33333333-3333-3333-3333-333333333333",
          "work_id": "11111111-1111-1111-1111-111111111111",
          "book": {"title": "Енеїда", "authors": []},
          "mime_type": "text/plain",
          "rendering_mode": "txt",
          "page_delivery": "client_full",
          "pages_extracted": false,
          "split_pending": false,
          "split_failed": false,
          "has_toc": false,
          "total_pages": null,
          "access_mode": "read_only",
          "download_allowed": false,
          "toc": [],
          "reading_position": null,
          "rights": {
            "can_read": true,
            "can_download_file": false,
            "can_download_page": false,
            "can_copy_text": true,
            "can_print": false,
            "can_share": true,
            "restriction_reason": null
          },
          "page_labels": []
        }
        """
        return try JSONDecoder().decode(ReaderInfo.self, from: Data(json.utf8))
    }

    func text(fileID: UUID) async throws -> TextReaderContent {
        textFetches += 1
        let offsets = pageOffsets.map(String.init).joined(separator: ",")
        let escaped = body.replacingOccurrences(of: "\"", with: "\\\"")
        let json = #"{"body":"\#(escaped)","page_offsets":[\#(offsets)]}"#
        return try JSONDecoder().decode(TextReaderContent.self, from: Data(json.utf8))
    }

    func epubDocument(fileID: UUID) async throws -> Data { throw StubError.unsupported }
    func fullDocument(fileID: UUID) async throws -> Data { throw StubError.unsupported }
    func pagePDF(fileID: UUID, page: Int) async throws -> Data { throw StubError.unsupported }
    func pageImage(fileID: UUID, page: Int, width: Int) async throws -> Data {
        throw StubError.unsupported
    }

    func savePosition(
        fileID: UUID,
        positionType: String,
        positionValue: String,
        progressPercent: Int?,
        totalPages: Int?
    ) async throws -> Bool { true }

    enum StubError: Error {
        case unsupported
    }
}

/// Reader repository serving a publication, counting position saves so it can
/// be asserted that none are sent.
private actor PublicationReaderStub: ReaderRepository {
    private(set) var saveAttempts = 0

    func info(fileID: UUID) async throws -> ReaderInfo {
        let json = """
        {
          "file_id": "44444444-4444-4444-4444-444444444444",
          "edition_id": "33333333-3333-3333-3333-333333333333",
          "work_id": "11111111-1111-1111-1111-111111111111",
          "book": {"title": "Кобзар", "authors": []},
          "mime_type": "application/epub+zip",
          "file_size_bytes": 2048,
          "rendering_mode": "epub",
          "page_delivery": "client_full",
          "pages_extracted": false,
          "split_pending": false,
          "split_failed": false,
          "has_toc": false,
          "total_pages": null,
          "access_mode": "read_only",
          "download_allowed": false,
          "toc": [],
          "reading_position": null,
          "rights": {
            "can_read": true,
            "can_download_file": false,
            "can_download_page": false,
            "can_copy_text": true,
            "can_print": false,
            "can_share": true,
            "restriction_reason": null
          },
          "page_labels": []
        }
        """
        return try JSONDecoder().decode(ReaderInfo.self, from: Data(json.utf8))
    }

    func text(fileID: UUID) async throws -> TextReaderContent { throw StubError.unsupported }

    func epubDocument(fileID: UUID) async throws -> Data {
        var data = Data([0x50, 0x4b, 0x03, 0x04])
        data.append(Data(repeating: 0x00, count: 32))
        return data
    }

    func fullDocument(fileID: UUID) async throws -> Data { throw StubError.unsupported }
    func pagePDF(fileID: UUID, page: Int) async throws -> Data { throw StubError.unsupported }
    func pageImage(fileID: UUID, page: Int, width: Int) async throws -> Data {
        throw StubError.unsupported
    }

    func savePosition(
        fileID: UUID,
        positionType: String,
        positionValue: String,
        progressPercent: Int?,
        totalPages: Int?
    ) async throws -> Bool {
        saveAttempts += 1
        return true
    }

    enum StubError: Error {
        case unsupported
    }
}

/// Catalog repository that always fails with a chosen error, for asserting
/// which failures fall back to on-device history and which surface as errors.
private struct FailingCatalogStub: CatalogRepository {
    let failure: APIError

    func works(search: String?, page: Int) async throws -> PaginatedResponse<WorkSummary> {
        throw failure
    }

    func works(
        search: String?,
        page: Int,
        readableOnly: Bool,
        language: String?
    ) async throws -> PaginatedResponse<WorkSummary> {
        throw failure
    }

    func work(identifier: String) async throws -> WorkSummary { throw failure }
    func editions(workID: UUID) async throws -> [EditionSummary] { throw failure }
}
