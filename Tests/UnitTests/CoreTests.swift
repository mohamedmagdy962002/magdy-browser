import XCTest
@testable import MagdyBrowser

final class CoreTests: XCTestCase {

    func testWebURLValidation() {
        XCTAssertEqual(URL.webURL(from: "example.com/path?q=1")?.absoluteString, "https://example.com/path?q=1")
        XCTAssertEqual(URL.webURL(from: "example.com:8080/video")?.absoluteString, "https://example.com:8080/video")
        XCTAssertEqual(URL.webURL(from: "localhost:8080")?.absoluteString, "https://localhost:8080")
        XCTAssertEqual("localhost:8080".magdyNavigable?.absoluteString, "https://localhost:8080")
        XCTAssertTrue(URL(string: "http://localhost:8080")!.isWebURL)
        XCTAssertNil(URL.webURL(from: "javascript:alert(1)"))
        XCTAssertNil(URL.webURL(from: "file:///private/document.pdf"))
        XCTAssertNil(URL.webURL(from: "https://"))
    }

    func testFilterResourceTypesAndExceptions() {
        let rules = FilterListManager.rules(from: """
        ||ads.example.com^
        ||tracker.example.com^$stylesheet
        ||frames.example.com^$subdocument
        @@||ads.example.com^
        """)

        XCTAssertEqual(rules.count, 4)
        let blockRules = rules.filter { ($0["action"] as? [String: String])?["type"] == "block" }
        let exceptions = rules.filter { ($0["action"] as? [String: String])?["type"] == "ignore-previous-rules" }
        XCTAssertEqual(blockRules.count, 3)
        XCTAssertEqual(exceptions.count, 1)
        guard blockRules.count == 3, let lastRule = rules.last else { return }
        XCTAssertEqual((lastRule["action"] as? [String: String])?["type"], "ignore-previous-rules")

        let stylesheet = blockRules[1]["trigger"] as? [String: Any]
        let frames = blockRules[2]["trigger"] as? [String: Any]
        XCTAssertEqual(stylesheet?["resource-type"] as? [String], ["style-sheet"])
        XCTAssertEqual(frames?["resource-type"] as? [String], ["document"])
    }

    func testFilterSkipsCosmeticAndNegatedTypeRules() {
        let rules = FilterListManager.rules(from: """
        ||ads.example.com##.banner
        ||ads.example.com$~script,image
        example.com#@#.ad
        ! comment
        """)
        XCTAssertTrue(rules.isEmpty)
    }

    func testCookieScope() {
        let cookie = HTTPCookie(properties: [
            .name: "session",
            .value: "secret",
            .domain: "example.com",
            .path: "/account",
            .secure: true
        ])!

        XCTAssertTrue(cookie.applies(to: URL(string: "https://example.com/account/videos")!))
        XCTAssertTrue(cookie.applies(to: URL(string: "https://sub.example.com/account")!))
        XCTAssertFalse(cookie.applies(to: URL(string: "https://example.com/settings")!))
        XCTAssertFalse(cookie.applies(to: URL(string: "http://example.com/account")!))
        XCTAssertFalse(cookie.applies(to: URL(string: "https://other.example/account")!))
    }

    func testExpiredCookieDoesNotApply() {
        let cookie = HTTPCookie(properties: [
            .name: "session",
            .value: "expired",
            .domain: "example.com",
            .path: "/",
            .expires: Date(timeIntervalSinceNow: -60)
        ])!
        XCTAssertFalse(cookie.applies(to: URL(string: "https://example.com/")!))
    }

    func testHLSCancellationWinsOverHandlerCompletion() {
        let completion = expectation(description: "HLS cancellation completes once")
        completion.assertForOverFulfill = true
        let request = HLSRequest { result in
            guard case .failure(let error) = result,
                  let hlsError = error as? HLSDownloader.HLSError,
                  case .cancelled = hlsError else {
                XCTFail("Expected HLS cancellation to win")
                completion.fulfill()
                return
            }
            completion.fulfill()
        }
        _ = request.addCancellationHandler {
            request.finish(.success(URL(string: "https://example.com/video.mp4")!))
        }
        request.cancel()
        wait(for: [completion], timeout: 1)
        XCTAssertTrue(request.isCancelled)
    }

    func testDestinationReservationsAvoidCollisions() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let first = DownloadDestinationAllocator.availableName("video.mp4", in: folder, reserve: true)
        let second = DownloadDestinationAllocator.availableName("video.mp4", in: folder, reserve: true)
        XCTAssertEqual(first, "video.mp4")
        XCTAssertEqual(second, "video (1).mp4")
        DownloadDestinationAllocator.release(folder.appendingPathComponent(first))
        DownloadDestinationAllocator.release(folder.appendingPathComponent(second))

        let reused = DownloadDestinationAllocator.availableName("video.mp4", in: folder, reserve: true)
        XCTAssertEqual(reused, "video.mp4")
        DownloadDestinationAllocator.release(folder.appendingPathComponent(reused))

        try Data().write(to: folder.appendingPathComponent("taken.mp4"))
        XCTAssertEqual(
            DownloadDestinationAllocator.availableName("taken.mp4", in: folder, reserve: false),
            "taken (1).mp4"
        )
    }

    func testBackupRejectsNonWebHistory() throws {
        let entry = HistoryEntry(url: "file:///private/document.pdf", title: "Local file", date: Date())
        let backup = BackupRestore.Backup(
            version: 1,
            defaults: [:],
            history: try JSONEncoder().encode([entry])
        )
        let data = try JSONEncoder().encode(backup)
        XCTAssertFalse(BackupRestore.restore(from: data))
    }

    func testBackupExcludesPlaybackPositions() throws {
        let key = "magdy.playback./private/document.mp4"
        UserDefaults.standard.set(12.0, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let data = try XCTUnwrap(BackupRestore.exportData())
        let backup = try JSONDecoder().decode(BackupRestore.Backup.self, from: data)
        XCTAssertNil(backup.defaults[key])
    }

    func testBackupRejectsOversizedSession() throws {
        let tabs = (0...TabStore.maxSavedTabs).map {
            TabStore.SavedTab(url: "https://example.com/\($0)")
        }
        let session = try JSONEncoder().encode(tabs)
        let encoded = try PropertyListSerialization.data(
            fromPropertyList: session, format: .binary, options: 0
        )
        let backup = BackupRestore.Backup(
            version: 1,
            defaults: ["magdy.session": encoded],
            history: nil
        )
        let data = try JSONEncoder().encode(backup)
        XCTAssertFalse(BackupRestore.restore(from: data))
    }

    func testID3ExtendedHeaderPreservesFramesAndAudio() throws {
        func syncSafe(_ value: Int) -> Data {
            Data([
                UInt8((value >> 21) & 0x7F),
                UInt8((value >> 14) & 0x7F),
                UInt8((value >> 7) & 0x7F),
                UInt8(value & 0x7F)
            ])
        }
        func frame(_ identifier: String, _ payload: Data) -> Data {
            Data(identifier.utf8) + syncSafe(payload.count) + Data([0, 0]) + payload
        }

        let oldTitle = Data([3]) + Data("Old title".utf8)
        let custom = Data([3]) + Data("CUSTOM".utf8) + Data([0]) + Data("kept".utf8)
        let disc = Data([3]) + Data("1/2".utf8)
        var body = syncSafe(6) + Data(repeating: 0, count: 6)
        body.append(frame("TIT2", oldTitle))
        body.append(frame("TXXX", custom))
        body.append(frame("TPOS", disc))

        var existing = Data("ID3".utf8)
        existing.append(contentsOf: [4, 0, 0x10])
        existing.append(syncSafe(body.count))
        existing.append(body)
        existing.append(contentsOf: Array("3DI".utf8))
        existing.append(contentsOf: [4, 0, 0x10])
        existing.append(syncSafe(body.count))
        XCTAssertEqual(try ID3.read(data: existing).title, "Old title")

        let audio = Data([0xFF, 0xFB, 0x90, 0x64, 0x00, 0x01, 0x02])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("sample.mp3")
        try (existing + audio).write(to: url)

        var updated = ID3Tag()
        updated.title = "New title"
        updated.track = "2/3"
        try ID3.write(updated, to: url)

        let output = try Data(contentsOf: url)
        let tag = try ID3.read(data: output)
        XCTAssertEqual(tag.title, "New title")
        XCTAssertEqual(tag.track, "2/3")
        XCTAssertNotNil(output.range(of: Data("TXXX".utf8)))
        XCTAssertNotNil(output.range(of: Data("TPOS".utf8)))
        XCTAssertEqual(output.suffix(audio.count), audio)
    }
}
