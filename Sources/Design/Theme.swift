import UIKit

/// Design tokens generated from the Stitch "Magdy Browser — Modern Redesign" design system.
///
/// Dark: canvas #0D0E12 · card #181920 · border #262734 · primary #8B5CF6 → #A78BFA
/// Light: canvas #FAFAFC · card #FFFFFF. Headlines Space Grotesk, body Manrope.
enum Theme {

    // MARK: - Colors

    /// Light/dark adaptive colors — dark values resolve automatically when the
    /// interface style changes (or when the app is forced via the Theme setting).
    private static func adaptive(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        }
    }

    static let canvas = adaptive(light: 0xFAFAFC, dark: 0x0D0E12)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x181920)
    /// Elevated container (tables, section backgrounds).
    static let container = adaptive(light: 0xFFFFFF, dark: 0x13141B)
    static let primary = UIColor(hex: 0x8B5CF6)
    static let primaryAlt = UIColor(hex: 0xA78BFA)
    /// Soft violet tint background for icon squircles / accents.
    static let primaryContainer = adaptive(light: 0xF1EBFE, dark: 0x24183E)
    static let violet = UIColor(hex: 0xA78BFA)
    static let textPrimary = adaptive(light: 0x1C1C1E, dark: 0xF3F4F6)
    static let textSecondary = adaptive(light: 0x8E8E93, dark: 0x9CA3AF)
    // Alpha must be applied inside the provider — withAlphaComponent on a dynamic
    // color resolves it once and freezes the light/dark value.
    static let hairline = UIColor { t in
        (t.userInterfaceStyle == .dark ? UIColor(hex: 0x262734) : UIColor(hex: 0x2C2C2E)).withAlphaComponent(0.10)
    }
    static let glass = UIColor { t in
        (t.userInterfaceStyle == .dark ? UIColor(hex: 0x13141B) : UIColor(hex: 0xFFFFFF)).withAlphaComponent(0.90)
    }

    /// App theme: system, forced light or forced dark. Forced styles are applied
    /// per window in RootViewController.
    static var forcedStyle: UIUserInterfaceStyle {
        switch UserDefaults.standard.string(forKey: "magdy.theme") {
        case "light": return .light
        case "dark": return .dark
        default: return .unspecified
        }
    }

    // MARK: - Metrics

    static let corner: CGFloat = 16
    static let cornerSmall: CGFloat = 12
    static let omniboxHeight: CGFloat = 50
    static let gutter: CGFloat = 16

    // MARK: - Type

    /// Geometric headline face (Space Grotesk in Stitch -> bundled Space Grotesk / SF Rounded).
    static func headline(_ size: CGFloat, weight: UIFont.Weight = .bold) -> UIFont {
        AppFonts.headline(size, weight: weight)
    }

    static func body(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        AppFonts.body(size, weight: weight)
    }

    // MARK: - Elevation

    /// Level 1 — resting card.
    static func cardShadow(_ view: UIView) {
        view.layer.shadowColor = UIColor(hex: 0x1C1C1E).cgColor
        view.layer.shadowOpacity = 0.06
        view.layer.shadowRadius = 24
        view.layer.shadowOffset = CGSize(width: 0, height: 8)
    }

    /// Level 2 — floating chrome.
    static func floatingShadow(_ view: UIView) {
        view.layer.shadowColor = UIColor(hex: 0x1C1C1E).cgColor
        view.layer.shadowOpacity = 0.08
        view.layer.shadowRadius = 20
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
    }

    /// Level 3 — primary action.
    static func fabShadow(_ view: UIView) {
        view.layer.shadowColor = primary.cgColor
        view.layer.shadowOpacity = 0.35
        view.layer.shadowRadius = 22
        view.layer.shadowOffset = CGSize(width: 0, height: 8)
    }

    // MARK: - Gradients

    static func applyGradient(to view: UIView, colors: [UIColor] = [primary, primaryAlt]) {
        let gradient = CAGradientLayer()
        gradient.colors = colors.map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.frame = view.bounds
        gradient.cornerRadius = view.layer.cornerRadius
        view.layer.insertSublayer(gradient, at: 0)
        view.layer.shadowPath = nil
    }

    // MARK: - Global appearance

    static func applyGlobalAppearance() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = canvas
        navigation.shadowColor = .clear
        navigation.titleTextAttributes = [
            .foregroundColor: textPrimary,
            .font: headline(17, weight: .semibold)
        ]
        navigation.largeTitleTextAttributes = [
            .foregroundColor: textPrimary,
            .font: headline(32, weight: .bold)
        ]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().tintColor = primary

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundColor = glass
        tab.shadowColor = hairline
        tab.stackedLayoutAppearance.normal.iconColor = textSecondary
        tab.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: textSecondary,
            .font: body(10, weight: .medium)
        ]
        tab.stackedLayoutAppearance.selected.iconColor = primary
        tab.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: primary,
            .font: body(10, weight: .semibold)
        ]
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        UITableView.appearance().backgroundColor = canvas
        UISwitch.appearance().onTintColor = primary
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
