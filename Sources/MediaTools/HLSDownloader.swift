import AVFoundation
import Foundation

/// Downloads an HLS (.m3u8) playlist: picks the highest variant, fetches every segment
/// in parallel, concatenates them and remuxes the result to .mp4.
enum HLSDownloader {

    enum HLSError: LocalizedError {
        case badPlaylist
        case noSegments
        case segment(Int)

        var errorDescription: String? {
            switch self {
            case .badPlaylist: return "That stream is not a readable HLS playlist."
            case .noSegments: return "The playlist contains no segments."
            case .segment(let index): return "Segment \(index) failed to download."
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
        fetchText(url, cookies: cookies) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let text):
                if text.contains("#EXT-X-STREAM-INF") {
                    guard let variant = bestVariant(in: text, base: url) else {
                        completion(.failure(HLSError.badPlaylist))
                        return
                    }
                    download(playlist: variant.url, cookies: cookies, progress: progress, completion: completion)
                } else {
                    downloadSegments(in: text, base: url, cookies: cookies, progress: progress, completion: completion)
                }
            }
        }
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

    // MARK: - Download

    private static let maxConcurrent = 4

    private static func downloadSegments(
        in text: String,
        base: URL,
        cookies: [HTTPCookie],
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let urls = segments(in: text, base: base)
        guard !urls.isEmpty else {
            completion(.failure(HLSError.noSegments))
            return
        }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hls-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        var downloaded = 0
        let lock = NSLock()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.magdy.hls", attributes: .concurrent)
        let semaphore = DispatchSemaphore(value: maxConcurrent)

        for (index, segmentURL) in urls.enumerated() {
            group.enter()
            queue.async {
                semaphore.wait()
                defer {
                    semaphore.signal()
                    group.leave()
                }
                let fileURL = workDir.appendingPathComponent("\(index).part")
                fetchData(segmentURL, cookies: cookies) { result in
                    switch result {
                    case .success(let data):
                        try? data.write(to: fileURL)
                    case .failure:
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                    lock.lock()
                    downloaded += 1
                    let ratio = Double(downloaded) / Double(urls.count)
                    lock.unlock()
                    DispatchQueue.main.async { progress(ratio) }
                }
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            // Merge the parts in playlist order.
            let merged = workDir.appendingPathComponent("merged.ts")
            FileManager.default.createFile(atPath: merged.path, contents: nil)
            guard let handle = try? FileHandle(forWritingTo: merged) else {
                completion(.failure(HLSError.badPlaylist))
                return
            }
            for index in 0..<urls.count {
                let part = workDir.appendingPathComponent("\(index).part")
                if let data = try? Data(contentsOf: part) {
                    handle.write(data)
                }
            }
            handle.closeFile()

            let output = DownloadManager.shared.directory
                .appendingPathComponent("video-\(Int(Date().timeIntervalSince1970)).mp4")
            remux(merged: merged, output: output) { result in
                try? FileManager.default.removeItem(at: workDir)
                completion(result)
            }
        }
    }

    private static func remux(merged: URL, output: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        let asset = AVURLAsset(url: merged)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            completion(.success(merged))
            return
        }
        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.exportAsynchronously {
            DispatchQueue.main.async {
                if session.status == .completed {
                    completion(.success(output))
                } else {
                    // Keep the raw MPEG-TS stream when the remux fails.
                    let fallback = output.deletingPathExtension().appendingPathExtension("ts")
                    try? FileManager.default.moveItem(at: merged, to: fallback)
                    completion(.success(fallback))
                }
            }
        }
    }

    // MARK: - Networking

    private static func fetchText(_ url: URL, cookies: [HTTPCookie], completion: @escaping (Result<String, Error>) -> Void) {
        fetchData(url, cookies: cookies) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let data):
                completion(.success(String(data: data, encoding: .utf8) ?? ""))
            }
        }
    }

    private static func fetchData(_ url: URL, cookies: [HTTPCookie], completion: @escaping (Result<Data, Error>) -> Void) {
        var request = URLRequest(url: url)
        let host = url.host ?? ""
        let matching = cookies.filter {
            let domain = $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == domain || host.hasSuffix(".\(domain)")
        }
        if !matching.isEmpty, let header = HTTPCookie.requestHeaderFields(with: matching)["Cookie"] {
            request.setValue(header, forHTTPHeaderField: "Cookie")
        }
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                completion(.failure(HLSError.segment(http.statusCode)))
                return
            }
            completion(.success(data ?? Data()))
        }.resume()
    }
}
