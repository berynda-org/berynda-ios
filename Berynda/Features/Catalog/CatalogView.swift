import BeryndaCore
import SwiftUI

struct CatalogView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        CatalogLoadedView(repository: environment.catalogRepository)
    }
}

private struct CatalogLoadedView: View {
    @EnvironmentObject private var environment: AppEnvironment
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
                WorkList(
                    works: works,
                    totalCount: totalCount,
                    collections: model.query.isEmpty ? environment.library.publicCollections : [],
                    model: model
                )
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Фільтри", systemImage: "line.3.horizontal.decrease.circle") {
                        Toggle("Лише доступні для читання", isOn: $model.readableOnly)
                        Picker("Мова", selection: $model.languageFilter) {
                            Text("Усі мови").tag(String?.none)
                            Text("Українська").tag(String?.some("uk"))
                            Text("English").tag(String?.some("en"))
                        }
                    }
                }
            }
            .accessibilityIdentifier("catalog_screen")
            .onChange(of: model.query) { _, _ in model.searchChanged() }
            .onChange(of: model.readableOnly) { _, _ in model.searchChanged() }
            .onChange(of: model.languageFilter) { _, _ in model.searchChanged() }
            .task {
                if case .idle = model.state { await model.load() }
                if environment.library.publicCollections.isEmpty {
                    await environment.library.loadPublicCollections()
                }
            }
    }
}

struct TabletCatalogColumn: View {
    @StateObject private var model: CatalogViewModel
    @Binding var selection: CatalogDestination?

    init(repository: any CatalogRepository, selection: Binding<CatalogDestination?>) {
        _model = StateObject(wrappedValue: CatalogViewModel(repository: repository))
        _selection = selection
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                BeryndaLoadingState(message: "Завантажуємо каталог…")
            case let .loaded(works, _) where works.isEmpty:
                BeryndaEmptyState(
                    title: "Нічого не знайдено",
                    message: "Спробуйте змінити запит або фільтри.",
                    systemImage: "text.magnifyingglass"
                )
            case let .loaded(works, _):
                List(works, selection: $selection) { work in
                    WorkRow(work: work)
                        .tag(CatalogDestination.work(work))
                        .task { await model.loadNextPageIfNeeded(after: work) }
                }
                .listStyle(.plain)
                .refreshable { await model.load() }
            case let .failed(message):
                BeryndaErrorState(
                    title: "Не вдалося завантажити",
                    message: message,
                    retry: { Task { await model.load() } }
                )
            }
        }
        .navigationTitle("Каталог")
        .searchable(text: $model.query, prompt: "Назва або автор")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Фільтри", systemImage: "line.3.horizontal.decrease.circle") {
                    Toggle("Лише доступні для читання", isOn: $model.readableOnly)
                    Picker("Мова", selection: $model.languageFilter) {
                        Text("Усі мови").tag(String?.none)
                        Text("Українська").tag(String?.some("uk"))
                        Text("English").tag(String?.some("en"))
                    }
                }
            }
        }
        .onChange(of: model.query) { _, _ in model.searchChanged() }
        .onChange(of: model.readableOnly) { _, _ in model.searchChanged() }
        .onChange(of: model.languageFilter) { _, _ in model.searchChanged() }
        .task { if case .idle = model.state { await model.load() } }
    }
}

private struct WorkList: View {
    let works: [WorkSummary]
    let totalCount: Int
    let collections: [PublicCollectionSummary]
    @ObservedObject var model: CatalogViewModel

    var body: some View {
        List {
            if !collections.isEmpty {
                Section("Вибрані колекції") {
                    ForEach(collections.filter(\.isFeatured)) { collection in
                        CollectionShelf(collection: collection)
                    }
                }
            }
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

private struct CollectionShelf: View {
    @EnvironmentObject private var environment: AppEnvironment
    let collection: PublicCollectionSummary
    @State private var saveMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(collection.name).font(.headline)
                    if !collection.description.isEmpty {
                        Text(collection.description)
                            .font(.caption)
                            .foregroundStyle(BeryndaColor.mutedInk)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button("Зберегти", systemImage: "bookmark") {
                    Task {
                        let result = await environment.library.setCollectionSaved(collection, saved: true)
                        if result == .signInRequired {
                            environment.requireAuthentication(for: .saveCollection(collection))
                        } else {
                            saveMessage = result.message
                        }
                    }
                }
                .labelStyle(.iconOnly)
                .disabled(environment.library.isMutating)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(collection.featuredWorks) { work in
                        Button {
                            environment.catalogPath.append(.linkedWork(identifier: work.slug))
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                BeryndaBookCover(
                                    title: work.title,
                                    imageURL: nil,
                                    design: work.coverDesign,
                                    width: 64,
                                    height: 92
                                )
                                Text(work.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BeryndaColor.ink)
                                    .lineLimit(2)
                                    .frame(width: 96, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .alert("Колекція", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("Гаразд", role: .cancel) {}
        } message: { Text(saveMessage ?? "") }
    }
}

private struct WorkRow: View {
    let work: WorkSummary

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BeryndaBookCover(
                title: work.title,
                imageURL: work.coverImageURL,
                design: work.coverDesign
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
                if let rights = work.rightsSummary, rights != "none", rights != "mixed" {
                    Label(rightsLabel(rights), systemImage: "checkmark.shield")
                        .font(.caption2)
                        .foregroundStyle(BeryndaColor.accent)
                }
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

    private func rightsLabel(_ value: String) -> String {
        switch value {
        case "public_domain": "Суспільне надбання"
        case "open_license": "Відкрита ліцензія"
        case "permission": "Дозволено правовласником"
        default: "Умови доступу визначено"
        }
    }
}
