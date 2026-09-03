import BeryndaCore
import Combine
import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let catalogRepository: any CatalogRepository
    let readerRepository: any ReaderRepository
    let networkMonitor: NetworkMonitor
    let session: SessionController
    let account: AccountViewModel
    let library: LibraryViewModel
    let localReadingPositions: LocalReadingPositionStore
    @Published var selectedTab: RootTab = .catalog
    @Published var pendingRoute: AppRoute?
    @Published var catalogPath: [CatalogDestination] = []
    @Published var tabletCatalogSelection: CatalogDestination?
    @Published var presentedReader: ReaderPresentation?

    init(
        catalogRepository: any CatalogRepository,
        readerRepository: any ReaderRepository,
        session: SessionController,
        authentication: any AuthenticationServing,
        accountRepository: any AccountRepository,
        libraryRepository: any LibraryRepository,
        networkMonitor: NetworkMonitor? = nil
    ) {
        self.catalogRepository = catalogRepository
        self.readerRepository = readerRepository
        self.session = session
        let localReadingPositions = LocalReadingPositionStore()
        self.localReadingPositions = localReadingPositions
        let account = AccountViewModel(
            session: session,
            authentication: authentication,
            repository: accountRepository,
            localPositions: localReadingPositions
        )
        self.account = account
        self.library = LibraryViewModel(
            repository: libraryRepository,
            account: account
        )
        self.networkMonitor = networkMonitor ?? NetworkMonitor()
    }

    static func live(baseURL: URL = AppConfiguration.apiBaseURL) -> AppEnvironment {
        precondition(
            baseURL.scheme == "https" && baseURL.absoluteString.hasSuffix("/api/v1/"),
            "The production API URL must use HTTPS and end in /api/v1/."
        )
        let authentication = LiveAuthenticationService(baseURL: baseURL)
        let session = SessionController(
            tokenStore: KeychainTokenStore(),
            authentication: authentication
        )
        let client = BeryndaAPIClient(
            baseURL: baseURL,
            authorizationSession: session
        )
        return AppEnvironment(
            catalogRepository: LiveCatalogRepository(client: client),
            readerRepository: LiveReaderRepository(client: client),
            session: session,
            authentication: authentication,
            accountRepository: LiveAccountRepository(client: client),
            libraryRepository: LiveLibraryRepository(client: client)
        )
    }

    #if DEBUG
    static func uiTesting() -> AppEnvironment {
        let repository = UITestRepository()
        let authentication = UITestAuthenticationService()
        let session = SessionController(
            tokenStore: UITestTokenStore(),
            authentication: authentication
        )
        return AppEnvironment(
            catalogRepository: repository,
            readerRepository: repository,
            session: session,
            authentication: authentication,
            accountRepository: UITestAccountRepository(),
            libraryRepository: repository
        )
    }
    #endif

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
            tabletCatalogSelection = .linkedWork(identifier: slug)
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
