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
        .sheet(isPresented: $showsContents) {
            PublicationContentsSheet(entries: controller.tableOfContents) { entry in
                showsContents = false
                Task { await controller.go(to: entry) }
            }
        }
        .sheet(isPresented: $showsAppearance) {
            PublicationAppearanceSheet(fontSizeScale: $controller.fontSizeScale)
        }
    }
}

private struct PublicationContentsSheet: View {
    let entries: [PublicationTOCEntry]
    let onSelect: (PublicationTOCEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                Button {
                    onSelect(entry)
                } label: {
                    Text(entry.title)
                        .font(entry.level == 0 ? .body.weight(.medium) : .body)
                        .foregroundStyle(BeryndaColor.ink)
                        // Nesting is shown as indentation rather than as
                        // collapsible groups: a reader looking for a chapter
                        // should not have to expand anything first.
                        .padding(.leading, CGFloat(entry.level) * 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("publication.toc.\(entry.id)")
            }
            .listStyle(.plain)
            .navigationTitle("Зміст")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

private struct PublicationAppearanceSheet: View {
    @Binding var fontSizeScale: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Розмір тексту") {
                    Slider(value: $fontSizeScale, in: 0.7...2.0, step: 0.1) {
                        Text("Розмір тексту")
                    }
                    .accessibilityValue("\(Int((fontSizeScale * 100).rounded())) відсотків")
                    .accessibilityIdentifier("publication.font-size")
                    Button("Скинути") { fontSizeScale = 1.0 }
                }
            }
            .navigationTitle("Вигляд")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
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

/// One row of a publication's table of contents, flattened for display.
struct PublicationTOCEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let level: Int
    let link: Link

    static func == (lhs: PublicationTOCEntry, rhs: PublicationTOCEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
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
    /// The publication's own table of contents, empty when it declares none.
    @Published private(set) var tableOfContents: [PublicationTOCEntry] = []
    /// Persisted so a reader sets publication type size once, not per book.
    /// Written straight to `UserDefaults` rather than through `@AppStorage`,
    /// which does not drive `objectWillChange` outside a `View`.
    @Published var fontSizeScale: Double {
        didSet {
            UserDefaults.standard.set(fontSizeScale, forKey: Self.fontSizeKey)
            applyPreferences()
        }
    }

    static let fontSizeKey = "reader.publication.fontSize"

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
        let stored = UserDefaults.standard.double(forKey: Self.fontSizeKey)
        // `double(forKey:)` answers 0 for a key that was never written.
        self.fontSizeScale = stored > 0 ? stored : 1.0
    }

    func load() async {
        guard !didStart else { return }
        didStart = true
        phase = .loading

        do {
            remoteContentBlocker = try await Self.makeRemoteContentBlocker()
            guard let data = payload.data else { throw EPUBReaderFailure.invalidFile }
            let localURL = try await ProtectedTemporaryFile.write(
                data,
                fileID: fileID,
                pathExtension: "epub"
            )
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

            await loadTableOfContents(from: publication)

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
            // The stored type size has to reach a navigator that now exists.
            applyPreferences()
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

    private func loadTableOfContents(from publication: Publication) async {
        // A publication that declares no TOC is normal, not an error: the
        // contents button simply is not offered.
        guard let links = try? await publication.tableOfContents().get() else { return }
        tableOfContents = Self.flatten(links)
    }

    /// Readium nests TOC links; the sheet shows one list, so depth becomes an
    /// indent level rather than a hierarchy the reader has to expand.
    static func flatten(_ links: [Link], level: Int = 0) -> [PublicationTOCEntry] {
        links.flatMap { link -> [PublicationTOCEntry] in
            let title = link.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let entry = PublicationTOCEntry(
                id: "\(level)-\(link.href)",
                title: (title?.isEmpty == false ? title : nil) ?? link.href,
                level: level,
                link: link
            )
            return [entry] + flatten(link.children, level: level + 1)
        }
    }

    func go(to entry: PublicationTOCEntry) async {
        guard case let .ready(navigator) = phase else { return }
        let moved = await navigator.go(to: entry.link)
        if !moved {
            notice = "Не вдалося відкрити цей розділ."
        }
    }

    func applyPreferences() {
        guard case let .ready(navigator) = phase else { return }
        navigator.submitPreferences(EPUBPreferences(fontSize: fontSizeScale))
    }

    private func cleanupTemporaryFile() {
        ProtectedTemporaryFile.remove(temporaryURL)
        temporaryURL = nil
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
