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
    private var pageTask: Task<Void, Never>?

    init(fileID: UUID, initialPage: Int? = nil, repository: any ReaderRepository) {
        self.fileID = fileID
        self.initialPage = initialPage
        self.repository = repository
    }

    deinit { pageTask?.cancel() }

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
            currentPage = restoredPage(from: readerInfo)
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

    private func restoredPage(from info: ReaderInfo) -> Int {
        if let initialPage {
            return min(max(initialPage, 1), max(info.totalPages ?? initialPage, 1))
        }
        guard info.readingPosition?.positionType == "page",
              let raw = info.readingPosition?.positionValue,
              let page = Int(raw)
        else { return 1 }
        return min(max(page, 1), max(info.totalPages ?? page, 1))
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
