import SwiftUI

struct LibraryUnavailableView: View {
    var body: some View {
        BeryndaEmptyState(
            title: "Бібліотека ще недоступна",
            message: "В альфа-версії можна шукати й читати видання без облікового запису. Особисту бібліотеку додамо в наступній версії.",
            systemImage: "bookmark.slash"
        )
        .navigationTitle("Бібліотека")
        .accessibilityIdentifier("library_unavailable")
    }
}
