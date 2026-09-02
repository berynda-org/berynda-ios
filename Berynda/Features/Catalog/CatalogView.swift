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
                ProgressView("Завантажуємо каталог…")
            case let .loaded(works) where works.isEmpty:
                BeryndaEmptyState(
                    title: "Нічого не знайдено",
                    message: "Спробуйте інший запит.",
                    systemImage: "text.magnifyingglass"
                )
            case let .loaded(works):
                WorkList(works: works)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Не вдалося завантажити", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Спробувати ще раз") { Task { await model.load() } }
                }
            }
        }
            .navigationTitle("Каталог")
            .searchable(text: $model.query, prompt: "Назва або автор")
            .onChange(of: model.query) { _, _ in model.searchChanged() }
            .task {
                if case .idle = model.state { await model.load() }
            }
    }
}

private struct WorkList: View {
    @EnvironmentObject private var environment: AppEnvironment
    let works: [WorkSummary]

    var body: some View {
        List(works) { work in
            NavigationLink {
                WorkDetailView(work: work, repository: environment.catalogRepository)
            } label: {
                WorkRow(work: work)
            }
            .accessibilityIdentifier("catalog.work.\(work.id)")
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BeryndaColor.paper)
    }
}

private struct WorkRow: View {
    let work: WorkSummary

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 5)
                .fill(BeryndaColor.deepAccent)
                .frame(width: 54, height: 78)
                .overlay {
                    Text(work.coverGlyph?.nilIfEmpty ?? String(work.title.prefix(1)))
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
