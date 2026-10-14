import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    static let ecBackground = Color(hex: 0x111318)
    static let ecSurface = Color(hex: 0x20242D)
    static let ecInput = Color(hex: 0x2A303C)
    static let ecTextPrimary = Color(hex: 0xF7F8FA)
    static let ecTextSecondary = Color(hex: 0xAFB8C8)
    static let ecBlue = Color(hex: 0x356DFF)
    static let ecLilac = Color(hex: 0xB89AFF)
    static let ecMint = Color(hex: 0x69DFBE)
    static let ecCoral = Color(hex: 0xFF6D83)
    static let ecDivider = Color(hex: 0x3B4352)
    static let ecOnBlue = Color.white
    static let ecOnAccent = Color(hex: 0x111318)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum Spacing {
    /// Screen side padding.
    static let screen: CGFloat = 20
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
}

enum Radius {
    static let card: CGFloat = 22
    static let field: CGFloat = 14
    static let button: CGFloat = 16
}

enum Metrics {
    static let minTapTarget: CGFloat = 44
    static let primaryButtonHeight: CGFloat = 52
}

extension AvatarColorKey {
    var fill: Color {
        switch self {
        case .blue: return Color.ecBlue
        case .lilac: return Color.ecLilac
        case .mint: return Color.ecMint
        case .coral: return Color.ecCoral
        case .amber: return Color(hex: 0xF5C25B)
        case .sky: return Color(hex: 0x5CC8FF)
        }
    }

    var initialsColor: Color {
        self == .blue ? .ecOnBlue : .ecOnAccent
    }
}

/// Dynamic Type–aware fixed sizes from the spec (title 31, amounts 36, sections 20).
private struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let monospacedDigits: Bool

    init(size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight, monospacedDigits: Bool) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.monospacedDigits = monospacedDigits
    }

    func body(content: Content) -> some View {
        let font = Font.system(size: size, weight: weight, design: .default)
        return content.font(monospacedDigits ? font.monospacedDigit() : font)
    }
}

extension View {
    func ecScreenTitleFont() -> some View {
        modifier(ScaledFont(size: 31, relativeTo: .largeTitle, weight: .bold, monospacedDigits: false))
    }

    func ecHeroAmountFont(size: CGFloat = 36) -> some View {
        modifier(ScaledFont(size: size, relativeTo: .largeTitle, weight: .semibold, monospacedDigits: true))
    }

    func ecSectionFont() -> some View {
        modifier(ScaledFont(size: 20, relativeTo: .title3, weight: .semibold, monospacedDigits: false))
    }

    func ecAmountFont(weight: Font.Weight = .semibold) -> some View {
        modifier(ScaledFont(size: 17, relativeTo: .body, weight: weight, monospacedDigits: true))
    }

    func ecCaptionFont() -> some View {
        modifier(ScaledFont(size: 13, relativeTo: .footnote, weight: .regular, monospacedDigits: false))
    }
}

/// Global UIKit appearance so navigation bars, tab bars and segmented controls follow the palette.
enum Appearance {
    static func configure() {
        let background = UIColor(hex: 0x111318)
        let surface = UIColor(hex: 0x20242D)
        let primary = UIColor(hex: 0xF7F8FA)
        let secondary = UIColor(hex: 0xAFB8C8)
        let blue = UIColor(hex: 0x356DFF)

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = background
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: primary]
        nav.largeTitleTextAttributes = [.foregroundColor: primary]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(hex: 0x8FB0FF)

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = surface
        tab.shadowColor = UIColor(hex: 0x3B4352)
        for layout in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            layout.normal.iconColor = secondary
            layout.normal.titleTextAttributes = [.foregroundColor: secondary]
            layout.selected.iconColor = UIColor(hex: 0x8FB0FF)
            layout.selected.titleTextAttributes = [.foregroundColor: UIColor(hex: 0x8FB0FF)]
        }
        UITabBar.appearance().standardAppearance = tab
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = tab
        }

        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = blue
        segmented.backgroundColor = UIColor(hex: 0x2A303C)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.preferredFont(forTextStyle: .subheadline)], for: .selected)
        segmented.setTitleTextAttributes([.foregroundColor: secondary, .font: UIFont.preferredFont(forTextStyle: .subheadline)], for: .normal)

        UITextView.appearance().backgroundColor = .clear
    }
}
