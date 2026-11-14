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
    /// Caps the response at 50 MB so a bad URL can't exhaust memory.
    func download(_ entry: Entry, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: entry.url) else {
            completion(.failure(NSError(domain: "magdy.filters", code: 1)))
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, error in
            let failure = { (code: Int) in completion(.failure(NSError(domain: "magdy.filters", code: code))) }
            if error != nil { failure(1); return }
            guard let data, data.count <= 50 * 1024 * 1024 else { failure(2); return }
            guard let text = String(data: data, encoding: .utf8) else { failure(2); return }
            // Reject HTML error pages / empty downloads — a silent empty rule list
            // would look "added" while blocking nothing.
            guard !text.isEmpty,
                  !text.lowercased().hasPrefix("<!doctype"),
                  !text.lowercased().hasPrefix("<html"),
                  FilterListManager.rules(from: text).count > 0 else { failure(3); return }
            do {
                try text.write(to: Self.fileURL(for: entry.id), atomically: true, encoding: .utf8)
            } catch {
                failure(4)
                return
            }
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
