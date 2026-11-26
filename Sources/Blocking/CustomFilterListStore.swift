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

    fileprivate static let maximumBytes = 50 * 1024 * 1024
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

    /// Downloads an HTTPS list with bounded memory, timeout, and redirect checks.
    func download(_ entry: Entry, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: entry.url), url.isWebURL,
              url.scheme?.lowercased() == "https" else {
            completion(.failure(Self.error(code: 1)))
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        BoundedDownloadDelegate(entry: entry, completion: completion).start(request: request)
    }

    func storedText(for entry: Entry) -> String? {
        guard let file = try? FileHandle(forReadingFrom: Self.fileURL(for: entry.id)) else { return nil }
        defer { try? file.close() }
        // Old downloads were unbounded, so also enforce the limit on startup reads.
        guard let data = try? file.read(upToCount: Self.maximumBytes + 1),
              data.count <= Self.maximumBytes,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    static func fileURL(for id: UUID) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("filters", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("custom-\(id.uuidString).txt")
    }

    fileprivate static func error(code: Int) -> NSError {
        NSError(domain: "magdy.filters", code: code)
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

private final class BoundedDownloadDelegate: NSObject, URLSessionDataDelegate {
    private let entry: CustomFilterListStore.Entry
    private let completion: (Result<String, Error>) -> Void
    private var session: URLSession?
    private var received = Data()
    private var finished = false

    init(entry: CustomFilterListStore.Entry, completion: @escaping (Result<String, Error>) -> Void) {
        self.entry = entry
        self.completion = completion
    }

    func start(request: URLRequest) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        session.dataTask(with: request).resume()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            finish(.failure(CustomFilterListStore.error(code: 5)))
            completionHandler(.cancel)
            return
        }
        if response.expectedContentLength > Int64(CustomFilterListStore.maximumBytes) {
            finish(.failure(CustomFilterListStore.error(code: 2)))
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.isWebURL, url.scheme?.lowercased() == "https" else {
            finish(.failure(CustomFilterListStore.error(code: 1)))
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard data.count <= CustomFilterListStore.maximumBytes - received.count else {
            finish(.failure(CustomFilterListStore.error(code: 2)))
            dataTask.cancel()
            return
        }
        received.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            let code = (error as? URLError)?.code == .timedOut ? 6 : 1
            finish(.failure(CustomFilterListStore.error(code: code)))
            return
        }
        guard received.count <= CustomFilterListStore.maximumBytes,
              let text = String(data: received, encoding: .utf8),
              !text.isEmpty,
              !text.lowercased().hasPrefix("<!doctype"),
              !text.lowercased().hasPrefix("<html"),
              FilterListManager.rules(from: text).count > 0 else {
            finish(.failure(CustomFilterListStore.error(code: 3)))
            return
        }
        do {
            try text.write(to: CustomFilterListStore.fileURL(for: entry.id), atomically: true, encoding: .utf8)
        } catch {
            finish(.failure(CustomFilterListStore.error(code: 4)))
            return
        }
        finish(.success(text))
    }

    private func finish(_ result: Result<String, Error>) {
        guard !finished else { return }
        finished = true
        session?.finishTasksAndInvalidate()
        session = nil
        received = Data()
        completion(result)
    }
}
