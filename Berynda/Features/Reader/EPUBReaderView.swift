import Combine
import ReadiumNavigator
import ReadiumShared
import ReadiumStreamer
import SwiftUI
import UIKit
import WebKit

struct EPUBReaderView: View {
    @StateObject private var controller: EPUBReaderController

    init(
        payload: EPUBPayload,
        fileID: UUID,
        initialProgressPercent: Int?,
        allowsCopy: Bool,
        allowsShare: Bool,
        onRetry: @escaping @MainActor () -> Void
    ) {
        _controller = StateObject(
            wrappedValue: EPUBReaderController(
                payload: payload,
                fileID: fileID,
                initialProgressPercent: initialProgressPercent,
                allowsCopy: allowsCopy,
                allowsShare: allowsShare,
                onRetry: onRetry
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch controller.phase {
                case .loading:
                    ProgressView("Готуємо видання…")
                case let .ready(navigator):
                    EPUBNavigatorHost(navigator: navigator)
                case let .failed(message):
                    ContentUnavailableView {
                        Label("Не вдалося відкрити", systemImage: "book.closed")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Спробувати ще раз") { controller.retry() }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if case .ready = controller.phase, let progress = controller.progressPercent {
                HStack(spacing: 12) {
                    ProgressView(value: Double(progress), total: 100)
                    Text("\(progress)%")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(BeryndaColor.mutedInk)
                }
                .padding(.horizontal, 20)
                .frame(height: 40)
                .background(.bar)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Прочитано \(progress) відсотків")
            }
        }
        .task { await controller.load() }
        .onDisappear { controller.close() }
        .alert(
            "Дію не виконано",
            isPresented: Binding(
                get: { controller.notice != nil },
                set: { if !$0 { controller.notice = nil } }
            )
        ) {
            Button("Гаразд", role: .cancel) { controller.notice = nil }
        } message: {
            Text(controller.notice ?? "")
        }
    }
}

private struct EPUBNavigatorHost: UIViewControllerRepresentable {
    let navigator: EPUBNavigatorViewController

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController {
        navigator
    }

    func updateUIViewController(
        _ uiViewController: EPUBNavigatorViewController,
        context: Context
    ) {}
}

@MainActor
final class EPUBReaderController: NSObject, ObservableObject, EPUBNavigatorDelegate {
    enum Phase {
        case loading
        case ready(EPUBNavigatorViewController)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var progressPercent: Int?
    @Published var notice: String?

    private let payload: EPUBPayload
    private let fileID: UUID
    private let initialProgressPercent: Int?
    private let allowsCopy: Bool
    private let allowsShare: Bool
    private let onRetry: @MainActor () -> Void
    private var didStart = false
    private var temporaryURL: URL?
    private var publication: Publication?
    private var remoteContentBlocker: WKContentRuleList?

    private lazy var httpClient: HTTPClient = DefaultHTTPClient()
    private lazy var assetRetriever = AssetRetriever(httpClient: httpClient)
    private lazy var publicationOpener = PublicationOpener(
        parser: DefaultPublicationParser(
            httpClient: httpClient,
            assetRetriever: assetRetriever,
            pdfFactory: DefaultPDFDocumentFactory()
        )
    )

    init(
        payload: EPUBPayload,
        fileID: UUID,
        initialProgressPercent: Int?,
        allowsCopy: Bool,
        allowsShare: Bool,
        onRetry: @escaping @MainActor () -> Void
    ) {
        self.payload = payload
        self.fileID = fileID
        self.initialProgressPercent = initialProgressPercent
        self.allowsCopy = allowsCopy
        self.allowsShare = allowsShare
        self.onRetry = onRetry
        self.progressPercent = initialProgressPercent
    }

    func load() async {
        guard !didStart else { return }
        didStart = true
        phase = .loading

        do {
            remoteContentBlocker = try await Self.makeRemoteContentBlocker()
            guard let data = payload.data else { throw EPUBReaderFailure.invalidFile }
            let localURL = try await Self.writeProtectedTemporaryFile(data, fileID: fileID)
            payload.data = nil
            temporaryURL = localURL
            guard let readiumURL = FileURL(url: localURL) else {
                throw EPUBReaderFailure.invalidFile
            }

            let asset = try await assetRetriever.retrieve(url: readiumURL).get()
            let publication = try await publicationOpener.open(
                asset: asset,
                allowUserInteraction: false
            ).get()
            guard (publication.conforms(to: .epub) || publication.conforms(to: .divina)),
                  !publication.isRestricted
            else {
                throw EPUBReaderFailure.invalidFile
            }

            let initialLocation: Locator?
            if let percent = initialProgressPercent, percent > 0 {
                initialLocation = await publication.locate(
                    progression: min(max(Double(percent) / 100, 0), 1)
                )
            } else {
                initialLocation = nil
            }

            var editingActions = allowsCopy ? EditingAction.defaultActions : []
            if !allowsShare { editingActions.removeAll { $0 == .share } }

            let navigator = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: initialLocation,
                config: .init(editingActions: editingActions)
            )
            navigator.delegate = self
            self.publication = publication
            phase = .ready(navigator)
        } catch is CancellationError {
            close()
        } catch {
            cleanupTemporaryFile()
            phase = .failed(
                (error as? EPUBReaderFailure)?.localizedDescription
                    ?? EPUBReaderFailure.invalidFile.localizedDescription
            )
        }
    }

    func retry() {
        close()
        onRetry()
    }

    func close() {
        phase = .loading
        publication = nil
        cleanupTemporaryFile()
    }

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        guard let progression = locator.locations.totalProgression else { return }
        progressPercent = min(max(Int((progression * 100).rounded()), 0), 100)
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        notice = "Ця дія недоступна для цього видання."
    }

    func navigator(_ navigator: Navigator, presentExternalURL url: URL) {
        guard url.scheme?.lowercased() == "https" else {
            notice = "Посилання має непідтримувану адресу."
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    func navigator(
        _ navigator: Navigator,
        didFailToLoadResourceAt href: RelativeURL,
        withError error: ReadError
    ) {
        notice = "Не вдалося завантажити частину видання."
    }

    func navigator(
        _ navigator: EPUBNavigatorViewController,
        setupUserScripts userContentController: WKUserContentController
    ) {
        if let remoteContentBlocker {
            userContentController.add(remoteContentBlocker)
        }
    }

    private func cleanupTemporaryFile() {
        guard let temporaryURL else { return }
        try? FileManager.default.removeItem(at: temporaryURL)
        self.temporaryURL = nil
    }

    nonisolated private static func writeProtectedTemporaryFile(
        _ data: Data,
        fileID: UUID
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let manager = FileManager.default
            let directory = manager.temporaryDirectory
                .appendingPathComponent("org.berynda.ios", isDirectory: true)
                .appendingPathComponent("reader", isDirectory: true)
            try manager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )

            var fileURL = directory.appendingPathComponent(
                "\(fileID.uuidString.lowercased())-\(UUID().uuidString.lowercased()).epub",
                isDirectory: false
            )
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try fileURL.setResourceValues(values)
            return fileURL
        }.value
    }

    private static func makeRemoteContentBlocker() async throws -> WKContentRuleList {
        let rules = #"[{"trigger":{"url-filter":"^https?://","resource-type":["image","style-sheet","script","font","media","raw","popup"]},"action":{"type":"block"}}]"#
        return try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "org.berynda.reader.block-remote-content.v1",
                encodedContentRuleList: rules
            ) { ruleList, error in
                if let ruleList {
                    continuation.resume(returning: ruleList)
                } else {
                    continuation.resume(throwing: error ?? EPUBReaderFailure.contentRules)
                }
            }
        }
    }
}

private enum EPUBReaderFailure: LocalizedError {
    case invalidFile
    case contentRules

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            "Файл видання пошкоджений або має непідтримувану структуру."
        case .contentRules:
            "Не вдалося безпечно підготувати читач."
        }
    }
}
