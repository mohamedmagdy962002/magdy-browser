import Foundation

extension Notification.Name {
    static let magdyLibraryChanged = Notification.Name("magdy.libraryChanged")
}

enum LibraryItemSource: String, CaseIterable {
    case downloads, favorites, history, readingList, artifacts
}

enum LibraryMediaKind: String, CaseIterable {
    case video, audio, image, document, archive, application, article, web

    init(url: URL?) {
        guard let url else {
            self = .web
            return
        }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "m3u8", "mp4", "m4v", "mov", "webm", "mkv", "avi", "ts", "m2ts":
            self = .video
        case "mp3", "m4a", "m4b", "aac", "wav", "flac", "ogg", "opus":
            self = .audio
        case "jpg", "jpeg", "png", "heic", "gif", "webp":
            self = .image
        case "pdf", "epub", "txt", "rtf", "doc", "docx":
            self = .document
        case "zip", "rar", "7z", "tar", "gz":
            self = .archive
        case "apk", "ipa":
            self = .application
        default:
            self = .web
        }
    }

    static var fileExtensions: Set<String> = [
        "m3u8", "mp4", "m4v", "mov", "webm", "mkv", "avi", "ts", "m2ts",
        "mp3", "m4a", "m4b", "aac", "wav", "flac", "ogg", "opus",
        "jpg", "jpeg", "png", "heic", "gif", "webp",
        "pdf", "epub", "txt", "rtf", "doc", "docx",
        "zip", "rar", "7z", "tar", "gz", "apk", "ipa"
    ]
}

struct LibraryItem: Identifiable {
    enum Identity: Hashable {
        case download(UUID)
        case favorite(String)
        case history(String)
        case readingList(UUID)
        case artifact(String)

        var sortKey: String {
            switch self {
            case .download(let id): return "download:\(id.uuidString)"
            case .favorite(let url): return "favorite:\(url)"
            case .history(let url): return "history:\(url)"
            case .readingList(let id): return "reading:\(id.uuidString)"
            case .artifact(let path): return "artifact:\(path)"
            }
        }
    }

    enum Payload {
        case download(DownloadItem)
        case favorite(Favorite)
        case history(HistoryEntry)
        case reading(ReadingListStore.Item)
    }

    let id: Identity
    let title: String
    let subtitle: String?
    let kind: LibraryMediaKind
    let source: LibraryItemSource
    let date: Date
    let webURL: URL?
    let fileURL: URL?
    let fileSize: Int64
    let isAvailable: Bool
    let state: DownloadItem.State?
    let payload: Payload?

    var progress: Double? {
        guard case .download(let item) = payload else { return nil }
        return item.progress
    }
}

struct LibraryCounts {
    let downloads: Int
    let favorites: Int
    let history: Int
    let readingList: Int
    let artifacts: Int

    var total: Int {
        downloads + favorites + history + readingList + artifacts
    }
}

struct LibraryFileRecord {
    let url: URL
    let modifiedAt: Date?
    let size: Int64

    static func read(in directory: URL) -> [LibraryFileRecord] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? []
        return contents.compactMap { url in
            guard LibraryMediaKind.fileExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
                  values.isRegularFile == true else { return nil }
            return LibraryFileRecord(
                url: url,
                modifiedAt: values.contentModificationDate,
                size: Int64(values.fileSize ?? 0)
            )
        }
    }
}

struct LibrarySnapshot {
    enum SortOrder {
        case recent, name, size
    }

    let items: [LibraryItem]
    let counts: LibraryCounts

    static func make(
        downloads: [DownloadItem],
        favorites: [Favorite],
        history: [HistoryEntry],
        readingList: [ReadingListStore.Item],
        localFiles: [LibraryFileRecord],
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> LibrarySnapshot {
        var filesByPath: [String: LibraryFileRecord] = [:]
        for file in localFiles {
            let key = canonicalPath(file.url)
            guard let existing = filesByPath[key] else {
                filesByPath[key] = file
                continue
            }
            if (file.modifiedAt ?? .distantPast) > (existing.modifiedAt ?? .distantPast) {
                filesByPath[key] = file
            }
        }

        var downloadsByPath: [String: DownloadItem] = [:]
        var knownPaths = Set<String>()
        for item in downloads {
            guard let url = item.localURL else { continue }
            let key = canonicalPath(url)
            knownPaths.insert(key)
            guard let current = downloadsByPath[key] else {
                downloadsByPath[key] = item
                continue
            }
            if downloadRank(item) > downloadRank(current)
                || (downloadRank(item) == downloadRank(current) && item.id.uuidString < current.id.uuidString) {
                downloadsByPath[key] = item
            }
        }

        var result: [LibraryItem] = []
        let selectedDownloads = Set(downloadsByPath.values.map(\.id))
        let visibleDownloads = downloadsByPath.values + downloads.filter {
            $0.localURL == nil && !selectedDownloads.contains($0.id)
        }
        for item in visibleDownloads {
            let localURL = item.localURL
            let key = localURL.map(canonicalPath)
            let file = key.flatMap { filesByPath[$0] }
            let fallbackName = localURL?.lastPathComponent ?? item.sourceURL?.lastPathComponent ?? "Untitled"
            let title = item.fileName.isEmpty ? fallbackName : item.fileName
            let available = item.state == .finished && localURL.map(fileExists) == true
            result.append(LibraryItem(
                id: .download(item.id),
                title: title,
                subtitle: item.sourceURL?.host,
                kind: LibraryMediaKind(url: localURL ?? item.sourceURL),
                source: .downloads,
                date: file?.modifiedAt ?? .distantPast,
                webURL: item.sourceURL,
                fileURL: localURL,
                fileSize: file?.size ?? max(item.totalBytes, 0),
                isAvailable: available,
                state: item.state,
                payload: .download(item)
            ))
        }

        var seenFavorites = Set<String>()
        for favorite in favorites {
            guard let url = URL(string: favorite.url), url.isWebURL,
                  seenFavorites.insert(favorite.url).inserted else { continue }
            result.append(LibraryItem(
                id: .favorite(favorite.url),
                title: favorite.title,
                subtitle: favorite.folder ?? url.host,
                kind: LibraryMediaKind(url: url),
                source: .favorites,
                date: .distantPast,
                webURL: url,
                fileURL: nil,
                fileSize: 0,
                isAvailable: true,
                state: nil,
                payload: .favorite(favorite)
            ))
        }

        var seenHistory = Set<String>()
        for entry in history {
            guard let url = URL(string: entry.url), url.isWebURL,
                  seenHistory.insert(entry.url).inserted else { continue }
            result.append(LibraryItem(
                id: .history(entry.url),
                title: entry.title,
                subtitle: url.host,
                kind: LibraryMediaKind(url: url),
                source: .history,
                date: entry.date,
                webURL: url,
                fileURL: nil,
                fileSize: 0,
                isAvailable: true,
                state: nil,
                payload: .history(entry)
            ))
        }

        var seenReading = Set<UUID>()
        for item in readingList {
            guard seenReading.insert(item.id).inserted else { continue }
            result.append(LibraryItem(
                id: .readingList(item.id),
                title: item.title,
                subtitle: URL(string: item.url)?.host,
                kind: .article,
                source: .readingList,
                date: item.addedAt,
                webURL: URL(string: item.url).flatMap { $0.isWebURL ? $0 : nil },
                fileURL: nil,
                fileSize: 0,
                isAvailable: !item.paragraphs.isEmpty,
                state: nil,
                payload: .reading(item)
            ))
        }

        for file in filesByPath.values {
            let key = canonicalPath(file.url)
            guard !knownPaths.contains(key), fileExists(file.url) else { continue }
            result.append(LibraryItem(
                id: .artifact(key),
                title: file.url.deletingPathExtension().lastPathComponent,
                subtitle: file.url.pathExtension.uppercased(),
                kind: LibraryMediaKind(url: file.url),
                source: .artifacts,
                date: file.modifiedAt ?? .distantPast,
                webURL: nil,
                fileURL: file.url,
                fileSize: file.size,
                isAvailable: true,
                state: nil,
                payload: nil
            ))
        }

        let counts = LibraryCounts(
            downloads: result.filter { $0.source == .downloads }.count,
            favorites: result.filter { $0.source == .favorites }.count,
            history: result.filter { $0.source == .history }.count,
            readingList: result.filter { $0.source == .readingList }.count,
            artifacts: result.filter { $0.source == .artifacts }.count
        )
        return LibrarySnapshot(items: result.sorted { ordered($0, $1, sort: .recent) }, counts: counts)
    }

    func items(query: String = "", sources: Set<LibraryItemSource>? = nil, sort: SortOrder = .recent) -> [LibraryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            guard sources?.contains(item.source) ?? true else { return false }
            guard !trimmed.isEmpty else { return true }
            return [item.title, item.subtitle, item.webURL?.absoluteString, item.fileURL?.path]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }.sorted { ordered($0, $1, sort: sort) }
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func downloadRank(_ item: DownloadItem) -> Int {
        switch item.state {
        case .finished: return 5
        case .running: return 4
        case .paused: return 3
        case .queued: return 2
        case .failed: return 1
        case .cancelled: return 0
        }
    }

    private static func ordered(_ lhs: LibraryItem, _ rhs: LibraryItem, sort: SortOrder) -> Bool {
        switch sort {
        case .recent where lhs.date != rhs.date:
            return lhs.date > rhs.date
        case .name where lhs.title.localizedStandardCompare(rhs.title) != .orderedSame:
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        case .size where lhs.fileSize != rhs.fileSize:
            return lhs.fileSize > rhs.fileSize
        default:
            return lhs.id.sortKey < rhs.id.sortKey
        }
    }
}
