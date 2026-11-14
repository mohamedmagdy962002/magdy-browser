import Foundation

/// User-added filter list sources, downloaded and compiled by FilterListManager.
final class CustomFilterListStore {
    struct Entry: Codable {
        let id: UUID
        var name: String
        var url: String
        var addedAt: Date
    }

    static let shared = CustomFilterListStore()

    private let key = "magdy.customFilterLists"

    private(set) var entries: [Entry] = []

    init() {
        load()
    }

    func add(name: String, url: String) {
        entries.append(Entry(id: UUID(), name: name, url: url, addedAt: Date()))
        save()
    }

    func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        try? FileManager.default.removeItem(at: Self.fileURL(for: entry.id))
        save()
    }

    /// Downloads a list to Documents/filters and returns its rule text.
    func download(_ entry: Entry, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: entry.url) else {
            completion(.failure(NSError(domain: "magdy.filters", code: 1)))
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let text = data.flatMap({ String(data: $0, encoding: .utf8) }) else {
                completion(.failure(NSError(domain: "magdy.filters", code: 2)))
                return
            }
            let destination = Self.fileURL(for: entry.id)
            try? text.write(to: destination, atomically: true, encoding: .utf8)
            completion(.success(text))
        }.resume()
    }

    func storedText(for entry: Entry) -> String? {
        try? String(contentsOf: Self.fileURL(for: entry.id), encoding: .utf8)
    }

    static func fileURL(for id: UUID) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("filters", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("custom-\(id.uuidString).txt")
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
