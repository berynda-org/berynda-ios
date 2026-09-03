import BeryndaCore
import SwiftUI

struct CatalogView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        CatalogLoadedView(repository: environment.catalogRepository)
    }
}

private struct CatalogLoadedView: View {
    @StateObject private var model: CatalogViewModel

    init(repository: any CatalogRepository) {
        _model = StateObject(wrappedValue: CatalogViewModel(repository: repository))
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                BeryndaLoadingState(message: "Завантажуємо каталог…")
            case let .loaded(works, _) where works.isEmpty:
                BeryndaEmptyState(
                    title: "Нічого не знайдено",
                    message: model.query.isEmpty
                        ? "У каталозі поки немає доступних творів."
                        : "Спробуйте скоротити або змінити запит.",
                    systemImage: "text.magnifyingglass"
                )
            case let .loaded(works, totalCount):
                WorkList(works: works, totalCount: totalCount, model: model)
            case let .failed(message):
                BeryndaErrorState(
                    title: "Не вдалося завантажити",
                    message: message,
                    retry: { Task { await model.load() } }
                )
            }
        }
            .background(BeryndaColor.paper)
            .navigationTitle("Каталог")
            .searchable(text: $model.query, prompt: "Назва або автор")
            .onChange(of: model.query) { _, _ in model.searchChanged() }
            .task {
                if case .idle = model.state { await model.load() }
            }
    }
}

private struct WorkList: View {
    let works: [WorkSummary]
    let totalCount: Int
    @ObservedObject var model: CatalogViewModel

    var body: some View {
        List {
            Section {
                ForEach(works) { work in
                    NavigationLink(value: CatalogDestination.work(work)) {
                        WorkRow(work: work)
                    }
                    .accessibilityIdentifier("catalog.work.\(work.id)")
                    .task { await model.loadNextPageIfNeeded(after: work) }
                }
            } footer: {
                paginationFooter
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BeryndaColor.paper)
        .refreshable { await model.load() }
        .accessibilityLabel("Каталог, показано \(works.count) із \(totalCount)")
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if model.isLoadingNextPage {
            HStack {
                Spacer()
                ProgressView("Завантажуємо ще…")
                Spacer()
            }
            .padding(.vertical, BeryndaSpacing.standard)
        } else if let message = model.nextPageError {
            VStack(spacing: BeryndaSpacing.compact) {
                Text("Не вдалося завантажити наступні твори")
                    .font(.footnote.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(BeryndaColor.mutedInk)
                    .multilineTextAlignment(.center)
                Button("Повторити") { Task { await model.retryNextPage() } }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BeryndaSpacing.standard)
        } else if works.count < totalCount {
            Text("Показано \(works.count) із \(totalCount)")
                .font(.caption)
                .foregroundStyle(BeryndaColor.mutedInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, BeryndaSpacing.compact)
        }
    }
}

private struct WorkRow: View {
    let work: WorkSummary

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BeryndaBookCover(
                title: work.title,
                glyph: work.coverGlyph,
                tone: work.coverTone
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(work.title)
                    .font(.headline)
                    .foregroundStyle(BeryndaColor.ink)
                if !work.authors.isEmpty {
                    Text(work.authors.map(\.displayName).joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(BeryndaColor.mutedInk)
                }
                Text(editionsLabel)
                    .font(.caption)
                    .foregroundStyle(BeryndaColor.mutedInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private var editionsLabel: String {
        switch work.editionsCount {
        case 0: "Бібліографічний запис"
        case 1: "1 видання"
        default: "\(work.editionsCount) видань"
        }
    }
}
