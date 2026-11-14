import Foundation

struct Favorite: Codable, Equatable {
    let url: String
    var title: String
}

final class FavoritesStore {
    static let shared = FavoritesStore()

    private(set) var favorites: [Favorite] = []

    private init() {
        load()
    }

    func add(url: URL, title: String) {
        let entry = Favorite(url: url.absoluteString, title: title.isEmpty ? (url.host ?? url.absoluteString) : title)
        favorites.removeAll { $0.url == entry.url }
        favorites.insert(entry, at: 0)
        save()
    }

    func add(urlString: String, title: String) {
        guard let url = URL(string: urlString) else { return }
        add(url: url, title: title)
    }

    func update(at index: Int, title: String, urlString: String) {
        guard favorites.indices.contains(index), URL(string: urlString) != nil else { return }
        favorites[index] = Favorite(url: urlString, title: title)
        save()
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
