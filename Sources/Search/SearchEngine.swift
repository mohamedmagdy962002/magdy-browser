import Foundation

/// Selectable search engines + DuckDuckGo omnibox suggestions.
enum SearchEngine: String, CaseIterable {
    case duckduckgo, google, bing, startpage, ecosia, brave

    var name: String {
        switch self {
        case .duckduckgo: return "DuckDuckGo"
        case .google: return "Google"
        case .bing: return "Bing"
        case .startpage: return "Startpage"
        case .ecosia: return "Ecosia"
        case .brave: return "Brave Search"
        }
    }

    var host: String {
        switch self {
        case .duckduckgo: return "duckduckgo.com"
        case .google: return "www.google.com"
        case .bing: return "www.bing.com"
        case .startpage: return "www.startpage.com"
        case .ecosia: return "www.ecosia.org"
        case .brave: return "search.brave.com"
        }
    }

    func searchURL(for query: String) -> URL? {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+#"))
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        switch self {
        case .duckduckgo: return URL(string: "https://duckduckgo.com/?q=\(encoded)")
        case .google: return URL(string: "https://www.google.com/search?q=\(encoded)")
        case .bing: return URL(string: "https://www.bing.com/search?q=\(encoded)")
        case .startpage: return URL(string: "https://www.startpage.com/sp/search?query=\(encoded)")
        case .ecosia: return URL(string: "https://www.ecosia.org/search?q=\(encoded)")
        case .brave: return URL(string: "https://search.brave.com/search?q=\(encoded)")
        }
    }

    static var selected: SearchEngine {
        get {
            SearchEngine(rawValue: UserDefaults.standard.string(forKey: "magdy.searchEngine") ?? "") ?? .duckduckgo
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "magdy.searchEngine")
        }
    }

    /// True when the user configured a custom engine as active.
    static var isCustom: Bool {
        UserDefaults.standard.string(forKey: "magdy.searchEngine") == "custom"
            && UserDefaults.standard.string(forKey: "magdy.customSearchURL")?.contains("%s") == true
    }

    /// Search URL honoring a user-defined engine (template with %s placeholder).
    static func effectiveSearchURL(for query: String) -> URL? {
        guard isCustom, let template = UserDefaults.standard.string(forKey: "magdy.customSearchURL") else {
            return selected.searchURL(for: query)
        }
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+#"))
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        return URL(string: template.replacingOccurrences(of: "%s", with: encoded))
    }

    /// Display name of the active engine, including a custom one.
    static var displayName: String {
        if isCustom {
            return UserDefaults.standard.string(forKey: "magdy.customSearchName") ?? "Custom"
        }
        return selected.name
    }

    /// Omnibox suggestions from DuckDuckGo's public autocomplete endpoint.
    static func suggestions(for query: String, completion: @escaping ([String]) -> Void) {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+#"))
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        guard let url = URL(string: "https://duckduckgo.com/ac/?q=\(encoded)&type=list") else {
            completion([])
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            var results: [String] = []
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) {
                // type=list returns [["query", [..suggestions..]]] or a plain array.
                if let array = json as? [Any] {
                    for entry in array {
                        if let item = entry as? String {
                            results.append(item)
                        } else if let pair = entry as? [Any], let text = pair.last as? [Any] {
                            results.append(contentsOf: text.compactMap { $0 as? String })
                        }
                    }
                }
            }
            DispatchQueue.main.async { completion(Array(results.prefix(6))) }
        }.resume()
    }
}
