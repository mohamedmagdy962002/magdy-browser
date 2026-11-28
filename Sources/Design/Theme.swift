import UIKit

enum Theme {

    private static func adaptive(
        light: UInt32,
        dark: UInt32,
        highContrastLight: UInt32? = nil,
        highContrastDark: UInt32? = nil
    ) -> UIColor {
        UIColor { trait in
            if trait.accessibilityContrast == .high {
                if trait.userInterfaceStyle == .dark, let value = highContrastDark {
                    return UIColor(hex: value)
                }
                if trait.userInterfaceStyle != .dark, let value = highContrastLight {
                    return UIColor(hex: value)
                }
            }
            return UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
        }
    }

    static let canvas = adaptive(light: 0xF7F3EE, dark: 0x120C09)
    static let surface = adaptive(light: 0xFFFDFB, dark: 0x1B1410)
    static let card = surface
    static let raised = adaptive(light: 0xEAE3DC, dark: 0x28201B)
    static let container = adaptive(light: 0xF0EAE4, dark: 0x17100C)
    static let bar = container
    static let field = adaptive(light: 0xE7E0D9, dark: 0x261D19)

    static let textPrimary = adaptive(
        light: 0x211914,
        dark: 0xF0EAE4,
        highContrastLight: 0x18120F,
        highContrastDark: 0xFFFDF8
    )
    static let textSecondary = adaptive(
        light: 0x645C58,
        dark: 0xB0A9A3,
        highContrastLight: 0x403834,
        highContrastDark: 0xD8D0CA
    )
    static let textTertiary = adaptive(
        light: 0x6F6864,
        dark: 0x7F7974,
        highContrastLight: 0x5C5551,
        highContrastDark: 0xA79F99
    )

    static let accent = adaptive(
        light: 0xEA5400,
        dark: 0xFA8927,
        highContrastLight: 0xC53D00,
        highContrastDark: 0xFFB067
    )
    static let accentText = adaptive(
        light: 0xC53D00,
        dark: 0xFFB067,
        highContrastLight: 0xB93400,
        highContrastDark: 0xFFC18A
    )
    static let primary = accentText
    static let primaryAlt = adaptive(light: 0xB93400, dark: 0xEC6F00)
    static let violet = accentText
    static let accentPressed = primaryAlt
    static let accentContainer = adaptive(light: 0xFED4B9, dark: 0x4A200C)
    static let primaryContainer = accentContainer
    static let onAccent = adaptive(
        light: 0x190F0B,
        dark: 0x190F0B,
        highContrastLight: 0xFEFBF8,
        highContrastDark: 0x190F0B
    )

    static let border = adaptive(
        light: 0xD6D0CB,
        dark: 0x38312D,
        highContrastLight: 0x8F8580,
        highContrastDark: 0x6A615C
    )
    static let hairline = UIColor { trait in
        border.withAlphaComponent(trait.accessibilityContrast == .high ? 0.8 : 0.55)
    }
    static let glass = bar

    static let success = adaptive(light: 0x298646, dark: 0x55B978)
    static let warning = adaptive(light: 0xC58D04, dark: 0xE3B74F)
    static let danger = adaptive(light: 0xC53637, dark: 0xF07373, highContrastLight: 0xA32222)
    static let info = adaptive(light: 0x1479B0, dark: 0x63B5DB)
    static let mediaSurface = adaptive(light: 0x20120F, dark: 0x0C0403)
    static let mediaText = adaptive(light: 0xF6F1EB, dark: 0xF6F1EB)
    static let scrim = UIColor { trait in
        UIColor(hex: trait.userInterfaceStyle == .dark ? 0x0C0403 : 0x211914)
            .withAlphaComponent(trait.userInterfaceStyle == .dark ? 0.64 : 0.36)
    }

    static func liquidGlassView(corner: CGFloat) -> UIVisualEffectView {
        let view: UIVisualEffectView
        if UIAccessibility.isReduceTransparencyEnabled {
            view = UIVisualEffectView(effect: nil)
            view.backgroundColor = bar
        } else if #available(iOS 26.0, *) {
            let glass = UIGlassEffect()
            glass.isTinted = true
            glass.tintColor = surface.withAlphaComponent(0.16)
            view = UIVisualEffectView(effect: glass)
        } else {
            view = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            view.backgroundColor = bar.withAlphaComponent(0.68)
        }
        view.layer.cornerRadius = corner
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor(hex: 0x8F8580).withAlphaComponent(0.35).cgColor
        view.clipsToBounds = true
        return view
    }

    static var forcedStyle: UIUserInterfaceStyle {
        switch UserDefaults.standard.string(forKey: "magdy.theme") {
        case "light": return .light
        case "dark": return .dark
        default: return .unspecified
        }
    }

    enum Spacing {
        static let x1: CGFloat = 4
        static let x2: CGFloat = 8
        static let x3: CGFloat = 12
        static let x4: CGFloat = 16
        static let x5: CGFloat = 20
        static let x6: CGFloat = 24
        static let x8: CGFloat = 32
        static let x10: CGFloat = 40
        static let x12: CGFloat = 48
    }

    enum Radius {
        static let small: CGFloat = 8
        static let control: CGFloat = 12
        static let panel: CGFloat = 16
        static let media: CGFloat = 20
        static let feature: CGFloat = 24
    }

    enum Motion {
        static let quick: TimeInterval = 0.15
        static let standard: TimeInterval = 0.22
        static let expressive: TimeInterval = 0.28
    }

    static let corner: CGFloat = Radius.panel
    static let cornerSmall: CGFloat = Radius.control
    static let omniboxHeight: CGFloat = 52
    static let gutter: CGFloat = Spacing.x4
    static let minimumTarget: CGFloat = 44

    static let largeTitle = UIFontMetrics.default.scaledFont(for: AppFonts.headline(34, weight: .bold))
    static let title = UIFontMetrics.default.scaledFont(for: AppFonts.headline(28, weight: .semibold))
    static let headline = UIFontMetrics.default.scaledFont(for: AppFonts.headline(17, weight: .semibold))
    static let bodyStyle = UIFontMetrics.default.scaledFont(for: AppFonts.body(17, weight: .regular))
    static let callout = UIFontMetrics.default.scaledFont(for: AppFonts.body(16, weight: .regular))
    static let subhead = UIFontMetrics.default.scaledFont(for: AppFonts.body(15, weight: .medium))
    static let footnote = UIFontMetrics.default.scaledFont(for: AppFonts.body(13, weight: .regular))
    static let caption = UIFontMetrics.default.scaledFont(for: AppFonts.body(12, weight: .medium))
    static let mediaTime = UIFontMetrics.default.scaledFont(
        for: UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    )

    static func headline(_ size: CGFloat, weight: UIFont.Weight = .bold) -> UIFont {
        UIFontMetrics.default.scaledFont(for: AppFonts.headline(size, weight: weight))
    }

    static func body(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFontMetrics.default.scaledFont(for: AppFonts.body(size, weight: weight))
    }

    static func cardShadow(_ view: UIView) {
        view.layer.shadowColor = UIColor(hex: 0x20120F).cgColor
        view.layer.shadowOpacity = 0.07
        view.layer.shadowRadius = 18
        view.layer.shadowOffset = CGSize(width: 0, height: 6)
    }

    static func floatingShadow(_ view: UIView) {
        view.layer.shadowColor = UIColor(hex: 0x20120F).cgColor
        view.layer.shadowOpacity = 0.12
        view.layer.shadowRadius = 16
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
    }

    static func fabShadow(_ view: UIView) {
        view.layer.shadowColor = UIColor(hex: 0xEA5400).cgColor
        view.layer.shadowOpacity = 0.24
        view.layer.shadowRadius = 16
        view.layer.shadowOffset = CGSize(width: 0, height: 6)
    }

    static func applyGradient(to view: UIView, colors: [UIColor] = [accent, accentPressed]) {
        let gradientView = ThemeGradientView(colors: colors)
        gradientView.translatesAutoresizingMaskIntoConstraints = false
        gradientView.layer.cornerRadius = view.layer.cornerRadius
        view.insertSubview(gradientView, at: 0)
        NSLayoutConstraint.activate([
            gradientView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gradientView.topAnchor.constraint(equalTo: view.topAnchor),
            gradientView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        view.layer.shadowPath = nil
    }

    static func applyGlobalAppearance() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = canvas
        navigation.shadowColor = hairline
        navigation.titleTextAttributes = [
            .foregroundColor: textPrimary,
            .font: headline(17, weight: .semibold)
        ]
        navigation.largeTitleTextAttributes = [
            .foregroundColor: textPrimary,
            .font: largeTitle
        ]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().tintColor = accentText

        let tab = UITabBarAppearance()
        if UIAccessibility.isReduceTransparencyEnabled {
            tab.configureWithOpaqueBackground()
            tab.backgroundColor = bar
        } else {
            tab.configureWithTransparentBackground()
            tab.backgroundColor = .clear
            if #available(iOS 26.0, *) {
                tab.backgroundEffect = UIGlassEffect()
            } else {
                tab.backgroundEffect = UIBlurEffect(style: .systemMaterial)
            }
        }
        tab.shadowColor = hairline
        tab.stackedLayoutAppearance.normal.iconColor = textSecondary
        tab.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: textSecondary,
            .font: caption
        ]
        tab.stackedLayoutAppearance.selected.iconColor = accentText
        tab.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: accentText,
            .font: caption
        ]
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().tintColor = accentText

        UITableView.appearance().backgroundColor = canvas
        UISwitch.appearance().onTintColor = accent
        UIButton.appearance().tintColor = accentText
    }
}

private final class ThemeGradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    private let palette: [UIColor]

    init(colors: [UIColor]) {
        palette = colors
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        let gradient = layer as? CAGradientLayer
        gradient?.startPoint = CGPoint(x: 0, y: 0)
        gradient?.endPoint = CGPoint(x: 1, y: 1)
        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = superview?.layer.cornerRadius ?? 0
    }

    private func updateColors() {
        (layer as? CAGradientLayer)?.colors = palette.map {
            $0.resolvedColor(with: traitCollection).cgColor
        }
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
