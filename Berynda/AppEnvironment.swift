import BeryndaCore
import Combine
import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let catalogRepository: any CatalogRepository
    let readerRepository: any ReaderRepository
    let networkMonitor: NetworkMonitor
    let session: SessionController
    @Published var selectedTab: RootTab = .catalog
    @Published var pendingRoute: AppRoute?
    @Published var catalogPath: [CatalogDestination] = []
    @Published var presentedReader: ReaderPresentation?

    init(
        catalogRepository: any CatalogRepository,
        readerRepository: any ReaderRepository,
        session: SessionController,
        networkMonitor: NetworkMonitor? = nil
    ) {
        self.catalogRepository = catalogRepository
        self.readerRepository = readerRepository
        self.session = session
        self.networkMonitor = networkMonitor ?? NetworkMonitor()
    }

    static func live(baseURL: URL = AppConfiguration.apiBaseURL) -> AppEnvironment {
        precondition(
            baseURL.scheme == "https" && baseURL.absoluteString.hasSuffix("/api/v1/"),
            "The production API URL must use HTTPS and end in /api/v1/."
        )
        let session = SessionController(
            tokenStore: KeychainTokenStore(),
            authentication: LiveAuthenticationService(baseURL: baseURL)
        )
        let client = BeryndaAPIClient(
            baseURL: baseURL,
            authorizationSession: session
        )
        return AppEnvironment(
            catalogRepository: LiveCatalogRepository(client: client),
            readerRepository: LiveReaderRepository(client: client),
            session: session
        )
    }

    func open(_ url: URL) {
        guard let route = AppRoute(url: url) else { return }
        selectedTab = .catalog
        pendingRoute = route
    }

    func consumePendingRoute() {
        guard let route = pendingRoute else { return }
        pendingRoute = nil
        selectedTab = .catalog
        switch route {
        case let .work(slug):
            presentedReader = nil
            catalogPath = [.linkedWork(identifier: slug)]
        case let .reader(fileID, page):
            presentedReader = ReaderPresentation(
                fileID: fileID,
                fallbackTitle: "Берында",
                initialPage: page
            )
        }
    }

    func presentReader(fileID: UUID, fallbackTitle: String, initialPage: Int? = nil) {
        presentedReader = ReaderPresentation(
            fileID: fileID,
            fallbackTitle: fallbackTitle,
            initialPage: initialPage
        )
    }
}

enum CatalogDestination: Hashable {
    case work(WorkSummary)
    case linkedWork(identifier: String)
}

struct ReaderPresentation: Identifiable, Equatable {
    let id = UUID()
    let fileID: UUID
    let fallbackTitle: String
    let initialPage: Int?
}

enum RootTab: Hashable {
    case catalog
    case library
    case profile
}
