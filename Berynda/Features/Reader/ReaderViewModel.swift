import BeryndaCore
import Combine
import Foundation

@MainActor
final class EPUBPayload {
    var data: Data?

    init(data: Data) {
        self.data = data
    }
}

@MainActor
final class ReaderViewModel: ObservableObject {
    enum Content {
        case text(String, isMarkdown: Bool)
        case pdf(Data, tracksDocumentPages: Bool)
        case image(Data)
        case epub(EPUBPayload)
    }

    enum Phase {
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var info: ReaderInfo?
    @Published private(set) var content: Content?
    @Published private(set) var pageIsLoading = false
    @Published var currentPage = 1

    let fileID: UUID
    private let initialPage: Int?
    private let repository: any ReaderRepository
    private let session: SessionController
    private let account: AccountViewModel
    private let localPositions: LocalReadingPositionStore
    private var pageTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    init(
        fileID: UUID,
        initialPage: Int? = nil,
        repository: any ReaderRepository,
        session: SessionController,
        account: AccountViewModel,
        localPositions: LocalReadingPositionStore
    ) {
        self.fileID = fileID
        self.initialPage = initialPage
        self.repository = repository
        self.session = session
        self.account = account
        self.localPositions = localPositions
    }

    deinit {
        pageTask?.cancel()
        saveTask?.cancel()
    }

    func load() async {
        phase = .loading
        do {
            let readerInfo = try await repository.info(fileID: fileID)
            guard readerInfo.rights.canRead else {
                throw ReaderFailure.restricted(
                    readerInfo.rights.restrictionReason ?? "Це видання зараз недоступне для читання."
                )
            }
            guard readerInfo.renderingMode != .djvu else {
                throw ReaderFailure.unsupported
            }

            info = readerInfo
            let local = await localPositions.position(for: fileID)
            currentPage = restoredPage(from: readerInfo, local: local)
            try await loadContent(for: readerInfo)
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func selectPage(_ page: Int) {
        guard let info else { return }
        let upperBound = max(info.totalPages ?? page, 1)
        let bounded = min(max(page, 1), upperBound)
        guard bounded != currentPage else { return }
        currentPage = bounded
        schedulePositionSave()

        guard info.renderingMode == .pdf, info.resource != .fullPDF else { return }
        pageTask?.cancel()
        pageTask = Task { [weak self] in
            await self?.reloadPage(page)
        }
    }

    var canGoBackward: Bool { currentPage > 1 && !pageIsLoading }

    var canGoForward: Bool {
        guard !pageIsLoading, let total = info?.totalPages else { return false }
        return currentPage < total
    }

    var contents: [ReaderContentsItem] {
        guard let info, info.renderingMode == .pdf else { return [] }
        return ReaderNavigation.contents(
            from: info.toc,
            workID: info.workID,
            totalPages: info.totalPages
        )
    }

    func pageLabel(for page: Int) -> String? {
        ReaderNavigation.pageLabel(for: page, in: info?.pageLabels ?? [])
    }

    func flushPosition() async {
        saveTask?.cancel()
        saveTask = nil
        await persistPosition()
    }

    private func loadContent(for info: ReaderInfo) async throws {
        switch info.resource {
        case let .structuredText(isMarkdown):
            let response = try await repository.text(fileID: fileID)
            content = .text(response.body, isMarkdown: isMarkdown)
        case .fullPDF, .pagePDF, .pageImage:
            content = try await pdfContent(info, page: currentPage)
        case .epub:
            guard (info.fileSizeBytes ?? 0) <= 100 * 1_024 * 1_024 else {
                throw APIError.responseTooLarge
            }
            content = .epub(
                EPUBPayload(data: try await repository.epubDocument(fileID: fileID))
            )
        case .unsupported:
            throw ReaderFailure.unsupported
        }
    }

    private func pdfContent(_ info: ReaderInfo, page: Int) async throws -> Content {
        switch info.resource {
        case .fullPDF:
            return .pdf(
                try await repository.fullDocument(fileID: fileID),
                tracksDocumentPages: true
            )
        case .pagePDF:
            return .pdf(
                try await repository.pagePDF(fileID: fileID, page: page),
                tracksDocumentPages: false
            )
        case .pageImage:
            return .image(
                try await repository.pageImage(fileID: fileID, page: page, width: 1_600)
            )
        case .structuredText, .epub, .unsupported:
            throw ReaderFailure.unsupported
        }
    }

    private func reloadPage(_ requestedPage: Int) async {
        guard let info else { return }
        pageIsLoading = true
        defer {
            if currentPage == requestedPage { pageIsLoading = false }
        }
        do {
            let nextContent = try await pdfContent(info, page: requestedPage)
            guard !Task.isCancelled, currentPage == requestedPage else { return }
            content = nextContent
        } catch is CancellationError {
            return
        } catch {
            guard currentPage == requestedPage else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func restoredPage(from info: ReaderInfo, local: LocalReadingPosition?) -> Int {
        if let initialPage {
            return min(max(initialPage, 1), max(info.totalPages ?? initialPage, 1))
        }
        let remotePage = info.readingPosition?.positionType == "page"
            ? info.readingPosition?.positionValue.flatMap(Int.init)
            : nil
        let page = remotePage ?? local?.page ?? 1
        return min(max(page, 1), max(info.totalPages ?? page, 1))
    }

    private func schedulePositionSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.persistPosition()
        }
    }

    private func persistPosition() async {
        guard let info, phase.isLoaded else { return }
        guard account.profile?.readingHistoryEnabled != false else {
            await localPositions.clearAll()
            return
        }
        let page = currentPage
        let total = info.totalPages
        await localPositions.save(page: page, totalPages: total, for: fileID)
        guard await session.state() == .authenticated else { return }
        let progress = total.map { min(max(Int((Double(page) / Double(max($0, 1)) * 100).rounded()), 0), 100) }
        _ = try? await repository.savePosition(
            fileID: fileID,
            positionType: "page",
            positionValue: String(page),
            progressPercent: progress,
            totalPages: total
        )
    }
}

private extension ReaderViewModel.Phase {
    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }
}

private enum ReaderFailure: LocalizedError {
    case restricted(String)
    case unsupported

    var errorDescription: String? {
        switch self {
        case let .restricted(reason): reason
        case .unsupported: "Цей матеріал не підтримується в мобільному читачі."
        }
    }
}
