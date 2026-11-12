import CoreText
import UIKit

/// Bundled variable typefaces loaded through CoreText, with a system-font fallback.
/// Inter (body) and Space Grotesk (headlines) match the Stitch design system;
/// the Noto families cover Latin, Arabic, Japanese, Korean, Simplified and
/// Traditional Chinese so localised UI text renders with the bundled faces.
enum AppFonts {

    static let familyNames = [
        "Inter", "SpaceGrotesk", "NotoSans", "NotoSansArabic",
        "NotoSansJP", "NotoSansKR", "NotoSansSC", "NotoSansTC"
    ]

    private static var registered = false
    private static var descriptors: [String: CTFontDescriptor] = [:]

    static func register() {
        guard !registered else { return }
        registered = true

        for name in familyNames {
            guard let data = fontData(named: name),
                  let provider = CGDataProvider(data: data as CFData),
                  let cgFont = CGFont(provider) else { continue }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterGraphicsFont(cgFont, &error)
            descriptors[name] = CTFontDescriptorCreateWithGraphicsFont(cgFont, 0, nil, nil)
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

    /// Headline face: Space Grotesk, falling back to the system rounded face.
    static func headline(_ size: CGFloat, weight: UIFont.Weight = .bold) -> UIFont {
        let custom = font("SpaceGrotesk", size: size, weight: weight)
        if custom.fontName.lowercased().contains("spacegrotesk") { return custom }
        let fallback = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = fallback.fontDescriptor.withDesign(.rounded) else { return fallback }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Body face: Inter, or a Noto family for non-Latin scripts.
    static func body(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let family: String
        switch L.resolvedLanguage {
        case "ar", "fa", "he": family = "NotoSansArabic"
        case "ja": family = "NotoSansJP"
        case "ko": family = "NotoSansKR"
        case "zh": family = "NotoSansSC"
        default: family = "Inter"
        }
        let custom = font(family, size: size, weight: weight)
        if custom.fontName.lowercased().contains(family.lowercased()) { return custom }
        return UIFont.systemFont(ofSize: size, weight: weight)
    }
}
