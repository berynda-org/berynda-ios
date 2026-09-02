import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                TabletRootView()
            } else {
                PhoneRootView()
            }
        }
        .background(BeryndaColor.paper.ignoresSafeArea())
    }
}

private struct PhoneRootView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        TabView(selection: $environment.selectedTab) {
            NavigationStack { CatalogView() }
                .tabItem { Label("Каталог", systemImage: "books.vertical") }
                .tag(RootTab.catalog)

            NavigationStack { LibraryPlaceholderView() }
                .tabItem { Label("Бібліотека", systemImage: "bookmark") }
                .tag(RootTab.library)

            NavigationStack { ProfilePlaceholderView() }
                .tabItem { Label("Профіль", systemImage: "person.crop.circle") }
                .tag(RootTab.profile)
        }
    }
}

private struct TabletRootView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        NavigationSplitView {
            List {
                sidebarButton("Каталог", systemImage: "books.vertical", tab: .catalog)
                sidebarButton("Бібліотека", systemImage: "bookmark", tab: .library)
                sidebarButton("Профіль", systemImage: "person.crop.circle", tab: .profile)
            }
            .navigationTitle("Берында")
        } detail: {
            NavigationStack {
                switch environment.selectedTab {
                case .catalog: CatalogView()
                case .library: LibraryPlaceholderView()
                case .profile: ProfilePlaceholderView()
                }
            }
        }
    }

    private func sidebarButton(_ title: String, systemImage: String, tab: RootTab) -> some View {
        Button {
            environment.selectedTab = tab
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .listRowBackground(environment.selectedTab == tab ? BeryndaColor.surface : Color.clear)
    }
}
