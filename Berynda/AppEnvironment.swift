import BeryndaCore
import Combine
import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let catalogRepository: any CatalogRepository
    let readerRepository: any ReaderRepository
    let networkMonitor: NetworkMonitor
    @Published var selectedTab: RootTab = .catalog
    @Published var pendingRoute: AppRoute?

    init(
        catalogRepository: any CatalogRepository,
        readerRepository: any ReaderRepository,
        networkMonitor: NetworkMonitor? = nil
    ) {
        self.catalogRepository = catalogRepository
        self.readerRepository = readerRepository
        self.networkMonitor = networkMonitor ?? NetworkMonitor()
    }

    static func live(bundle: Bundle = .main) -> AppEnvironment {
        guard let raw = bundle.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
              let baseURL = URL(string: raw),
              baseURL.path.hasSuffix("/api/v1/")
        else {
            preconditionFailure("API_BASE_URL must be a fixed /api/v1/ URL supplied by build configuration")
        }
        let client = BeryndaAPIClient(baseURL: baseURL)
        return AppEnvironment(
            catalogRepository: LiveCatalogRepository(client: client),
            readerRepository: LiveReaderRepository(client: client)
        )
    }

    func open(_ url: URL) {
        guard let route = AppRoute(url: url) else { return }
        selectedTab = .catalog
        pendingRoute = route
    }
}

enum RootTab: Hashable {
    case catalog
    case library
    case profile
}
