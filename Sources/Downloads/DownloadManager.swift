import Foundation
import UIKit
import WebKit

final class DownloadItem {
    enum State: String {
        case queued, running, paused, finished, failed, cancelled
    }

    let id = UUID()
    var fileName: String = ""
    var sourceURL: URL?
    var state: State = .queued
    var progress: Double = 0
    var bytesWritten: Int64 = 0
    var totalBytes: Int64 = 0
    var errorMessage: String?
    var localURL: URL?
    var cancel: (() -> Void)?
    var task: URLSessionDownloadTask?
    var resumeData: Data?
    /// Bytes already on disk before the current resume session (for correct totals).
    var resumeBaseBytes: Int64 = 0
}

/// Unlimited download queue: no count cap, no speed cap, no subscription gate.
final class DownloadManager: NSObject {
    static let shared = DownloadManager()

    private(set) var items: [DownloadItem] = []
    var onChange: (() -> Void)?

    private var downloadItems: [ObjectIdentifier: DownloadItem] = [:]
    private var pendingSourceURL: [ObjectIdentifier: URL] = [:]
    private var taskItems: [Int: DownloadItem] = [:]
    private var hlsItems: [UUID: DownloadItem] = [:]
    private var timers: [UUID: Timer] = [:]

    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Downloads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Public API

    /// WebKit download (page-initiated).
    func attach(download: WKDownload, url: URL?) {
        download.delegate = self
        if let url {
            pendingSourceURL[ObjectIdentifier(download)] = url
        }
    }

    /// Direct media link download (video/audio/file found on the page).
    func start(url: URL, referer: URL?, cookies: [HTTPCookie]) {
        var request = URLRequest(url: url)
        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
        let host = url.host ?? ""
        let matching = cookies.filter {
            let domain = $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == domain || host.hasSuffix(".\(domain)")
        }
        if !matching.isEmpty, let header = HTTPCookie.requestHeaderFields(with: matching)["Cookie"] {
            request.setValue(header, forHTTPHeaderField: "Cookie")
        }

        let item = DownloadItem()
        item.fileName = uniqueName(url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent)
        item.sourceURL = url
        item.state = .running

        let task = session.downloadTask(with: request)
        taskItems[task.taskIdentifier] = item
        item.task = task
        item.cancel = { task.cancel() }
        insert(item)
        task.resume()
    }

    /// HLS playlist download: all segments are fetched, merged and remuxed to .mp4.
    func startHLS(url: URL, referer: URL?, cookies: [HTTPCookie]) {
        let item = DownloadItem()
        item.fileName = uniqueName(url.deletingPathExtension().lastPathComponent + ".mp4")
        item.sourceURL = url
        item.state = .running
        hlsItems[item.id] = item
        insert(item)

        HLSDownloader.download(
            playlist: url,
            cookies: cookies,
            progress: { [weak self] value in
                item.progress = value
                self?.notify()
            },
            completion: { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let fileURL):
                    let destination = self.directory.appendingPathComponent(self.uniqueName(item.fileName))
                    try? FileManager.default.removeItem(at: destination)
                    do {
                        try FileManager.default.moveItem(at: fileURL, to: destination)
                        item.localURL = destination
                        item.fileName = destination.lastPathComponent
                    } catch {
                        item.localURL = fileURL
                    }
                    item.state = .finished
                    item.progress = 1
                case .failure(let error):
                    item.state = .failed
                    item.errorMessage = error.localizedDescription
                }
                self.hlsItems.removeValue(forKey: item.id)
                self.notify()
            }
        )
    }

    func cancel(_ item: DownloadItem) {
        item.cancel?()
        item.cancel = nil
        item.state = .cancelled
        stopPolling(item)
        notify()
    }

    /// Pauses a direct download, keeping resume data for `resume(item:)`.
    func pause(_ item: DownloadItem) {
        guard let task = item.task, item.state == .running else { return }
        item.resumeData = nil
        // Base offset so progress after resume counts the bytes already saved.
        item.resumeBaseBytes = item.bytesWritten
        task.cancel(byProducingResumeData: { [weak self, weak item] data in
            guard let self, let item else { return }
            item.resumeData = data
            item.state = .paused
            self.stopPolling(item)
            self.notify()
        })
    }

    /// Resumes a paused download from its stored resume data.
    func resume(_ item: DownloadItem) {
        guard let data = item.resumeData, item.state == .paused || item.state == .failed || item.state == .cancelled else { return }
        item.resumeData = nil
        item.state = .running
        let task = session.downloadTask(withResumeData: data)
        taskItems[task.taskIdentifier] = item
        item.task = task
        item.cancel = { task.cancel() }
        notify()
        task.resume()
    }

    func remove(_ item: DownloadItem) {
        cancel(item)
        if let localURL = item.localURL {
            try? FileManager.default.removeItem(at: localURL)
        }
        items.removeAll { $0 === item }
        notify()
    }

    func clearFinished() {
        for item in items where item.state == .finished || item.state == .failed || item.state == .cancelled {
            if let localURL = item.localURL { try? FileManager.default.removeItem(at: localURL) }
        }
        items.removeAll { $0.state == .finished || $0.state == .failed || $0.state == .cancelled }
        notify()
    }

    // MARK: - Internals

    private func insert(_ item: DownloadItem) {
        items.insert(item, at: 0)
        notify()
    }

    private func notify() {
        DispatchQueue.main.async { [weak self] in
            self?.onChange?()
        }
    }

    private func uniqueName(_ proposed: String) -> String {
        let cleaned = proposed
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cleaned.isEmpty ? "download" : cleaned
        var candidate = name
        var counter = 1
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            let ext = (name as NSString).pathExtension
            let base = (name as NSString).deletingPathExtension
            candidate = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            counter += 1
        }
        return candidate
    }

    private func startPolling(_ item: DownloadItem) {
        stopPolling(item)
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self, weak item] _ in
            guard let self, let item, let localURL = item.localURL else { return }
            let size = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? nil
            guard let size else { return }
            item.bytesWritten = size
            if item.totalBytes > 0 {
                item.progress = min(1, Double(size) / Double(item.totalBytes))
            }
            self.notify()
        }
        timers[item.id] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPolling(_ item: DownloadItem) {
        timers[item.id]?.invalidate()
        timers[item.id] = nil
    }
}

// MARK: - WKDownload (page downloads)

extension DownloadManager: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let key = ObjectIdentifier(download)
        let item = DownloadItem()
        item.fileName = uniqueName(suggestedFilename)
        item.sourceURL = pendingSourceURL[key]
        item.totalBytes = response.expectedContentLength
        item.state = .running

        let destination = directory.appendingPathComponent(item.fileName)
        item.localURL = destination
        downloadItems[key] = item
        pendingSourceURL.removeValue(forKey: key)
        item.cancel = { download.cancel { _ in } }

        insert(item)
        completionHandler(destination)
        startPolling(item)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        if let item = downloadItems.removeValue(forKey: key) {
            item.state = .finished
            item.progress = 1
            stopPolling(item)
        }
        notify()
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let key = ObjectIdentifier(download)
        if let item = downloadItems.removeValue(forKey: key) {
            item.state = .failed
            item.errorMessage = error.localizedDescription
            stopPolling(item)
        }
        notify()
    }
}

// MARK: - URLSession (direct media links)

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let item = taskItems[downloadTask.taskIdentifier] else { return }
        let base = item.resumeBaseBytes
        item.bytesWritten = base + totalBytesWritten
        item.totalBytes = base + totalBytesExpectedToWrite
        if item.totalBytes > 0 {
            item.progress = min(1, Double(item.bytesWritten) / Double(item.totalBytes))
        }
        notify()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let item = taskItems[downloadTask.taskIdentifier] else { return }
        taskItems.removeValue(forKey: downloadTask.taskIdentifier)
        // Resolve the name now — two concurrent same-name downloads would
        // otherwise both be told the same destination.
        let destination = directory.appendingPathComponent(uniqueName(item.fileName))
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            item.localURL = destination
            item.fileName = destination.lastPathComponent
            item.state = .finished
            item.progress = 1
        } catch {
            item.state = .failed
            item.errorMessage = error.localizedDescription
        }
        notify()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { taskItems.removeValue(forKey: task.taskIdentifier) }
        guard let error, let item = taskItems[task.taskIdentifier] else { return }
        if (error as NSError).code == NSURLErrorCancelled {
            // Pause keeps the resume data so the download can continue later.
            if item.resumeData != nil {
                item.state = .paused
            } else {
                item.state = .cancelled
                item.errorMessage = error.localizedDescription
            }
        } else {
            item.state = .failed
            item.errorMessage = error.localizedDescription
        }
        notify()
    }
}
