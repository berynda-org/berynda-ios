import SwiftUI

@main
struct BeryndaApp: App {
    @StateObject private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(environment)
                .environmentObject(environment.networkMonitor)
                .tint(BeryndaColor.accent)
                .onOpenURL { environment.open($0) }
        }
    }
}
