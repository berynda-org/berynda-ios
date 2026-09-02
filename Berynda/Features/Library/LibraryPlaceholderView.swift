import SwiftUI

struct LibraryPlaceholderView: View {
    var body: some View {
        BeryndaEmptyState(
            title: "Ваша бібліотека",
            message: "Продовження читання та бібліографічні списки з’являться після підключення входу.",
            systemImage: "bookmark"
        )
        .navigationTitle("Бібліотека")
    }
}
