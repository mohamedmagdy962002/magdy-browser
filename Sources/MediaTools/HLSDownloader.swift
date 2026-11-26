import AVFoundation
import Foundation

final class HLSRequest {
    private let lock = NSLock()
    private var cancelled = false
    private var completed = false
    private var tasks: [URLSessionTask] = []
    private var cancellationHandlers: [UUID: () -> Void] = [:]
    private let completion: (Result<URL, Error>) -> Void

    init(completion: @escaping (Result<URL, Error>) -> Void) {
        self.completion = completion
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func add(_ task: URLSessionTask) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled, !completed else { return false }
        tasks.append(task)
        return true
    }

    func remove(_ task: URLSessionTask) {
        lock.lock()
        tasks.removeAll { $0 === task }
        lock.unlock()
    }

    func addCancellationHandler(_ handler: @escaping () -> Void) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled, !completed else { return nil }
        let id = UUID()
        cancellationHandlers[id] = handler
        return id
    }

    func removeCancellationHandler(_ id: UUID) {
        lock.lock()
        cancellationHandlers.removeValue(forKey: id)
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        guard !cancelled, !completed else {
            lock.unlock()
            return
        }
        cancelled = true
        let tasks = self.tasks
        let handlers = Array(cancellationHandlers.values)
        self.tasks.removeAll()
        cancellationHandlers.removeAll()
        lock.unlock()

        tasks.forEach { $0.cancel() }
        handlers.forEach { $0() }
        finish(.failure(HLSError.cancelled))
    }

    func finish(_ result: Result<URL, Error>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()
        DispatchQueue.main.async { self.completion(result) }
    }
}

/// Downloads an HLS (.m3u8) playlist: picks the highest variant, fetches every segment
/// in parallel, concatenates them and remuxes the result to .mp4.
enum HLSDownloader {

    enum HLSError: LocalizedError {
        case badPlaylist
        case noSegments
        case segment(Int)
        case httpStatus(Int)
        case invalidResponse
        case missingPart(Int)
        case cancelled
        case exportFailed(String)
        case missingOutput

        var errorDescription: String? {
            switch self {
            case .badPlaylist: return "That stream is not a readable HLS playlist."
            case .noSegments: return "The playlist contains no segments."
            case .segment(let index): return "Segment \(index) failed to download."
            case .httpStatus(let status): return "The stream server returned HTTP \(status)."
            case .invalidResponse: return "The stream server returned an invalid response."
            case .missingPart(let index): return "Segment \(index) is missing."
            case .cancelled: return "The download was cancelled."
            case .exportFailed(let message): return "Could not create the video: \(message)"
            case .missingOutput: return "The exported video is missing."
            }
        }
    }

    private struct Variant {
        let url: URL
        let bandwidth: Double
    }

    /// A selectable HLS quality (parsed from a master playlist).
    struct VariantOption {
        let label: String
        let url: URL
    }

    /// Lists the qualities of a master playlist, highest resolution first.
    /// Empty result = media playlist (single quality).
    static func variants(playlist url: URL, cookies: [HTTPCookie], completion: @escaping ([VariantOption]) -> Void) {
        fetchText(url, cookies: cookies) { result in
            switch result {
            case .failure:
                completion([])
            case .success(let text):
                guard text.contains("#EXT-X-STREAM-INF") else {
                    completion([])
                    return
                }
                var options: [VariantOption] = []
                let lines = text.components(separatedBy: .newlines)
                for (index, line) in lines.enumerated() where line.contains("#EXT-X-STREAM-INF") {
                    guard index + 1 < lines.count else { continue }
                    let candidate = lines[index + 1].trimmingCharacters(in: .whitespaces)
                    guard !candidate.isEmpty, !candidate.hasPrefix("#"),
                          let resolved = URL(string: candidate, relativeTo: url)?.absoluteURL else { continue }
                    let height = Double(
                        line.split(separator: ",")
                            .first { $0.hasPrefix("RESOLUTION=") }?
                            .replacingOccurrences(of: "RESOLUTION=", with: "")
                            .split(separator: "x").last.map(String.init) ?? ""
                    ) ?? 0
                    let bandwidth = Double(
                        line.split(separator: ",")
                            .first { $0.hasPrefix("BANDWIDTH=") }?
                            .replacingOccurrences(of: "BANDWIDTH=", with: "") ?? "0"
                    ) ?? 0
                    let label = height > 0
                        ? "\(Int(height))p"
                        : String(format: "%.1f Mbps", bandwidth / 1_000_000)
                    options.append(VariantOption(label: label, url: resolved))
                }
                completion(options)
            }
        }
    }

    static func download(
        playlist url: URL,
        cookies: [HTTPCookie],
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        startDownload(playlist: url, cookies: cookies, progress: progress, completion: completion)
    }

    @discardableResult
    static func startDownload(
        playlist url: URL,
        cookies: [HTTPCookie],
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) -> HLSRequest {
        let request = HLSRequest(completion: completion)
        download(playlist: url, cookies: cookies, request: request, progress: progress)
        return request
    }

    // MARK: - Playlist parsing

    private static func bestVariant(in text: String, base: URL) -> Variant? {
        var best: Variant?
        let lines = text.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() where line.contains("#EXT-X-STREAM-INF") {
            let bandwidth = Double(
                line.split(separator: ",")
                    .first { $0.hasPrefix("BANDWIDTH=") }?
                    .replacingOccurrences(of: "BANDWIDTH=", with: "") ?? "0"
            ) ?? 0
            guard index + 1 < lines.count else { continue }
            let candidate = lines[index + 1].trimmingCharacters(in: .whitespaces)
            guard !candidate.isEmpty, !candidate.hasPrefix("#"),
                  let resolved = URL(string: candidate, relativeTo: base)?.absoluteURL else { continue }
            if best == nil || bandwidth > best!.bandwidth {
                best = Variant(url: resolved, bandwidth: bandwidth)
            }
        }
        return best
    }

    private static func segments(in text: String, base: URL) -> [URL] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap { URL(string: $0, relativeTo: base)?.absoluteURL }
    }

    private static func initializationURL(in text: String, base: URL) -> URL? {
        for line in text.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("#EXT-X-MAP:") else { continue }
            let marker = "URI=\""
            guard let start = line.range(of: marker),
                  let end = line[start.upperBound...].firstIndex(of: "\"") else { continue }
            let value = String(line[start.upperBound..<end])
            return URL(string: value, relativeTo: base)?.absoluteURL
        }
        return nil
    }

    // MARK: - Download

    private static let maxConcurrent = 4

    private static func download(
        playlist url: URL,
        cookies: [HTTPCookie],
        request: HLSRequest,
        progress: @escaping (Double) -> Void
    ) {
        guard !request.isCancelled else {
            request.finish(.failure(HLSError.cancelled))
            return
        }
        fetchText(url, cookies: cookies, request: request) { result in
            guard !request.isCancelled else {
                request.finish(.failure(HLSError.cancelled))
                return
            }
            switch result {
            case .failure(let error):
                request.finish(.failure(error))
            case .success(let text):
                if text.contains("#EXT-X-STREAM-INF") {
                    guard let variant = bestVariant(in: text, base: url) else {
                        request.finish(.failure(HLSError.badPlaylist))
                        return
                    }
                    download(playlist: variant.url, cookies: cookies, request: request, progress: progress)
                } else {
                    downloadSegments(in: text, base: url, cookies: cookies, request: request, progress: progress)
                }
            }
        }
    }

    private static func downloadSegments(
        in text: String,
        base: URL,
        cookies: [HTTPCookie],
        request: HLSRequest,
        progress: @escaping (Double) -> Void
    ) {
        let mediaURLs = segments(in: text, base: base)
        guard !mediaURLs.isEmpty else {
            request.finish(.failure(HLSError.noSegments))
            return
        }
        let initialization = initializationURL(in: text, base: base)
        let urls = initialization.map { [$0] + mediaURLs } ?? mediaURLs
        guard !request.isCancelled else {
            request.finish(.failure(HLSError.cancelled))
            return
        }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hls-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        } catch {
            request.finish(.failure(error))
            return
        }

        var finished = 0
        var errors: [Int: Error] = [:]
        let lock = NSLock()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.magdy.hls", attributes: .concurrent)
        let semaphore = DispatchSemaphore(value: maxConcurrent)

        for (index, segmentURL) in urls.enumerated() {
            group.enter()
            queue.async {
                semaphore.wait()
                guard !request.isCancelled else {
                    semaphore.signal()
                    group.leave()
                    return
                }
                let fileURL = workDir.appendingPathComponent("\(index).part")
                fetchData(segmentURL, cookies: cookies, request: request) { result in
                    defer {
                        semaphore.signal()
                        group.leave()
                    }
                    lock.lock()
                    if case .failure(let error) = result {
                        errors[index] = error
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                    finished += 1
                    let ratio = Double(finished) / Double(urls.count)
                    lock.unlock()
                    DispatchQueue.main.async {
                        if !request.isCancelled { progress(ratio) }
                    }
                    if case .success(let data) = result {
                        do {
                            try data.write(to: fileURL, options: .atomic)
                        } catch {
                            lock.lock()
                            errors[index] = error
                            lock.unlock()
                            try? FileManager.default.removeItem(at: fileURL)
                        }
                    }
                }
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            guard !request.isCancelled else {
                try? FileManager.default.removeItem(at: workDir)
                request.finish(.failure(HLSError.cancelled))
                return
            }
            lock.lock()
            let firstError = errors.min(by: { $0.key < $1.key })?.value
            lock.unlock()
            if let firstError {
                try? FileManager.default.removeItem(at: workDir)
                request.finish(.failure(firstError))
                return
            }

            let merged = workDir.appendingPathComponent("merged.ts")
            do {
                try Data().write(to: merged)
                let handle = try FileHandle(forWritingTo: merged)
                defer { try? handle.close() }
                for index in 0..<urls.count {
                    try appendPart(
                        workDir.appendingPathComponent("\(index).part"),
                        to: handle,
                        isCancelled: { request.isCancelled }
                    )
                }
                try handle.close()
            } catch {
                try? FileManager.default.removeItem(at: workDir)
                request.finish(.failure(error))
                return
            }

            guard !request.isCancelled else {
                try? FileManager.default.removeItem(at: workDir)
                request.finish(.failure(HLSError.cancelled))
                return
            }
            let rawOutput = FileManager.default.temporaryDirectory
                .appendingPathComponent("hls-output-\(UUID().uuidString).\(initialization == nil ? "ts" : "mp4")")
            do {
                try FileManager.default.moveItem(at: merged, to: rawOutput)
            } catch {
                try? FileManager.default.removeItem(at: workDir)
                request.finish(.failure(error))
                return
            }
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("hls-output-\(UUID().uuidString).mp4")
            remux(merged: rawOutput, output: output, request: request) { result in
                try? FileManager.default.removeItem(at: workDir)
                guard !request.isCancelled else {
                    try? FileManager.default.removeItem(at: rawOutput)
                    try? FileManager.default.removeItem(at: output)
                    request.finish(.failure(HLSError.cancelled))
                    return
                }
                switch result {
                case .success(let url):
                    try? FileManager.default.removeItem(at: rawOutput)
                    request.finish(.success(url))
                case .failure(let error):
                    try? FileManager.default.removeItem(at: output)
                    if isUsableRawOutput(rawOutput, fragmentedMP4: initialization != nil) {
                        request.finish(.success(rawOutput))
                    } else {
                        try? FileManager.default.removeItem(at: rawOutput)
                        request.finish(.failure(error))
                    }
                }
            }
        }
    }

    private static func isUsableRawOutput(_ url: URL, fragmentedMP4: Bool) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        guard let size = try? handle.seekToEnd(), size > (fragmentedMP4 ? 8 : 188) else {
            try? handle.close()
            return false
        }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: 0)
            let prefix = try handle.read(upToCount: 8) ?? Data()
            if fragmentedMP4 {
                return prefix.count == 8 && prefix[4] == 0x66 && prefix[5] == 0x74
                    && prefix[6] == 0x79 && prefix[7] == 0x70
            }
            return prefix.first == 0x47
        } catch {
            return false
        }
    }

    private static func appendPart(_ part: URL, to handle: FileHandle, isCancelled: () -> Bool) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: part.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw HLSError.missingPart(Int((part.deletingPathExtension().lastPathComponent as NSString).intValue))
        }
        let input = try FileHandle(forReadingFrom: part)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            if isCancelled() { throw HLSError.cancelled }
            try handle.write(contentsOf: chunk)
        }
    }

    private static func remux(
        merged: URL,
        output: URL,
        request: HLSRequest,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard !request.isCancelled else {
            completion(.failure(HLSError.cancelled))
            return
        }
        let asset = AVURLAsset(url: merged)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            completion(.failure(HLSError.exportFailed("No exporter is available for this stream.")))
            return
        }
        guard let handlerID = request.addCancellationHandler({ session.cancelExport() }) else {
            session.cancelExport()
            completion(.failure(HLSError.cancelled))
            return
        }
        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.exportAsynchronously {
            DispatchQueue.main.async {
                request.removeCancellationHandler(handlerID)
                guard !request.isCancelled else {
                    completion(.failure(HLSError.cancelled))
                    return
                }
                switch session.status {
                case .completed:
                    var isDirectory: ObjCBool = false
                    let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int64) ?? 0
                    guard FileManager.default.fileExists(atPath: output.path, isDirectory: &isDirectory),
                          !isDirectory.boolValue,
                          size > 0 else {
                        completion(.failure(HLSError.missingOutput))
                        return
                    }
                    completion(.success(output))
                case .cancelled:
                    completion(.failure(HLSError.cancelled))
                default:
                    let message = session.error?.localizedDescription ?? "Export failed."
                    completion(.failure(HLSError.exportFailed(message)))
                }
            }
        }
    }

    // MARK: - Networking

    private static func fetchText(
        _ url: URL,
        cookies: [HTTPCookie],
        request: HLSRequest? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        fetchData(url, cookies: cookies, request: request) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let data):
                guard let text = String(data: data, encoding: .utf8) else {
                    completion(.failure(HLSError.badPlaylist))
                    return
                }
                completion(.success(text))
            }
        }
    }

    private static func fetchData(
        _ url: URL,
        cookies: [HTTPCookie],
        request: HLSRequest? = nil,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        if request?.isCancelled == true {
            completion(.failure(HLSError.cancelled))
            return
        }
        var urlRequest = URLRequest(url: url)
        let matching = cookies.filter { $0.applies(to: url) }
        if !matching.isEmpty, let header = HTTPCookie.requestHeaderFields(with: matching)["Cookie"] {
            urlRequest.setValue(header, forHTTPHeaderField: "Cookie")
        }
        let completionLock = NSLock()
        var didComplete = false
        let complete: (Result<Data, Error>) -> Void = { result in
            completionLock.lock()
            guard !didComplete else {
                completionLock.unlock()
                return
            }
            didComplete = true
            completionLock.unlock()
            completion(result)
        }
        let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            request?.remove(task)
            if let error {
                complete(.failure(error))
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                complete(.failure(HLSError.httpStatus(http.statusCode)))
                return
            }
            guard let data else {
                complete(.failure(HLSError.invalidResponse))
                return
            }
            complete(.success(data))
        }
        if let request, !request.add(task) {
            task.cancel()
            complete(.failure(HLSError.cancelled))
            return
        }
        task.resume()
    }
}
