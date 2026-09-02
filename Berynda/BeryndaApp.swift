import SwiftUI

@main
struct BeryndaApp: App {
    @StateObject private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(environment)
                .tint(BeryndaColor.accent)
                .onOpenURL { environment.open($0) }
        }
    }
}
