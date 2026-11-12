import Foundation

struct HistoryEntry: Codable, Equatable {
    let url: String
    var title: String
    let date: Date
}

/// Local browsing history. Nothing is uploaded anywhere.
final class HistoryStore {
    static let shared = HistoryStore()

    private(set) var entries: [HistoryEntry] = []
    private let limit = 5000
    private var pendingSave: DispatchWorkItem?

    private var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("history.json")
    }

    private init() {
        load()
    }

    func record(url: URL, title: String?) {
        let key = url.absoluteString
        entries.removeAll { $0.url == key }
        let name = (title?.isEmpty == false ? title! : (url.host ?? key))
        entries.insert(HistoryEntry(url: key, title: name, date: Date()), at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        scheduleSave()
    }

    func remove(at index: Int) {
        guard entries.indices.contains(index) else { return }
        entries.remove(at: index)
        scheduleSave()
    }

    func remove(where predicate: (HistoryEntry) -> Bool) {
        entries.removeAll(where: predicate)
        scheduleSave()
    }

    func clear() {
        entries.removeAll()
        scheduleSave()
    }

    func search(_ query: String) -> [HistoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        let lowered = trimmed.lowercased()
        return entries.filter {
            $0.title.lowercased().contains(lowered) || $0.url.lowercased().contains(lowered)
        }
    }

    /// Most visited domains, used for the speed dial home page.
    func topDomains(limit count: Int) -> [(domain: String, title: String, visits: Int)] {
        var visits: [String: (title: String, count: Int)] = [:]
        for entry in entries {
            guard let host = URL(string: entry.url)?.host else { continue }
            let current = visits[host] ?? (entry.title, 0)
            visits[host] = (current.0, current.1 + 1)
        }
        return visits
            .map { (domain: $0.key, title: $0.value.0, visits: $0.value.1) }
            .sorted { $0.visits > $1.visits }
            .prefix(count)
            .map { $0 }
    }

    // MARK: - Persistence

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded
    }
}
