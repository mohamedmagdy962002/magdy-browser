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
        _ = request.addCancellationHandler { _ in
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
}
