import BeryndaCore
import Combine
import Foundation

@MainActor
final class WorkDetailViewModel: ObservableObject {
    enum State {
        case loading
        case loaded([EditionSummary])
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    private let workID: UUID
    private let repository: any CatalogRepository

    init(workID: UUID, repository: any CatalogRepository) {
        self.workID = workID
        self.repository = repository
    }

    func load() async {
        state = .loading
        do {
            state = .loaded(try await repository.editions(workID: workID))
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
