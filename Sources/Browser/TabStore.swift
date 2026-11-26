import Foundation

final class TabStore {
    private(set) var tabs: [BrowserTab] = []

    struct SavedTab: Codable {
        let url: String
    }

    func newTab(privateMode: Bool) -> BrowserTab {
        let tab = BrowserTab(isPrivate: privateMode)
        tabs.append(tab)
        return tab
    }

    func close(_ tab: BrowserTab) {
        tabs.removeAll { $0 === tab }
        persist()
    }

    func closeAll() {
        tabs.removeAll()
        persist()
    }

    /// Persists non-private tab URLs so a killed app can offer session restore.
    /// Private tabs are never persisted.
    func persist() {
        let saved = tabs.compactMap { tab -> SavedTab? in
            guard !tab.isPrivate, let url = tab.sessionURL else { return nil }
            return SavedTab(url: url.absoluteString)
        }
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: "magdy.session")
        }
    }

    func savedSession() -> [SavedTab] {
        guard let data = UserDefaults.standard.data(forKey: "magdy.session"),
              let saved = try? JSONDecoder().decode([SavedTab].self, from: data) else { return [] }
        return saved.filter { URL.webURL(from: $0.url)?.absoluteString == $0.url }
    }

    func clearSavedSession() {
        UserDefaults.standard.removeObject(forKey: "magdy.session")
    }
}
