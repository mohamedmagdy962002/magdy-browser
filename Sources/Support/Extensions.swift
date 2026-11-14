import Foundation

extension Notification.Name {
    /// Posted with a URL as the notification object to open a link in the browser.
    static let magdyOpenURL = Notification.Name("com.magdy.openURL")
    /// Posted with a URL as the notification object to download a media URL.
    static let magdyDownloadURL = Notification.Name("com.magdy.downloadURL")
    /// Posted with a Bool when night mode is toggled from settings.
    static let magdyNightModeChanged = Notification.Name("com.magdy.nightModeChanged")
}

enum UserDefaultsKey {
    static let blockAds = "magdy.blockAds"
    static let blockTrackers = "magdy.blockTrackers"
    static let strongBlocking = "magdy.strongBlocking"
    static let defaultPrivate = "magdy.defaultPrivate"
    static let favorites = "magdy.favorites"
    static let language = "magdy.language"

    static func bool(_ key: String, default fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }
}

extension String {
    /// Turns typed text into a URL: bare hosts get https, anything with spaces becomes a search.
    var magdyNavigable: URL? {
        let text = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.contains(" ") { return searchURL(for: text) }
        if let url = URL(string: text), let scheme = url.scheme, !scheme.isEmpty, url.host != nil {
            return url
        }
        if text.contains(".") { return URL(string: "https://\(text)") }
        return searchURL(for: text)
    }

    private func searchURL(for query: String) -> URL? {
        SearchEngine.selected.searchURL(for: query)
    }
}
