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
        let value = template.replacingOccurrences(of: "%s", with: encoded)
        guard let url = URL(string: value), url.isWebURL else { return nil }
        return url
    }

    /// Display name of the active engine, including a custom one.
    static var displayName: String {
        if isCustom {
            return UserDefaults.standard.string(forKey: "magdy.customSearchName") ?? "Custom"
        }
        return selected.name
    }

    /// Debounced omnibox suggestions from the selected provider. All request
    /// state is confined to the main queue; a newer query cancels older work.
    static func suggestions(for query: String, completion: @escaping ([String]) -> Void) {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.async {
            suggestionGeneration &+= 1
            let generation = suggestionGeneration
            pendingSuggestionWork?.cancel()
            pendingSuggestionWork = nil
            suggestionTask?.cancel()
            suggestionTask = nil

            guard UserDefaultsKey.bool(UserDefaultsKey.searchSuggestions, default: false), !text.isEmpty else {
                completion([])
                return
            }
            if ProcessInfo.processInfo.environment["MAGDY_UI_TEST"] == "1" {
                completion([text, "\(text) browser", "\(text) news"])
                return
            }

            let work = DispatchWorkItem {
                guard generation == suggestionGeneration else { return }
                guard UserDefaultsKey.bool(UserDefaultsKey.searchSuggestions, default: false) else {
                    completion([])
                    return
                }
                // Custom engines have no declared autocomplete contract. Do not
                // send omnibox text to an arbitrary user-configured endpoint.
                guard !isCustom else {
                    completion([])
                    return
                }
                let provider = selected
                let providerID = provider.rawValue
                guard let url = suggestionURL(for: provider, query: text) else {
                    completion([])
                    return
                }
                let task = URLSession.shared.dataTask(with: url) { data, _, _ in
                    let results = data.map(parseSuggestions) ?? []
                    DispatchQueue.main.async {
                        guard generation == suggestionGeneration else { return }
                        suggestionTask = nil
                        guard UserDefaultsKey.bool(UserDefaultsKey.searchSuggestions, default: false),
                              providerIdentifier() == providerID else {
                            completion([])
                            return
                        }
                        completion(results)
                    }
                }
                suggestionTask = task
                task.resume()
            }
            pendingSuggestionWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + suggestionDebounce, execute: work)
        }
    }

    private static let suggestionDebounce: TimeInterval = 0.25
    private static var pendingSuggestionWork: DispatchWorkItem?
    private static var suggestionTask: URLSessionDataTask?
    private static var suggestionGeneration: UInt64 = 0

    private static func providerIdentifier() -> String {
        isCustom ? "custom" : selected.rawValue
    }

    private static func suggestionURL(for provider: SearchEngine, query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        switch provider {
        case .duckduckgo:
            components.host = "duckduckgo.com"
            components.path = "/ac/"
            components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "type", value: "list")]
        case .google:
            components.host = "suggestqueries.google.com"
            components.path = "/complete/search"
            components.queryItems = [URLQueryItem(name: "client", value: "firefox"), URLQueryItem(name: "q", value: query)]
        case .bing:
            components.host = "api.bing.com"
            components.path = "/osjson.aspx"
            components.queryItems = [URLQueryItem(name: "query", value: query)]
        case .startpage:
            components.host = "www.startpage.com"
            components.path = "/do/suggest"
            components.queryItems = [
                URLQueryItem(name: "limit", value: "10"),
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "query", value: query)
            ]
        case .ecosia:
            components.host = "ac.ecosia.org"
            components.path = "/autocomplete"
            components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "type", value: "list")]
        case .brave:
            components.host = "search.brave.com"
            components.path = "/api/suggest"
            components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "rich", value: "false")]
        }
        return components.url
    }

    private static func parseSuggestions(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var candidates: [String] = []

        // Google, Bing, Brave and Startpage commonly return [query, [suggestions]].
        if let pair = json as? [Any], pair.count > 1, let suggestions = pair[1] as? [String] {
            candidates = suggestions
        } else if let array = json as? [Any] {
            for entry in array {
                if let text = entry as? String {
                    candidates.append(text)
                } else if let pair = entry as? [Any], let suggestions = pair.last as? [Any] {
                    candidates.append(contentsOf: suggestions.compactMap { $0 as? String })
                } else if let list = entry as? [Any] {
                    candidates.append(contentsOf: list.compactMap { $0 as? String })
                } else if let object = entry as? [String: Any], let phrase = object["phrase"] as? String {
                    candidates.append(phrase)
                }
            }
        } else if let object = json as? [String: Any], let suggestions = object["suggestions"] as? [String] {
            candidates = suggestions
        }

        var seen = Set<String>()
        return candidates.filter {
            let text = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !text.isEmpty && seen.insert(text.lowercased()).inserted
        }.prefix(6).map { $0 }
    }
}
