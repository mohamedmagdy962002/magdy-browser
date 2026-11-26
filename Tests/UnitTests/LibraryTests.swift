import XCTest
@testable import MagdyBrowser

final class LibraryTests: XCTestCase {
    func testFinishedDownloadWinsPathDeduplicationAndRetainsBackingObject() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try makeFile("movie.mp4", in: folder)
        let paused = DownloadItem()
        paused.fileName = "Paused copy"
        paused.state = .paused
        paused.localURL = file
        let finished = DownloadItem()
        finished.fileName = "Movie"
        finished.state = .finished
        finished.localURL = file
        finished.sourceURL = URL(string: "https://example.com/movie.mp4")

        let snapshot = LibrarySnapshot.make(
            downloads: [paused, finished],
            favorites: [],
            history: [],
            readingList: [],
            localFiles: [LibraryFileRecord(url: file, modifiedAt: Date(timeIntervalSince1970: 100), size: 42)]
        )

        XCTAssertEqual(snapshot.counts.downloads, 1)
        XCTAssertEqual(snapshot.counts.artifacts, 0)
        let item = try XCTUnwrap(snapshot.items.first)
        guard case .download(let id) = item.id, case .download(let backing) = item.payload else {
            return XCTFail("Expected the finished download payload")
        }
        XCTAssertEqual(id, finished.id)
        XCTAssertTrue(backing === finished)
        XCTAssertEqual(item.fileSize, 42)
        XCTAssertTrue(item.isAvailable)
    }

    func testActiveDownloadWithoutDestinationRemainsVisible() throws {
        let item = DownloadItem()
        item.fileName = "Downloading movie"
        item.state = .running
        item.totalBytes = 1_024

        let snapshot = LibrarySnapshot.make(
            downloads: [item],
            favorites: [],
            history: [],
            readingList: [],
            localFiles: []
        )

        XCTAssertEqual(snapshot.counts.downloads, 1)
        let libraryItem = try XCTUnwrap(snapshot.items.first)
        XCTAssertEqual(libraryItem.title, "Downloading movie")
        XCTAssertEqual(libraryItem.kind, .web)
        XCTAssertNil(libraryItem.fileURL)
        XCTAssertFalse(libraryItem.isAvailable)
        XCTAssertEqual(libraryItem.state, .running)
        XCTAssertEqual(libraryItem.fileSize, 1_024)
    }

    func testMissingFinishedDownloadRemainsVisibleAsUnavailable() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let missing = folder.appendingPathComponent("missing.mp4")
        let item = DownloadItem()
        item.fileName = "Missing movie"
        item.state = .finished
        item.localURL = missing

        let snapshot = LibrarySnapshot.make(
            downloads: [item],
            favorites: [],
            history: [],
            readingList: [],
            localFiles: []
        )

        let libraryItem = try XCTUnwrap(snapshot.items.first)
        XCTAssertEqual(libraryItem.id, .download(item.id))
        XCTAssertFalse(libraryItem.isAvailable)
        XCTAssertEqual(libraryItem.kind, .video)
    }

    func testOrphanMediaFilesBecomeArtifacts() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try makeFile("frame-100.jpg", in: folder)

        let snapshot = LibrarySnapshot.make(
            downloads: [],
            favorites: [],
            history: [],
            readingList: [],
            localFiles: [LibraryFileRecord(url: file, modifiedAt: Date(timeIntervalSince1970: 200), size: 12)]
        )

        XCTAssertEqual(snapshot.counts.artifacts, 1)
        let item = try XCTUnwrap(snapshot.items.first)
        XCTAssertEqual(item.id, .artifact(file.standardizedFileURL.resolvingSymlinksInPath().path))
        XCTAssertEqual(item.title, "frame-100")
        XCTAssertEqual(item.kind, .image)
        XCTAssertNil(item.payload)
        XCTAssertTrue(item.isAvailable)
    }

    func testSnapshotDeduplicatesEntriesRejectsInvalidURLsAndMarksEmptyReadingUnavailable() throws {
        let id = UUID()
        let data = Data("""
        {"id":"\(id.uuidString)","title":"Saved article","url":"","paragraphs":["First"],"addedAt":0}
        """.utf8)
        let reading = try JSONDecoder().decode(ReadingListStore.Item.self, from: data)
        let favorite = Favorite(url: "https://example.com/watch", title: "Watch", folder: "Media")
        let history = HistoryEntry(url: "file:///private/document.pdf", title: "Invalid", date: Date())
        let empty = ReadingListStore.Item(id: UUID(), title: "Empty", url: "", paragraphs: [], addedAt: Date())

        let snapshot = LibrarySnapshot.make(
            downloads: [],
            favorites: [favorite, favorite],
            history: [history],
            readingList: [reading, reading, empty],
            localFiles: []
        )

        XCTAssertEqual(snapshot.counts.favorites, 1)
        XCTAssertEqual(snapshot.counts.history, 0)
        XCTAssertEqual(snapshot.counts.readingList, 2)
        XCTAssertEqual(snapshot.counts.total, 3)
        let saved = try XCTUnwrap(snapshot.items(query: "Saved").first)
        XCTAssertEqual(saved.id, .readingList(id))
        XCTAssertFalse(saved.isAvailable)
        XCTAssertEqual(saved.payload != nil, true)
        XCTAssertEqual(snapshot.items(query: "watch", sources: [.favorites]).count, 1)
        XCTAssertTrue(snapshot.items(query: "watch", sources: [.history]).isEmpty)
    }

    func testSortingUsesStableIdentityForTies() {
        let date = Date(timeIntervalSince1970: 300)
        let first = HistoryEntry(url: "https://a.example.com/video", title: "Same title", date: date)
        let second = HistoryEntry(url: "https://b.example.com/video", title: "Same title", date: date)
        let snapshot = LibrarySnapshot.make(
            downloads: [],
            favorites: [],
            history: [second, first],
            readingList: [],
            localFiles: []
        )

        XCTAssertEqual(snapshot.items(sort: .recent).map(\.id), [.history(first.url), .history(second.url)])
        XCTAssertEqual(snapshot.items(sort: .name).map(\.id), [.history(first.url), .history(second.url)])
    }

    func testFileScanIsReadOnlyAndIncludesOnlySupportedRegularFiles() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try makeFile("photo.heic", in: folder)
        _ = try makeFile("notes.json", in: folder)
        _ = try makeFile(".hidden.mp4", in: folder)
        let nested = folder.appendingPathComponent("nested.mp4", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let missing = folder.appendingPathComponent("missing", isDirectory: true)

        XCTAssertEqual(LibraryFileRecord.read(in: folder).map { $0.url.lastPathComponent }, ["photo.heic"])
        XCTAssertTrue(LibraryFileRecord.read(in: missing).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func makeFile(_ name: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data([1, 2, 3]).write(to: url)
        return url
    }
}
