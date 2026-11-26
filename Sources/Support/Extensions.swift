import Foundation

extension Notification.Name {
    /// Posted with a URL as the notification object to open a link in the browser.
    static let magdyOpenURL = Notification.Name("com.magdy.openURL")
    /// Posted with a URL as the notification object to download a media URL.
    static let magdyDownloadURL = Notification.Name("com.magdy.downloadURL")
    /// Posted with a Bool when night mode is toggled from settings.
    static let magdyNightModeChanged = Notification.Name("com.magdy.nightModeChanged")
    /// Posted when the theme setting changes.
    static let magdyThemeChanged = Notification.Name("com.magdy.themeChanged")
    /// Fired when the user switches the search bar between top and bottom.
    static let magdyOmniboxChanged = Notification.Name("com.magdy.omniboxChanged")
    static let magdyLockRequested = Notification.Name("com.magdy.lockRequested")
    static let magdyLanguageChanged = Notification.Name("com.magdy.languageChanged")
}

enum UserDefaultsKey {
    static let blockAds = "magdy.blockAds"
    static let blockTrackers = "magdy.blockTrackers"
    static let strongBlocking = "magdy.strongBlocking"
    static let defaultPrivate = "magdy.defaultPrivate"
    static let favorites = "magdy.favorites"
    static let language = "magdy.language"
    static let searchSuggestions = "magdy.searchSuggestions"
    /// true = omnibox docked at the bottom (Aloha-style), false = top (default).
    static let omniboxBottomKey = "magdy.omniboxBottom"

    static func bool(_ key: String, default fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }
}

extension HTTPCookie {
    func applies(to url: URL) -> Bool {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        let domain = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !domain.isEmpty, host == domain || host.hasSuffix("." + domain) else { return false }
        if isSecure, url.scheme?.lowercased() != "https" { return false }
        if let expiresDate, expiresDate <= Date() { return false }

        let requestPath = url.path.isEmpty ? "/" : url.path
        let cookiePath = path.isEmpty ? "/" : path
        guard requestPath == cookiePath || requestPath.hasPrefix(cookiePath) else { return false }
        if requestPath.count > cookiePath.count, !cookiePath.hasSuffix("/") {
            return requestPath.dropFirst(cookiePath.count).first == "/"
        }
        return true
    }
}

extension String {
    /// Turns typed text into a URL: bare hosts get https, anything with spaces becomes a search.
    var magdyNavigable: URL? {
        let text = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.contains(" ") {
            if let quick = Self.quickSearchURL(for: text) { return quick }
            return searchURL(for: text)
        }
        if text.contains(".") || text.contains(":"),
           let url = URL.webURL(from: text) {
            return url
        }
        return searchURL(for: text)
    }

    /// Quick Website Search: "wiki cats" searches Wikipedia, "yt cats" YouTube, etc.
    /// Off by default so it never hijacks normal queries.
    static let quickSearchEnabledKey = "magdy.quickSearch"

    private static let quickSites: [String: String] = [
        "wiki": "https://en.wikipedia.org/w/index.php?search=%@&fulltext=1",
        "yt": "https://www.youtube.com/results?search_query=%@",
        "a": "https://www.amazon.com/s?k=%@",
        "az": "https://www.amazon.com/s?k=%@",
        "tw": "https://x.com/search?q=%@",
        "x": "https://x.com/search?q=%@",
        "ig": "https://www.instagram.com/explore/tags/%@",
        "g": "https://www.google.com/search?q=%@"
    ]

    private static func quickSearchURL(for text: String) -> URL? {
        guard UserDefaults.standard.bool(forKey: quickSearchEnabledKey) else { return nil }
        let parts = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, let template = quickSites[parts[0].lowercased()] else { return nil }
        let query = parts[1]
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .replacingOccurrences(of: "+", with: "%2B") ?? ""
        return URL(string: template.replacingOccurrences(of: "%@", with: query))
    }

    private func searchURL(for query: String) -> URL? {
        SearchEngine.effectiveSearchURL(for: query)
    }
}
