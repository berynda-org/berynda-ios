import BeryndaCore
import PDFKit
import SwiftUI
import UIKit

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ReaderViewModel
    @State private var showsContents = false
    @State private var showsAppearance = false
    @State private var draftPage = 1.0
    @State private var isScrubbing = false
    @State private var textScale: CGFloat = 1
    @State private var lineSpacingScale: CGFloat = 1
    private let fallbackTitle: String

    init(fileID: UUID, fallbackTitle: String, repository: any ReaderRepository) {
        self.fallbackTitle = fallbackTitle
        _model = StateObject(wrappedValue: ReaderViewModel(fileID: fileID, repository: repository))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .loading:
                    ProgressView("Відкриваємо видання…")
                case let .failed(message):
                    ContentUnavailableView {
                        Label("Не вдалося відкрити", systemImage: "book.closed")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Спробувати ще раз") { Task { await model.load() } }
                    }
                case .loaded:
                    readerContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BeryndaColor.paper)
            .navigationTitle(model.info?.book.title ?? fallbackTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрити", systemImage: "xmark") { dismiss() }
                }
                if !model.contents.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Зміст", systemImage: "list.bullet.indent") {
                            showsContents = true
                        }
                        .accessibilityIdentifier("reader.contents")
                    }
                }
                if isTextReader {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Вигляд тексту", systemImage: "textformat.size") {
                            showsAppearance = true
                        }
                        .accessibilityIdentifier("reader.appearance")
                    }
                }
                if model.info?.rights.canShare == true {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: shareURL) {
                            Label("Поділитися", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .task { await model.load() }
        .sheet(isPresented: $showsContents) {
            ReaderContentsSheet(
                items: model.contents,
                currentPage: model.currentPage
            ) { page in
                model.selectPage(page)
                draftPage = Double(page)
                showsContents = false
            }
        }
        .sheet(isPresented: $showsAppearance) {
            ReaderAppearanceSheet(
                textScale: $textScale,
                lineSpacingScale: $lineSpacingScale
            )
        }
        .onChange(of: model.currentPage) { _, page in
            guard !isScrubbing else { return }
            draftPage = Double(page)
        }
        .accessibilityIdentifier("reader.\(model.fileID)")
    }

    @ViewBuilder
    private var readerContent: some View {
        VStack(spacing: 0) {
            Group {
                switch model.content {
                case let .text(body, isMarkdown):
                    TextReaderView(
                        content: body,
                        isMarkdown: isMarkdown,
                        allowsSelection: model.info?.rights.canCopyText == true,
                        textScale: textScale,
                        lineSpacingScale: lineSpacingScale
                    )
                case let .pdf(data, tracksDocumentPages):
                    PDFReaderView(
                        data: data,
                        currentPage: $model.currentPage,
                        tracksDocumentPages: tracksDocumentPages
                    )
                case let .image(data):
                    ServerPageImage(data: data)
                case let .epub(payload):
                    EPUBReaderView(
                        payload: payload,
                        fileID: model.fileID,
                        initialProgressPercent: model.info?.readingPosition?.progressPercent,
                        allowsCopy: model.info?.rights.canCopyText == true,
                        allowsShare: model.info?.rights.canShare == true,
                        onRetry: { Task { await model.load() } }
                    )
                case nil:
                    ProgressView()
                }
            }

            if showsPageControls {
                pageControls
            }
        }
    }

    private var showsPageControls: Bool {
        guard let info = model.info else { return false }
        return info.renderingMode == .pdf && (info.totalPages ?? 0) > 1
    }

    private var isTextReader: Bool {
        guard let mode = model.info?.renderingMode else { return false }
        return mode == .text || mode == .markdown
    }

    private var pageControls: some View {
        VStack(spacing: 5) {
            Slider(
                value: $draftPage,
                in: 1...Double(max(model.info?.totalPages ?? 1, 1)),
                step: 1
            ) { editing in
                isScrubbing = editing
                if !editing {
                    model.selectPage(Int(draftPage.rounded()))
                }
            }
            .disabled(model.pageIsLoading)
            .accessibilityLabel("Перейти до сторінки")
            .accessibilityValue(pageLabel(for: displayedPage))
            .accessibilityIdentifier("reader.page-slider")

            HStack(spacing: 18) {
                Button("Попередня", systemImage: "chevron.left") {
                    model.selectPage(model.currentPage - 1)
                }
                .labelStyle(.iconOnly)
                .disabled(!model.canGoBackward)
                .accessibilityIdentifier("reader.previous-page")

                if model.pageIsLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text(pageLabel(for: displayedPage))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(BeryndaColor.mutedInk)
                }

                Button("Наступна", systemImage: "chevron.right") {
                    model.selectPage(model.currentPage + 1)
                }
                .labelStyle(.iconOnly)
                .disabled(!model.canGoForward)
                .accessibilityIdentifier("reader.next-page")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var displayedPage: Int {
        isScrubbing ? Int(draftPage.rounded()) : model.currentPage
    }

    private func pageLabel(for page: Int) -> String {
        let prefix = model.pageLabel(for: page).map { "\($0) · " } ?? ""
        guard let total = model.info?.totalPages else { return "\(prefix)с. \(page)" }
        return "\(prefix)с. \(page) з \(total)"
    }

    private var shareURL: URL {
        URL(string: "https://berynda.org/read/\(model.fileID.uuidString.lowercased())")!
    }
}

private struct ReaderAppearanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var textScale: CGFloat
    @Binding var lineSpacingScale: CGFloat

    var body: some View {
        NavigationStack {
            Form {
                Section("Розмір тексту") {
                    Slider(value: $textScale, in: 0.85...1.4, step: 0.05) {
                        Text("Розмір тексту")
                    } minimumValueLabel: {
                        Image(systemName: "textformat.size.smaller")
                    } maximumValueLabel: {
                        Image(systemName: "textformat.size.larger")
                    }
                    .accessibilityValue("\(Int((textScale * 100).rounded())) відсотків")
                }

                Section("Міжрядковий інтервал") {
                    Slider(value: $lineSpacingScale, in: 0.8...1.8, step: 0.1)
                        .accessibilityLabel("Міжрядковий інтервал")
                        .accessibilityValue("\(Int((lineSpacingScale * 100).rounded())) відсотків")
                }

                Button("Відновити стандартний вигляд") {
                    textScale = 1
                    lineSpacingScale = 1
                }
            }
            .navigationTitle("Вигляд тексту")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct ReaderContentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let items: [ReaderContentsItem]
    let currentPage: Int
    let onSelect: (Int) -> Void

    var body: some View {
        NavigationStack {
            List(items) { item in
                Button {
                    onSelect(item.page)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(item.title)
                            .foregroundStyle(BeryndaColor.ink)
                            .padding(.leading, CGFloat(item.depth) * 16)
                        Spacer(minLength: 12)
                        Text("\(item.page)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(BeryndaColor.mutedInk)
                        if item.page == currentPage {
                            Image(systemName: "checkmark")
                                .foregroundStyle(BeryndaColor.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.title), сторінка \(item.page)")
            }
            .navigationTitle("Зміст")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct TextReaderView: View {
    let content: String
    let isMarkdown: Bool
    let allowsSelection: Bool
    let textScale: CGFloat
    let lineSpacingScale: CGFloat
    @ScaledMetric(relativeTo: .body) private var baseFontSize: CGFloat = 19
    @ScaledMetric(relativeTo: .body) private var baseLineSpacing: CGFloat = 7

    var body: some View {
        ScrollView {
            Group {
                if allowsSelection {
                    renderedText.textSelection(.enabled)
                } else {
                    renderedText
                }
            }
            .font(.system(size: baseFontSize * textScale, weight: .regular, design: .serif))
            .lineSpacing(baseLineSpacing * lineSpacingScale)
            .foregroundStyle(BeryndaColor.ink)
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
    }

    private var renderedText: Text {
        guard isMarkdown,
              let attributed = try? AttributedString(
                markdown: content,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
              )
        else { return Text(content) }
        return Text(attributed)
    }
}

private struct PDFReaderView: UIViewRepresentable {
    let data: Data
    @Binding var currentPage: Int
    let tracksDocumentPages: Bool

    func makeCoordinator() -> Coordinator { Coordinator(currentPage: $currentPage) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = .clear
        view.displayDirection = .vertical
        view.displayMode = .singlePageContinuous
        view.usePageViewController(true, withViewOptions: nil)
        context.coordinator.observe(view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if context.coordinator.loadedData != data {
            context.coordinator.loadedData = data
            view.document = PDFDocument(data: data)
        }
        context.coordinator.tracksDocumentPages = tracksDocumentPages
        guard tracksDocumentPages,
              let document = view.document,
              currentPage > 0,
              currentPage <= document.pageCount,
              let target = document.page(at: currentPage - 1)
        else { return }
        if let visible = view.currentPage, document.index(for: visible) == currentPage - 1 { return }
        view.go(to: target)
    }

    final class Coordinator: NSObject {
        var loadedData: Data?
        var tracksDocumentPages = false
        private var currentPage: Binding<Int>
        private var observer: NSObjectProtocol?

        init(currentPage: Binding<Int>) {
            self.currentPage = currentPage
        }

        func observe(_ view: PDFView) {
            observer = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged,
                object: view,
                queue: .main
            ) { [weak self, weak view] _ in
                guard let self, self.tracksDocumentPages,
                      let view, let document = view.document, let page = view.currentPage
                else { return }
                self.currentPage.wrappedValue = document.index(for: page) + 1
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

private struct ServerPageImage: View {
    let data: Data
    @State private var scale: CGFloat = 1
    @GestureState private var gestureScale: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                if let image = UIImage(data: data) {
                    let effectiveScale = min(max(scale * gestureScale, 1), 4)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: geometry.size.width * effectiveScale,
                            height: geometry.size.height * effectiveScale
                        )
                        .gesture(
                            MagnifyGesture()
                                .updating($gestureScale) { value, state, _ in
                                    state = value.magnification
                                }
                                .onEnded { value in
                                    scale = min(max(scale * value.magnification, 1), 4)
                                }
                        )
                        .onTapGesture(count: 2) { scale = scale > 1 ? 1 : 2 }
                } else {
                    ContentUnavailableView("Сторінку пошкоджено", systemImage: "exclamationmark.triangle")
                }
            }
        }
    }
}
