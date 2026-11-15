import Foundation

struct Favorite: Codable, Equatable {
    let url: String
    var title: String
    /// nil = main list. Folders group favorites; only main-list favorites reach the speed dial.
    var folder: String?

    init(url: String, title: String, folder: String? = nil) {
        self.url = url
        self.title = title
        self.folder = folder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        folder = try container.decodeIfPresent(String.self, forKey: .folder)
    }
}

final class FavoritesStore {
    static let shared = FavoritesStore()

    private(set) var favorites: [Favorite] = []

    private init() {
        load()
    }

    func add(url: URL, title: String, folder: String? = nil) {
        let entry = Favorite(
            url: url.absoluteString,
            title: title.isEmpty ? (url.host ?? url.absoluteString) : title,
            folder: folder?.trimmingCharacters(in: .whitespaces)
        )
        favorites.removeAll { $0.url == entry.url }
        favorites.insert(entry, at: 0)
        save()
    }

    func add(urlString: String, title: String, folder: String? = nil) {
        guard let url = URL(string: urlString) else { return }
        add(url: url, title: title, folder: folder)
    }

    func update(at index: Int, title: String, urlString: String, folder: String?) {
        guard favorites.indices.contains(index), URL(string: urlString) != nil else { return }
        let trimmed = folder?.trimmingCharacters(in: .whitespaces)
        favorites[index] = Favorite(url: urlString, title: title, folder: (trimmed?.isEmpty == false) ? trimmed : nil)
        save()
    }

    /// Distinct folder names in insertion order.
    func folders() -> [String] {
        var seen = Set<String>()
        var order: [String] = []
        for favorite in favorites {
            guard let folder = favorite.folder, seen.insert(folder).inserted else { continue }
            order.append(folder)
        }
        return order
    }

    func favorites(inFolder folder: String?) -> [Favorite] {
        favorites.filter { $0.folder == folder }
    }

    func move(from source: Int, to destination: Int) {
        guard favorites.indices.contains(source) else { return }
        let entry = favorites.remove(at: source)
        favorites.insert(entry, at: min(destination, favorites.count))
        save()
    }

    func remove(at index: Int) {
        guard favorites.indices.contains(index) else { return }
        favorites.remove(at: index)
        save()
    }

    func search(_ query: String) -> [Favorite] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return favorites }
        return favorites.filter {
            $0.title.localizedCaseInsensitiveContains(text) || $0.url.localizedCaseInsensitiveContains(text)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKey.favorites),
              let decoded = try? JSONDecoder().decode([Favorite].self, from: data) else { return }
        favorites = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        UserDefaults.standard.set(data, forKey: UserDefaultsKey.favorites)
    }
}
