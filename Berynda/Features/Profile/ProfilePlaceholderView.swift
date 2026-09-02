import SwiftUI

struct ProfilePlaceholderView: View {
    var body: some View {
        List {
            Section("Обліковий запис") {
                Label("Увійти", systemImage: "person.crop.circle.badge.checkmark")
            }
            Section("Про застосунок") {
                Link("Сайт Берынды", destination: AppConfiguration.supportURL)
                Link("Конфіденційність", destination: AppConfiguration.privacyURL)
            }
        }
        .navigationTitle("Профіль")
    }
}
