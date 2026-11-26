import CoreText
import UIKit

/// Space Grotesk for brand headlines, system fonts for UI body text, and bundled Noto families for supported non-Latin scripts.
enum AppFonts {

    static let familyNames = [
        "Inter", "SpaceGrotesk", "NotoSansArabic",
        "NotoSansJP", "NotoSansKR", "NotoSansSC"
    ]

    private static var registered = false
    private static var descriptors: [String: CTFontDescriptor] = [:]

    static func register() {
        guard !registered else { return }
        registered = true

        for name in familyNames {
            guard let data = fontData(named: name),
                  let provider = CGDataProvider(data: data as CFData),
                  let cgFont = CGFont(provider),
                  let descriptor = CTFontManagerCreateFontDescriptorFromData(data as CFData) else { continue }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterGraphicsFont(cgFont, &error)
            descriptors[name] = descriptor
        }
    }

    private static func fontData(named name: String) -> Data? {
        if let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts"),
           let data = try? Data(contentsOf: url) {
            return data
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "ttf"),
           let data = try? Data(contentsOf: url) {
            return data
        }
        return nil
    }

    static func font(_ family: String, size: CGFloat, weight: UIFont.Weight) -> UIFont {
        register()
        guard let descriptor = descriptors[family] else {
            return UIFont.systemFont(ofSize: size, weight: weight)
        }
        let traits: [CFString: Any] = [
            kCTFontWeightTrait: CGFloat(weight.rawValue)
        ]
        let attributes: [CFString: Any] = [kCTFontTraitsAttribute: traits]
        let varied = CTFontDescriptorCreateCopyWithAttributes(descriptor, attributes as CFDictionary)
        return UIFont(descriptor: varied, size: size)
    }

    /// Rounded system face for large brand and media titles.
    static func headline(_ size: CGFloat, weight: UIFont.Weight = .bold) -> UIFont {
        let fallback = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = fallback.fontDescriptor.withDesign(.rounded) else { return fallback }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Optional bundled brand face for the canonical wordmark.
    static func brandHeadline(_ size: CGFloat, weight: UIFont.Weight = .bold) -> UIFont {
        let custom = font("SpaceGrotesk", size: size, weight: weight)
        if custom.fontName.lowercased().contains("spacegrotesk") { return custom }
        return headline(size, weight: weight)
    }

    /// System body face, with bundled Noto families for supported non-Latin scripts.
    static func body(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let family: String?
        switch L.languageTag {
        case "ar", "fa": family = "NotoSansArabic"
        case "ja": family = "NotoSansJP"
        case "ko": family = "NotoSansKR"
        case "zh", "zh-hans": family = "NotoSansSC"
        default: family = nil
        }
        guard let family else { return UIFont.systemFont(ofSize: size, weight: weight) }
        let custom = font(family, size: size, weight: weight)
        if custom.fontName.lowercased().contains(family.lowercased()) { return custom }
        return UIFont.systemFont(ofSize: size, weight: weight)
    }
}
