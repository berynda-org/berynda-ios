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
}

private extension Color {
    init(light: UInt, dark: UInt) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
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
