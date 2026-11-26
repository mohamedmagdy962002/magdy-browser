import UIKit

/// Design tokens generated from the Stitch "Magdy Master" light design system.
///
/// Light ("MASTER" reference): surface #FBF8FF · card #FFFFFF · container #F5F2FB
/// primary #5F48BD (deep periwinkle) · alt #7862D7 · text #1B1B21 / #484553.
/// Dark: canvas #0D0E12 · card #181920 · border #262734 (kept from Magdy Modern).
enum Theme {

    // MARK: - Colors

    /// Light/dark adaptive colors — dark values resolve automatically when the
    /// interface style changes (or when the app is forced via the Theme setting).
    private static func adaptive(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        }
    }

    static let canvas = adaptive(light: 0xFBF8FF, dark: 0x0D0E12)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x181920)
    /// Elevated container (tables, section backgrounds).
    static let container = adaptive(light: 0xF5F2FB, dark: 0x13141B)
    static let primary = adaptive(light: 0x5F48BD, dark: 0x8B5CF6)
    static let primaryAlt = adaptive(light: 0x7862D7, dark: 0xA78BFA)
    /// Soft lavender tint background for icon squircles / accents.
    static let primaryContainer = adaptive(light: 0xE6DEFF, dark: 0x24183E)
    static let violet = adaptive(light: 0x7862D7, dark: 0xA78BFA)
    static let textPrimary = adaptive(light: 0x1B1B21, dark: 0xF3F4F6)
    static let textSecondary = adaptive(light: 0x484553, dark: 0x9CA3AF)
    // Alpha must be applied inside the provider — withAlphaComponent on a dynamic
    // color resolves it once and freezes the light/dark value.
    static let hairline = UIColor { t in
        (t.userInterfaceStyle == .dark ? UIColor(hex: 0x262734) : UIColor(hex: 0xC9C4D5)).withAlphaComponent(0.45)
    }
    static let glass = UIColor { t in
        (t.userInterfaceStyle == .dark ? UIColor(hex: 0x13141B) : UIColor(hex: 0xFFFFFF)).withAlphaComponent(0.94)
    }

    // MARK: - Liquid Glass (iOS 26 style)

    /// Frosted liquid-glass surface: blur material + lavender tint + specular edge.
    /// Content views are added ON TOP of the returned effect view.
    static func liquidGlassView(corner: CGFloat) -> UIVisualEffectView {
        let glass = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        glass.layer.cornerRadius = corner
        glass.layer.cornerCurve = .continuous
        glass.layer.borderWidth = 1
        // cgColor resolves once — a mid alpha reads as glass in both modes.
        glass.layer.borderColor = UIColor(white: 1, alpha: 0.65).cgColor
        glass.clipsToBounds = true
        // Lavender tint so the capsule still reads over plain white pages.
        let tint = UIView()
        tint.backgroundColor = UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0, alpha: 0.10)
                : UIColor(hex: 0x5F48BD).withAlphaComponent(0.07)
        }
        tint.translatesAutoresizingMaskIntoConstraints = false
        tint.isUserInteractionEnabled = false
        glass.contentView.addSubview(tint)
        NSLayoutConstraint.activate([
            tint.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
            tint.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor),
            tint.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor)
        ])
        return glass
    }

    /// App theme: MASTER light by default, forced light or forced dark. Forced
    /// styles are applied per window in RootViewController.
    static var forcedStyle: UIUserInterfaceStyle {
        switch UserDefaults.standard.string(forKey: "magdy.theme") {
        case "system": return .unspecified
        case "dark": return .dark
        default: return .light
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
        UIFontMetrics.default.scaledFont(for: AppFonts.headline(size, weight: weight))
    }

    static func body(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFontMetrics.default.scaledFont(for: AppFonts.body(size, weight: weight))
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
