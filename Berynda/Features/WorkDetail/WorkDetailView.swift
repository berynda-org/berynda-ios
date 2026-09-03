import BeryndaCore
import SwiftUI

struct WorkDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let work: WorkSummary
    @StateObject private var model: WorkDetailViewModel

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
        .task { await model.load() }
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
    }

    private var metadata: String {
        [edition.year.map(String.init), edition.publisherName, edition.publicationPlace]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
