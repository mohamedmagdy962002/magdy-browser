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

    func testBackupReadRejectsOversizedFileBeforeLoading() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(BackupRestore.maxBackupBytes + 1))
        try handle.close()

        XCTAssertThrowsError(try BackupRestore.readBackup(at: url))
    }

    func testHLSVariantLabelHandlesMalformedResolution() {
        XCTAssertEqual(HLSDownloader.variantLabel(height: 1080, bandwidth: 4_000_000), "1080p")
        XCTAssertEqual(HLSDownloader.variantLabel(height: .infinity, bandwidth: 4_000_000), "4.0 Mbps")
        XCTAssertEqual(HLSDownloader.variantLabel(height: 1e300, bandwidth: .nan), "0.0 Mbps")
    }

    func testAdAllowlistKeepsTrackerAndCustomRules() {
        XCTAssertTrue(BrowserTab.isAdBlockingRuleList("MagdyBlockList.ads"))
        XCTAssertTrue(BrowserTab.isAdBlockingRuleList("MagdyFilter.easylist"))
        XCTAssertFalse(BrowserTab.isAdBlockingRuleList("MagdyBlockList.trackers"))
        XCTAssertFalse(BrowserTab.isAdBlockingRuleList("MagdyFilter.easyprivacy"))
        XCTAssertFalse(BrowserTab.isAdBlockingRuleList("MagdyFilter.custom.example"))
    }

    func testSiteDataMatchingDoesNotClearParentDomains() {
        XCTAssertTrue(BrowserViewController.siteDataRecord("foo.example.com", matches: "foo.example.com"))
        XCTAssertTrue(BrowserViewController.siteDataRecord("sub.foo.example.com", matches: "foo.example.com"))
        XCTAssertFalse(BrowserViewController.siteDataRecord("example.com", matches: "foo.example.com"))
    }

    func testFavoritesValidationAcceptsHostsWithPorts() {
        XCTAssertEqual(FavoritesStore.validatedWebURL(from: "localhost:8080")?.host, "localhost")
        XCTAssertEqual(FavoritesStore.validatedWebURL(from: "example.com:8080/video")?.port, 8080)
        XCTAssertEqual(
            FavoritesStore.validatedWebURL(from: "example.com:8080/video?x=1#t")?.absoluteString,
            "https://example.com:8080/video?x=1#t"
        )
        XCTAssertNil(FavoritesStore.validatedWebURL(from: "example.com:notaport/video"))
        XCTAssertNil(FavoritesStore.validatedWebURL(from: "javascript:alert(1)"))
        XCTAssertNil(FavoritesStore.validatedWebURL(from: "file:///private/document.pdf"))
    }

    func testBackupRejectsUnsafeNumericPreferences() throws {
        let cases: [(String, Any)] = [
            (BrowserTab.textZoomKey, 1e300),
            ("magdy.zoomPerSite", ["example.com": 1e300]),
            (BlockStats.countKey, -1),
            ("magdy.futureNumber", 1e300)
        ]
        for (key, value) in cases {
            let encoded = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
            let backup = BackupRestore.Backup(version: 1, defaults: [key: encoded], history: nil)
            let data = try JSONEncoder().encode(backup)
            XCTAssertFalse(BackupRestore.restore(from: data), key)
        }
    }

    func testBackupExcludesDownloadFolderMetadata() throws {
        let nameKey = DownloadManager.folderBookmarkKey + ".name"
        let previous = UserDefaults.standard.object(forKey: nameKey)
        UserDefaults.standard.set("Private Folder", forKey: nameKey)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: nameKey) }
            else { UserDefaults.standard.removeObject(forKey: nameKey) }
        }

        let data = try XCTUnwrap(BackupRestore.exportData())
        let backup = try JSONDecoder().decode(BackupRestore.Backup.self, from: data)
        XCTAssertFalse(backup.defaults.keys.contains { $0.hasPrefix(DownloadManager.folderBookmarkKey) })
    }

    func testBlockStatsSaturatesRestoredCounter() {
        let previous = UserDefaults.standard.object(forKey: BlockStats.countKey)
        UserDefaults.standard.set(Int.max, forKey: BlockStats.countKey)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: BlockStats.countKey) }
            else { UserDefaults.standard.removeObject(forKey: BlockStats.countKey) }
        }
        BlockStats.shared.add(1)
        XCTAssertEqual(BlockStats.shared.total, Int.max)
    }

    func testID3UTF16CommentAndArtwork() throws {
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
        func utf16(_ value: String) -> Data {
            var data = Data([0xFE, 0xFF])
            for unit in value.utf16 {
                data.append(UInt8(unit >> 8))
                data.append(UInt8(unit & 0xFF))
            }
            return data
        }

        let image = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let description = utf16("cover")
        let comment = Data([1]) + Data("eng".utf8) + description + Data([0, 0]) + utf16("A comment")
        let picture = Data([1]) + Data("image/jpeg".utf8) + Data([0, 3]) + description + Data([0, 0]) + image
        let body = frame("COMM", comment) + frame("APIC", picture)
        var existing = Data("ID3".utf8)
        existing.append(contentsOf: [4, 0, 0])
        existing.append(syncSafe(body.count))
        existing.append(body)

        let parsed = try ID3.read(data: existing)
        XCTAssertEqual(parsed.comment, "A comment")
        XCTAssertEqual(parsed.artwork, image)
        XCTAssertEqual(parsed.artworkMimeType, "image/jpeg")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("sample.mp3")
        try (existing + Data([0xFF, 0xFB, 0x90, 0x64])).write(to: url)
        try ID3.write(parsed, to: url)
        let roundTrip = try ID3.read(from: url)
        XCTAssertEqual(roundTrip.comment, "A comment")
        XCTAssertEqual(roundTrip.artwork, image)
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
        existing.append(contentsOf: [4, 0, 0x50])
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
