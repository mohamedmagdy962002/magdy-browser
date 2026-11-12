import Foundation

extension Notification.Name {
    /// Posted with a URL as the notification object to open a link in the browser.
    static let magdyOpenURL = Notification.Name("com.magdy.openURL")
}

enum UserDefaultsKey {
    static let blockAds = "magdy.blockAds"
    static let blockTrackers = "magdy.blockTrackers"
    static let defaultPrivate = "magdy.defaultPrivate"
    static let favorites = "magdy.favorites"

    static func bool(_ key: String, default fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }
}

extension URL {
    /// Treats a bare host ("example.com") as https, anything with spaces as a search query.
    var magdyNavigable: URL? {
        let text = trimmedText
        guard !text.isEmpty else { return nil }
        if text.contains(" ") { return searchURL(for: text) }
        if let url = URL(string: text), let scheme = url.scheme, !scheme.isEmpty, url.host != nil {
            return url
        }
        if text.contains("."), !text.contains(" ") {
            return URL(string: "https://\(text)")
        }
        return searchURL(for: text)
    }

    private var trimmedText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func searchURL(for query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: "https://duckduckgo.com/?q=\(encoded)")
    }
}
