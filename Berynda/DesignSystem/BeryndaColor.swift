import SwiftUI
import UIKit

enum BeryndaColor {
    static let paper = Color(light: 0xF4F3ED, dark: 0x171312)
    static let surface = Color(light: 0xFFFDF8, dark: 0x251F1D)
    static let ink = Color(light: 0x251F1D, dark: 0xFFFDF8)
    static let mutedInk = Color(light: 0x6B6660, dark: 0xC8C0B8)
    static let border = Color(light: 0xD9D8CD, dark: 0x4A413E)
    static let accent = Color(light: 0x95271D, dark: 0xE77B49)
    static let deepAccent = Color(light: 0x60241E, dark: 0xF1A078)

    static func coverPalette(for tone: String?) -> (background: Color, ink: Color) {
        let values: (UInt, UInt)
        switch tone {
        case "blue": values = (0x385B78, 0xF5F1E8)
        case "green": values = (0x465F4D, 0xF6F1E5)
        case "ochre": values = (0x8A5C22, 0xFFF7E8)
        case "plum": values = (0x66516D, 0xFAF2E6)
        case "teal": values = (0x3E6667, 0xF6F2E8)
        case "slate": values = (0x31404E, 0xEEF0EA)
        case "burgundy": values = (0x5C1F2E, 0xFAF0E6)
        case "moss": values = (0x4F5C33, 0xF4F1E2)
        case "sepia": values = (0x6B4A30, 0xF8F0E0)
        case "aubergine": values = (0x4A2545, 0xF6ECF2)
        case "graphite": values = (0x37484A, 0xEEF1EC)
        default: values = (0x6D2925, 0xFFF7E8)
        }
        return (Color(hex: values.0), Color(hex: values.1))
    }
}

private extension Color {
    init(light: UInt, dark: UInt) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
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
