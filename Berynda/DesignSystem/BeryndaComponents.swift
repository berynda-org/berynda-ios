import SwiftUI

enum BeryndaSpacing {
    static let compact: CGFloat = 8
    static let standard: CGFloat = 16
    static let section: CGFloat = 24
}

struct BeryndaPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(BeryndaColor.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(BeryndaColor.border, lineWidth: 1)
            }
    }
}

struct BeryndaEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .foregroundStyle(BeryndaColor.ink)
    }
}

struct BeryndaLoadingState: View {
    let message: String

    var body: some View {
        VStack(spacing: BeryndaSpacing.standard) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(BeryndaColor.mutedInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct BeryndaErrorState: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Спробувати ще раз", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(BeryndaColor.accent)
        }
        .foregroundStyle(BeryndaColor.ink)
    }
}

struct BeryndaBookCover: View {
    let title: String
    let glyph: String?
    let tone: String?
    var width: CGFloat = 54
    var height: CGFloat = 78

    var body: some View {
        let palette = BeryndaColor.coverPalette(for: tone)
        RoundedRectangle(cornerRadius: max(width * 0.09, 4), style: .continuous)
            .fill(palette.background)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.black.opacity(0.16))
                    .frame(width: max(width * 0.07, 3))
                    .padding(.vertical, 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: max(width * 0.07, 3), style: .continuous)
                    .stroke(palette.ink.opacity(0.38), lineWidth: 1)
                    .padding(max(width * 0.1, 5))
            }
            .overlay {
                Text(displayGlyph)
                    .font(.system(size: width * 0.42, weight: .semibold, design: .serif))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(palette.ink)
                    .padding(width * 0.14)
            }
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }

    private var displayGlyph: String {
        if let glyph, !glyph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return glyph
        }
        return String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }
}
