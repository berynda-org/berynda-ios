import BeryndaCore
import Combine
import Foundation

@MainActor
final class CatalogViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loaded([WorkSummary], totalCount: Int)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var nextPageError: String?
    @Published var query = ""
    private let repository: any CatalogRepository
    private var searchTask: Task<Void, Never>?
    private var currentPage = 0
    private var hasNextPage = false
    private var loadGeneration = 0

    init(repository: any CatalogRepository) {
        self.repository = repository
    }

    deinit { searchTask?.cancel() }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let requestedQuery = query.nilIfBlank
        isLoadingNextPage = false
        nextPageError = nil
        state = .loading
        do {
            let page = try await repository.works(search: requestedQuery, page: 1)
            guard generation == loadGeneration, requestedQuery == query.nilIfBlank else { return }
            currentPage = 1
            hasNextPage = page.next != nil && page.results.count < page.count
            state = .loaded(page.results, totalCount: page.count)
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func loadNextPageIfNeeded(after work: WorkSummary) async {
        guard case let .loaded(works, totalCount) = state,
              work.id == works.last?.id,
              hasNextPage,
              !isLoadingNextPage
        else { return }

        let generation = loadGeneration
        let requestedQuery = query.nilIfBlank
        let requestedPage = currentPage + 1
        isLoadingNextPage = true
        nextPageError = nil
        defer {
            if generation == loadGeneration { isLoadingNextPage = false }
        }

        do {
            let page = try await repository.works(search: requestedQuery, page: requestedPage)
            guard generation == loadGeneration, requestedQuery == query.nilIfBlank else { return }
            let knownIDs = Set(works.map(\.id))
            let newWorks = page.results.filter { !knownIDs.contains($0.id) }
            let combined = works + newWorks
            currentPage = requestedPage
            hasNextPage = page.next != nil && !page.results.isEmpty && combined.count < page.count
            state = .loaded(combined, totalCount: max(totalCount, page.count))
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }
            nextPageError = error.localizedDescription
        }
    }

    func retryNextPage() async {
        guard case let .loaded(works, _) = state, let last = works.last else { return }
        await loadNextPageIfNeeded(after: last)
    }

    func searchChanged() {
        searchTask?.cancel()
        loadGeneration += 1
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
