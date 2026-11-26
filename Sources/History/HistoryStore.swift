import Foundation
import UIKit

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
    private var generation: UInt64 = 0
    private let persistenceQueue = DispatchQueue(label: "com.magdy.history.persistence", qos: .utility)
    /// Accessed only on persistenceQueue. Older snapshots can never overwrite newer ones.
    private var writtenGeneration: UInt64 = 0

    private struct Snapshot {
        let generation: UInt64
        let entries: [HistoryEntry]
    }

    private var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("history.json")
    }

    private init() {
        load()
        NotificationCenter.default.addObserver(
            self, selector: #selector(flushForBackground), name: UIApplication.didEnterBackgroundNotification, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func record(url: URL, title: String?) {
        guard url.isWebURL else { return }
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

    /// Removes visits strictly older than the cutoff.
    func remove(olderThan cutoff: Date) {
        let previousCount = entries.count
        entries.removeAll { $0.date < cutoff }
        if entries.count != previousCount { scheduleSave() }
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

    /// Most visited domains, used for the speed dial home page. urlString is the
    /// representative visited URL, so HTTP and intranet schemes are not rewritten.
    func topDomains(limit count: Int) -> [(domain: String, title: String, visits: Int, urlString: String)] {
        guard count > 0 else { return [] }
        var visits: [String: (title: String, urlString: String, count: Int)] = [:]
        for entry in entries {
            guard let url = URL(string: entry.url), url.isWebURL,
                  let host = url.host, !host.isEmpty else { continue }
            if var current = visits[host] {
                current.count += 1
                visits[host] = current
            } else {
                visits[host] = (entry.title, entry.url, 1)
            }
        }
        return visits
            .map { (domain: $0.key, title: $0.value.title, visits: $0.value.count, urlString: $0.value.urlString) }
            .sorted { $0.visits > $1.visits }
            .prefix(count)
            .map { $0 }
    }

    // MARK: - Persistence

    /// Whole history as JSON, for backup export.
    func exportData() -> Data? {
        let snapshot = entries
        do {
            return try persistenceQueue.sync { try JSONEncoder().encode(snapshot) }
        } catch {
            return nil
        }
    }

    /// Replaces history from a backup. Returns false for undecodable data or a
    /// failed write; a failed write leaves the in-memory history unchanged.
    @discardableResult
    func restoreData(_ data: Data) -> Bool {
        guard let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data),
              decoded.count <= limit,
              decoded.allSatisfy({ URL(string: $0.url)?.isWebURL == true }) else { return false }
        let previous = entries
        pendingSave?.cancel()
        pendingSave = nil
        entries = decoded
        let snapshot = makeSnapshot()
        let saved = persistenceQueue.sync { persist(snapshot) }
        if !saved { entries = previous }
        if saved { NotificationCenter.default.post(name: .magdyLibraryChanged, object: self) }
        return saved
    }

    private func scheduleSave() {
        NotificationCenter.default.post(name: .magdyLibraryChanged, object: self)
        pendingSave?.cancel()
        let snapshot = makeSnapshot()
        let work = DispatchWorkItem { [weak self] in self?.save(snapshot) }
        pendingSave = work
        persistenceQueue.asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// Waits for earlier writes and synchronously persists the newest snapshot.
    @discardableResult
    func flush() -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        let snapshot = makeSnapshot()
        return persistenceQueue.sync { persist(snapshot) }
    }

    @objc private func flushForBackground() {
        pendingSave?.cancel()
        pendingSave = nil
        let snapshot = makeSnapshot()
        var backgroundTask: UIBackgroundTaskIdentifier = .invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "MagdyHistorySave") {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        persistenceQueue.async { [weak self] in
            self?.persist(snapshot)
            DispatchQueue.main.async {
                guard backgroundTask != .invalid else { return }
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }
    }

    private func makeSnapshot() -> Snapshot {
        generation &+= 1
        return Snapshot(generation: generation, entries: entries)
    }

    private func save(_ snapshot: Snapshot) {
        persistenceQueue.async { [weak self] in self?.persist(snapshot) }
    }

    @discardableResult
    private func persist(_ snapshot: Snapshot) -> Bool {
        guard snapshot.generation > writtenGeneration else { return true }
        do {
            let data = try JSONEncoder().encode(snapshot.entries)
            try data.write(to: fileURL, options: .atomic)
            writtenGeneration = snapshot.generation
            return true
        } catch {
            return false
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = Array(decoded.filter { URL(string: $0.url)?.isWebURL == true }.prefix(limit))
    }
}
