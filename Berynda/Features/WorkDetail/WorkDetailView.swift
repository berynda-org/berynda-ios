import BeryndaCore
import SwiftUI

struct WorkDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let work: WorkSummary
    @StateObject private var model: WorkDetailViewModel
    @State private var saveMessage: String?

    init(work: WorkSummary, repository: any CatalogRepository) {
        self.work = work
        _model = StateObject(
            wrappedValue: WorkDetailViewModel(workID: work.id, repository: repository)
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: BeryndaSpacing.standard) {
                    BeryndaBookCover(
                        title: work.title,
                        imageURL: work.coverImageURL,
                        glyph: work.coverGlyph,
                        tone: work.coverTone,
                        width: 88,
                        height: 128
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text(work.title)
                            .font(.system(.largeTitle, design: .serif, weight: .bold))
                            .foregroundStyle(BeryndaColor.ink)
                        if let subtitle = work.subtitle {
                            Text(subtitle).font(.title3).foregroundStyle(BeryndaColor.mutedInk)
                        }
                        if !work.authors.isEmpty {
                            Text(work.authors.map(\.displayName).joined(separator: ", "))
                                .foregroundStyle(BeryndaColor.accent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let description = work.description, !description.isEmpty {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(BeryndaColor.ink)
                }

                BeryndaPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Бібліографічні відомості", systemImage: "text.book.closed")
                            .font(.headline)
                        detailRow("Мова", value: work.language?.uppercased())
                        detailRow("Перша публікація", value: work.firstPublishedYear.map(String.init))
                        detailRow("Обсяг", value: work.pages.map { "\($0) с." })
                        detailRow("Права", value: rightsLabel)
                    }
                }

                Text("Видання")
                    .font(.title2.bold())

                switch model.state {
                case .loading:
                    BeryndaLoadingState(message: "Завантажуємо видання…")
                        .frame(minHeight: 180)
                case let .loaded(editions) where editions.isEmpty:
                    BeryndaEmptyState(
                        title: "Видань ще немає",
                        message: "Для цього твору поки немає окремого видання.",
                        systemImage: "books.vertical"
                    )
                case let .loaded(editions):
                    ForEach(editions) { edition in
                        EditionRow(edition: edition) { fileID in
                            environment.presentReader(
                                fileID: fileID,
                                fallbackTitle: edition.displayTitle
                            )
                        }
                    }
                case let .failed(message):
                    BeryndaErrorState(
                        title: "Не вдалося завантажити видання",
                        message: message,
                        retry: { Task { await model.load() } }
                    )
                    .frame(minHeight: 240)
                }
            }
            .padding(20)
        }
        .background(BeryndaColor.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("До списку", systemImage: "bookmark") {
                    Task {
                        let result = await environment.library.quickAdd(workID: work.id)
                        saveMessage = result.message
                    }
                }
                .disabled(environment.library.isMutating)
                .accessibilityIdentifier("work.quick-add")
            }
        }
        .alert("Бібліотека", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("Гаразд", role: .cancel) {}
        } message: {
            Text(saveMessage ?? "")
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private func detailRow(_ label: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label, value: value)
                .font(.subheadline)
        }
    }

    private var rightsLabel: String? {
        switch work.rightsSummary {
        case "public_domain": "Суспільне надбання"
        case "open_license": "Відкрита ліцензія"
        case "permission": "Дозволено правовласником"
        case "copyrighted": "Захищено авторським правом"
        default: nil
        }
    }
}

extension LibraryViewModel.SaveResult {
    var message: String {
        switch self {
        case .saved: "Додано до бібліографічного списку."
        case .alreadySaved: "Цей твір уже є у вашому списку."
        case .signInRequired: "Увійдіть у профілі, щоб зберігати твори."
        case let .failed(message): message
        }
    }
}

private struct EditionRow: View {
    let edition: EditionSummary
    let onRead: (UUID) -> Void

    var body: some View {
        BeryndaPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text(edition.displayTitle)
                    .font(.headline)
                    .foregroundStyle(BeryndaColor.ink)
                Text(metadata)
                    .font(.subheadline)
                    .foregroundStyle(BeryndaColor.mutedInk)
                if let pageCount = edition.pageCount {
                    Text("\(pageCount) сторінок · \(edition.language.uppercased())")
                        .font(.caption)
                        .foregroundStyle(BeryndaColor.mutedInk)
                }

                if let fileID = edition.readableFileID, edition.canRead {
                    Button {
                        onRead(fileID)
                    } label: {
                        Label("Читати видання", systemImage: "book.pages")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("edition.read.\(edition.id)")
                } else {
                    Label(
                        edition.restrictionReason ?? "Файл для читання недоступний",
                        systemImage: "lock"
                    )
                    .font(.footnote)
                    .foregroundStyle(BeryndaColor.mutedInk)
                }
            }
        }
        .accessibilityIdentifier("work.edition.\(edition.id)")
    }

    private var metadata: String {
        [edition.year.map(String.init), edition.publisherName, edition.publicationPlace]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
