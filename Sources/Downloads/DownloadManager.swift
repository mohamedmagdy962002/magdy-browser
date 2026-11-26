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
    /// Keeps a custom folder's security scope active while its finished file is in the queue.
    var scopedFolder: URL?
    var cancel: (() -> Void)?
    var task: URLSessionDownloadTask?
    var resumeData: Data?
    var hasReservedDestination = false
    /// Bytes already on disk before the current resume session (for correct totals).
    var resumeBaseBytes: Int64 = 0
    var generation: UInt64 = 0
    var isPausing = false
}

enum DownloadError: LocalizedError {
    case invalidFileName(String)
    case missingFile(String)
    case deliveryFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFileName(let name): return "Invalid download name: \(name)"
        case .missingFile(let name): return "The downloaded file \(name) is missing."
        case .deliveryFailed(let message): return "Could not save the download: \(message)"
        }
    }
}

enum DownloadDestinationAllocator {
    private static let lock = NSLock()
    private static var reserved: Set<String> = []

    static func availableName(_ proposed: String, in folder: URL, reserve: Bool) -> String {
        lock.lock()
        defer { lock.unlock() }

        var candidate = proposed
        var counter = 1
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path)
                || reserved.contains(reservationKey(folder.appendingPathComponent(candidate))) {
            let ext = (proposed as NSString).pathExtension
            let base = (proposed as NSString).deletingPathExtension
            let suffix = ext.isEmpty ? " (\(counter))" : " (\(counter)).\(ext)"
            if suffix.utf8.count >= 255 {
                candidate = "download-\(counter)"
            } else {
                let shortenedBase = prefixFitting(base, maxBytes: 255 - suffix.utf8.count)
                candidate = shortenedBase + suffix
            }
            counter += 1
        }
        if reserve {
            reserved.insert(reservationKey(folder.appendingPathComponent(candidate)))
        }
        return candidate
    }

    static func release(_ destination: URL) {
        lock.lock()
        reserved.remove(reservationKey(destination))
        lock.unlock()
    }

    private static func reservationKey(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func prefixFitting(_ value: String, maxBytes: Int) -> String {
        guard maxBytes > 0 else { return "" }
        var result = ""
        for character in value {
            result.append(character)
            if result.utf8.count > maxBytes {
                result.removeLast()
                break
            }
        }
        return result
    }
}

/// Unlimited download queue: no count cap, no speed cap, no subscription gate.
final class DownloadManager: NSObject {
    static let shared = DownloadManager()

    private(set) var items: [DownloadItem] = []
    var onChange: (() -> Void)?

    private var downloadItems: [ObjectIdentifier: DownloadItem] = [:]
    private var pendingSourceURL: [ObjectIdentifier: URL] = [:]
    private var scopedDownloadFolders: [ObjectIdentifier: URL] = [:]
    private var taskItems: [Int: DownloadItem] = [:]
    private var hlsItems: [UUID: DownloadItem] = [:]
    private var timers: [UUID: Timer] = [:]

    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue.main)

    /// Security-scoped bookmark of the user-chosen download folder (nil = app Downloads).
    static let folderBookmarkKey = "magdy.downloadFolderBookmark"

    var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Downloads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// The folder new files land in: the user's chosen folder when reachable, else Downloads.
    func folderDisplayName() -> String {
        guard let folder = resolveCustomFolder() else { return "Magdy Downloads" }
        defer { folder.stopAccessingSecurityScopedResource() }
        return customFolderName ?? "Magdy Downloads"
    }

    private var customFolderName: String? {
        UserDefaults.standard.string(forKey: Self.folderBookmarkKey + ".name")
    }

    /// Resolves the bookmarked folder; caller must balance startAccessingSecurityScopedResource.
    private func resolveCustomFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.folderBookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else {
            return nil
        }
        return url
    }

    private func downloadDirectory() throws -> URL {
        let folder = directory
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw DownloadError.deliveryFailed("Downloads is not a folder.") }
        } else {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    private func withDeliveryFolder<T>(_ body: (URL) throws -> T) throws -> T {
        if let folder = resolveCustomFolder() {
            defer { folder.stopAccessingSecurityScopedResource() }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return try body(folder)
            }
        }
        return try body(try downloadDirectory())
    }

    private func removeDeliveredFile(_ item: DownloadItem) {
        if let url = item.localURL {
            try? FileManager.default.removeItem(at: url)
        }
        item.scopedFolder?.stopAccessingSecurityScopedResource()
        item.scopedFolder = nil
    }

    /// Moves a finished temp file to the chosen folder (or Downloads) with a unique name.
    private func deliver(_ temp: URL, name: String, item: DownloadItem) throws -> URL {
        var scopedFolder = resolveCustomFolder()
        if let folder = scopedFolder {
            var isDirectory: ObjCBool = false
            if !FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
                folder.stopAccessingSecurityScopedResource()
                scopedFolder = nil
            }
        }
        let folder: URL
        if let scopedFolder {
            folder = scopedFolder
        } else {
            folder = try downloadDirectory()
        }
        var retainsScope = false
        defer { if !retainsScope { scopedFolder?.stopAccessingSecurityScopedResource() } }

        let target = try reserveDestination(name: name, in: folder)
        defer { releaseDestination(target) }

        var moved = false
        do {
            try FileManager.default.moveItem(at: temp, to: target)
            moved = true
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                throw DownloadError.missingFile(target.lastPathComponent)
            }
            item.scopedFolder?.stopAccessingSecurityScopedResource()
            item.scopedFolder = scopedFolder
            retainsScope = true
            return target
        } catch {
            if moved { try? FileManager.default.removeItem(at: target) }
            if error is DownloadError { throw error }
            throw DownloadError.deliveryFailed(error.localizedDescription)
        }
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
    func start(url: URL, referer: URL?, cookies: [HTTPCookie], fileName: String? = nil) {
        var request = URLRequest(url: url)
        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
        let matching = cookies.filter { $0.applies(to: url) }
        if !matching.isEmpty, let header = HTTPCookie.requestHeaderFields(with: matching)["Cookie"] {
            request.setValue(header, forHTTPHeaderField: "Cookie")
        }

        let proposed = fileName.flatMap { $0.isEmpty ? nil : $0 }
            ?? (url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent)
        let item = DownloadItem()
        item.sourceURL = url
        item.generation = 1
        do {
            item.fileName = try withDeliveryFolder { try uniqueName(proposed, in: $0) }
        } catch {
            item.fileName = proposed
            item.state = .failed
            item.errorMessage = error.localizedDescription
            insert(item)
            return
        }
        item.state = .running

        let task = session.downloadTask(with: request)
        taskItems[task.taskIdentifier] = item
        item.task = task
        item.cancel = { task.cancel() }
        insert(item)
        task.resume()
    }

    /// HLS playlist download: all segments are fetched, merged and remuxed to .mp4.
    func startHLS(url: URL, referer: URL?, cookies: [HTTPCookie], fileName: String? = nil) {
        let proposed = fileName.flatMap { $0.isEmpty ? nil : $0 }
            ?? (url.deletingPathExtension().lastPathComponent + ".mp4")
        let item = DownloadItem()
        item.sourceURL = url
        item.generation = 1
        do {
            item.fileName = try withDeliveryFolder { try uniqueName(proposed, in: $0) }
        } catch {
            item.fileName = proposed
            item.state = .failed
            item.errorMessage = error.localizedDescription
            insert(item)
            return
        }
        item.state = .running
        hlsItems[item.id] = item
        insert(item)

        let request = HLSDownloader.startDownload(
            playlist: url,
            cookies: cookies,
            progress: { [weak self] value in
                item.progress = value
                self?.notify()
            },
            completion: { [weak self] result in
                guard let self else { return }
                self.hlsItems.removeValue(forKey: item.id)
                guard item.state == .running else {
                    if case .success(let fileURL) = result { try? FileManager.default.removeItem(at: fileURL) }
                    self.notify()
                    return
                }
                switch result {
                case .success(let fileURL):
                    let base = (item.fileName as NSString).deletingPathExtension
                    let fileExtension = fileURL.pathExtension.lowercased() == "ts" ? "ts" : "mp4"
                    do {
                        let destination = try self.deliver(fileURL, name: base + "." + fileExtension, item: item)
                        item.localURL = destination
                        item.fileName = destination.lastPathComponent
                        item.state = .finished
                        item.progress = 1
                    } catch {
                        try? FileManager.default.removeItem(at: fileURL)
                        item.state = .failed
                        item.errorMessage = error.localizedDescription
                    }
                case .failure(let error):
                    if let hlsError = error as? HLSDownloader.HLSError, case .cancelled = hlsError {
                        item.state = .cancelled
                    } else {
                        item.state = .failed
                        item.errorMessage = error.localizedDescription
                    }
                }
                item.cancel = nil
                self.notify()
            }
        )
        item.cancel = { request.cancel() }
    }

    func cancel(_ item: DownloadItem) {
        guard item.state != .finished, item.state != .cancelled else { return }
        item.state = .cancelled
        item.errorMessage = nil
        item.generation &+= 1
        item.isPausing = false
        item.resumeData = nil

        if hlsItems.removeValue(forKey: item.id) != nil {
            let cancel = item.cancel
            item.cancel = nil
            cancel?()
        } else if let task = item.task {
            taskItems.removeValue(forKey: task.taskIdentifier)
            item.task = nil
            item.cancel = nil
            task.cancel()
        } else {
            item.cancel?()
            item.cancel = nil
        }
        stopPolling(item)
        notify()
    }

    /// Pauses a direct download, keeping resume data for `resume(item:)`.
    func pause(_ item: DownloadItem) {
        guard let task = item.task, item.state == .running, !item.isPausing else { return }
        item.generation &+= 1
        let generation = item.generation
        let taskIdentifier = task.taskIdentifier
        item.resumeData = nil
        item.isPausing = true
        // Base offset so progress after resume counts the bytes already saved.
        item.resumeBaseBytes = item.bytesWritten
        task.cancel(byProducingResumeData: { [weak self, weak item] data in
            guard let self, let item, item.generation == generation, item.isPausing else { return }
            item.isPausing = false
            item.task = nil
            item.cancel = nil
            self.taskItems.removeValue(forKey: taskIdentifier)
            if let data {
                item.resumeData = data
                item.state = .paused
                item.errorMessage = nil
            } else {
                item.state = .failed
                item.errorMessage = "Pause did not produce resume data."
            }
            self.notify()
        })
    }

    /// Resumes a paused download from its stored resume data.
    func resume(_ item: DownloadItem) {
        guard let data = item.resumeData,
              item.task == nil,
              !item.isPausing,
              item.state == .paused || item.state == .failed || item.state == .cancelled else { return }
        item.generation &+= 1
        item.resumeData = nil
        item.resumeBaseBytes = item.bytesWritten
        item.errorMessage = nil
        item.localURL = nil
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
        if let task = item.task {
            taskItems.removeValue(forKey: task.taskIdentifier)
            item.task = nil
        }
        hlsItems.removeValue(forKey: item.id)
        removeDeliveredFile(item)
        items.removeAll { $0 === item }
        notify()
    }

    func clearFinished() {
        for item in items where item.state == .finished || item.state == .failed || item.state == .cancelled {
            if let task = item.task {
                taskItems.removeValue(forKey: task.taskIdentifier)
                item.task = nil
            }
            hlsItems.removeValue(forKey: item.id)
            removeDeliveredFile(item)
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
            NotificationCenter.default.post(name: .magdyDownloadsChanged, object: nil)
        }
    }

    private func sanitizedName(_ proposed: String) throws -> String {
        guard !proposed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw DownloadError.invalidFileName(proposed)
        }
        let cleaned = proposed
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != ".", cleaned != "..", cleaned.utf8.count <= 255 else {
            throw DownloadError.invalidFileName(proposed)
        }
        return cleaned
    }

    private func uniqueName(_ proposed: String, in folder: URL) throws -> String {
        try availableName(proposed, in: folder, reserve: false)
    }

    private func reserveDestination(name: String, in folder: URL) throws -> URL {
        folder.appendingPathComponent(try availableName(name, in: folder, reserve: true))
    }

    private func availableName(_ proposed: String, in folder: URL, reserve: Bool) throws -> String {
        DownloadDestinationAllocator.availableName(try sanitizedName(proposed), in: folder, reserve: reserve)
    }

    private func releaseDestination(_ destination: URL) {
        DownloadDestinationAllocator.release(destination)
    }

    private func httpStatusError(_ response: URLResponse?) -> Error? {
        guard let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) else { return nil }
        return NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorBadServerResponse,
            userInfo: [NSLocalizedDescriptionKey: "The server returned HTTP \(response.statusCode)."]
        )
    }

    private func markFailed(_ item: DownloadItem, error: Error) {
        guard item.state != .cancelled else { return }
        item.state = .failed
        item.errorMessage = error.localizedDescription
        item.cancel = nil
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
        item.fileName = suggestedFilename
        item.sourceURL = pendingSourceURL[key]
        item.totalBytes = response.expectedContentLength
        var scopedFolder: URL?
        do {
            let folder: URL
            if let custom = resolveCustomFolder() {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: custom.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    folder = custom
                    scopedFolder = custom
                } else {
                    custom.stopAccessingSecurityScopedResource()
                    folder = try downloadDirectory()
                }
            } else {
                folder = try downloadDirectory()
            }
            item.fileName = try availableName(suggestedFilename, in: folder, reserve: true)
            let destination = folder.appendingPathComponent(item.fileName)
            item.localURL = destination
            item.hasReservedDestination = true
            item.state = .running
            downloadItems[key] = item
            pendingSourceURL.removeValue(forKey: key)
            if let scopedFolder {
                scopedDownloadFolders[key] = scopedFolder
            }
            item.cancel = { [weak self] in
                download.cancel { [weak self] _ in
                    self?.completeWebKitDownload(download, error: nil)
                }
            }
            insert(item)
            completionHandler(destination)
            startPolling(item)
        } catch {
            scopedFolder?.stopAccessingSecurityScopedResource()
            item.state = .failed
            item.errorMessage = error.localizedDescription
            downloadItems.removeValue(forKey: key)
            pendingSourceURL.removeValue(forKey: key)
            insert(item)
            completionHandler(nil)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        completeWebKitDownload(download, error: nil)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        completeWebKitDownload(download, error: error)
    }

    private func completeWebKitDownload(_ download: WKDownload, error: Error?) {
        let key = ObjectIdentifier(download)
        let scopedFolder = scopedDownloadFolders.removeValue(forKey: key)
        pendingSourceURL.removeValue(forKey: key)
        guard let item = downloadItems.removeValue(forKey: key) else {
            scopedFolder?.stopAccessingSecurityScopedResource()
            return
        }
        let destination = item.localURL
        var retainedFolder = false
        defer {
            if let destination, item.hasReservedDestination {
                releaseDestination(destination)
                item.hasReservedDestination = false
            }
            if !retainedFolder {
                scopedFolder?.stopAccessingSecurityScopedResource()
            }
            item.cancel = nil
            stopPolling(item)
            notify()
        }

        var isDirectory: ObjCBool = false
        let hasFile = destination.map {
            FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        } ?? false
        if item.state != .cancelled, error == nil, hasFile {
            item.state = .finished
            item.progress = 1
            item.scopedFolder?.stopAccessingSecurityScopedResource()
            item.scopedFolder = scopedFolder
            retainedFolder = true
        } else {
            if let destination {
                try? FileManager.default.removeItem(at: destination)
                item.localURL = nil
            }
            if item.state != .cancelled {
                item.state = .failed
                item.errorMessage = error?.localizedDescription
                    ?? DownloadError.missingFile(item.fileName).localizedDescription
            }
        }
    }
}

// MARK: - URLSession (direct media links)

extension Notification.Name {
    static let magdyDownloadsChanged = Notification.Name("magdyDownloadsChanged")
}

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let item = taskItems[downloadTask.taskIdentifier],
              item.task === downloadTask,
              item.state == .running,
              !item.isPausing else { return }
        if let error = httpStatusError(downloadTask.response) {
            markFailed(item, error: error)
            downloadTask.cancel()
            notify()
            return
        }
        let base = item.resumeBaseBytes
        item.bytesWritten = base + totalBytesWritten
        item.totalBytes = totalBytesExpectedToWrite >= 0 ? base + totalBytesExpectedToWrite : 0
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
        guard let item = taskItems[downloadTask.taskIdentifier],
              item.task === downloadTask,
              item.state == .running else { return }
        taskItems.removeValue(forKey: downloadTask.taskIdentifier)
        item.task = nil
        item.cancel = nil
        if item.isPausing {
            item.isPausing = false
            item.generation &+= 1
            item.resumeData = nil
        }
        if let error = httpStatusError(downloadTask.response) {
            markFailed(item, error: error)
        } else {
            do {
                let destination = try deliver(location, name: item.fileName, item: item)
                item.localURL = destination
                item.fileName = destination.lastPathComponent
                item.state = .finished
                item.progress = 1
                item.bytesWritten = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? item.bytesWritten
            } catch {
                markFailed(item, error: error)
            }
        }
        notify()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let item = taskItems.removeValue(forKey: task.taskIdentifier),
              let downloadTask = item.task,
              downloadTask === task else { return }
        item.task = nil
        item.cancel = nil
        defer { notify() }

        if item.isPausing {
            if let error, (error as NSError).code != NSURLErrorCancelled {
                item.isPausing = false
                markFailed(item, error: error)
            }
            return
        }
        guard item.state == .running else { return }
        if let error {
            if (error as NSError).code == NSURLErrorCancelled {
                item.state = .cancelled
                item.errorMessage = error.localizedDescription
            } else {
                markFailed(item, error: error)
            }
        } else if let statusError = httpStatusError(task.response) {
            markFailed(item, error: statusError)
        } else {
            markFailed(item, error: DownloadError.missingFile(item.fileName))
        }
    }
}
