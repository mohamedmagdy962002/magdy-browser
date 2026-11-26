import Foundation

final class ReadingListStore {
    struct Item: Codable {
        let id: UUID
        var title: String
        var url: String
        var paragraphs: [String]
        var addedAt: Date
    }

    static let shared = ReadingListStore()

    private let key = "magdy.readingList"
    private(set) var items: [Item] = []

    init() {
        load()
    }

    func add(title: String, url: String, paragraphs: [String]) {
        let item = Item(id: UUID(), title: title, url: url, paragraphs: paragraphs, addedAt: Date())
        items.insert(item, at: 0)
        save()
        NotificationCenter.default.post(name: .magdyLibraryChanged, object: self)
    }

    func remove(_ item: Item) {
        let previousCount = items.count
        items.removeAll { $0.id == item.id }
        guard items.count != previousCount else { return }
        save()
        NotificationCenter.default.post(name: .magdyLibraryChanged, object: self)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Item].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func reloadFromDisk() {
        load()
        NotificationCenter.default.post(name: .magdyLibraryChanged, object: self)
    }
}
