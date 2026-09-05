import BeryndaCore
import SwiftUI
import UIKit

enum BeryndaColor {
    // Values are taken from the normative prototype in
    // `web/public/ios-mockups/styles.css`; the dark set is its
    // `body[data-app-theme="dark"]` block. Light already matched; dark had
    // drifted in five of seven tokens, most visibly `ink`, which was near-pure
    // white where the design calls for a warm off-white — harsher than
    // intended for long reading.
    //
    // The increased-contrast variants are this client's own: the prototype
    // defines no high-contrast palette, and the standard borders are
    // decorative (about 1.3:1) rather than perceivable boundaries. Under
    // Increase Contrast they are strengthened past the 3:1 that WCAG 1.4.11
    // asks of UI boundaries, and muted text past the 7:1 of AAA body text.
    static let paper = Color(BeryndaPalette.paper)
    static let surface = Color(BeryndaPalette.surface)
    static let ink = Color(BeryndaPalette.ink)
    static let mutedInk = Color(BeryndaPalette.mutedInk)
    static let border = Color(BeryndaPalette.border)
    static let accent = Color(BeryndaPalette.accent)
    static let deepAccent = Color(BeryndaPalette.deepAccent)

    static func coverPalette(for tone: CoverTone) -> (background: Color, ink: Color) {
        let pair = coverHexPair(for: tone)
        return (Color(hex: pair.background), Color(hex: pair.ink))
    }

    /// One entry per `CoverTone`, so an unhandled tone is a compile error
    /// rather than a work silently painted oxblood. Exposed as raw values so
    /// the glyph's legibility on each background can be asserted.
    static func coverHexPair(for tone: CoverTone) -> (background: UInt, ink: UInt) {
        let values: (UInt, UInt)
        switch tone {
        case .oxblood: values = (0x6D2925, 0xFFF7E8)
        case .blue: values = (0x385B78, 0xF5F1E8)
        case .green: values = (0x465F4D, 0xF6F1E5)
        case .ochre: values = (0x8A5C22, 0xFFF7E8)
        case .plum: values = (0x66516D, 0xFAF2E6)
        case .teal: values = (0x3E6667, 0xF6F2E8)
        case .slate: values = (0x31404E, 0xEEF0EA)
        case .burgundy: values = (0x5C1F2E, 0xFAF0E6)
        case .moss: values = (0x4F5C33, 0xF4F1E2)
        case .sepia: values = (0x6B4A30, 0xF8F0E0)
        case .aubergine: values = (0x4A2545, 0xF6ECF2)
        case .graphite: values = (0x37484A, 0xEEF1EC)
        }
        return (background: values.0, ink: values.1)
    }
}

private extension Color {
    /// Resolves against both the interface style and the Increase Contrast
    /// accessibility setting, so a reader who turns it on gets stronger
    /// boundaries and muted text without anything else changing.
    init(_ token: BeryndaPalette.Token) {
        self.init(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let isIncreased = traits.accessibilityContrast == .high
            switch (isDark, isIncreased) {
            case (false, false): return UIColor(hex: token.light)
            case (false, true): return UIColor(hex: token.lightIncreased)
            case (true, false): return UIColor(hex: token.dark)
            case (true, true): return UIColor(hex: token.darkIncreased)
            }
        })
    }

    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}

private extension UIColor {
    convenience init(hex: UInt) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}
