import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section("Альфа-версія") {
                Label(
                    "Читання без облікового запису",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
                Text("Вхід і профіль з’являться після перевірки основного читання в TestFlight.")
                    .font(.footnote)
                    .foregroundStyle(BeryndaColor.mutedInk)
            }

            Section("Беринда") {
                Link(destination: AppConfiguration.supportURL) {
                    Label("Відкрити сайт", systemImage: "safari")
                }
                Link(destination: AppConfiguration.privacyURL) {
                    Label("Конфіденційність", systemImage: "hand.raised")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(BeryndaColor.paper)
        .navigationTitle("Про застосунок")
        .accessibilityIdentifier("about_screen")
    }
}
