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

    func remove(at index: Int) {
        guard favorites.indices.contains(index) else { return }
        favorites.remove(at: index)
        save()
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
