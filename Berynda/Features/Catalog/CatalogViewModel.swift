import BeryndaCore
import Combine
import Foundation

@MainActor
final class CatalogViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loaded([WorkSummary])
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published var query = ""
    private let repository: any CatalogRepository
    private var searchTask: Task<Void, Never>?

    init(repository: any CatalogRepository) {
        self.repository = repository
    }

    deinit { searchTask?.cancel() }

    func load() async {
        state = .loading
        do {
            let page = try await repository.works(search: query.nilIfBlank, page: 1)
            state = .loaded(page.results)
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func searchChanged() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await load()
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
