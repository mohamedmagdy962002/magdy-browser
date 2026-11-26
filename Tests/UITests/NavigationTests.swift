import XCTest
import UIKit

final class NavigationTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launchEnvironment["MAGDY_UI_TEST"] = "1"
        app.launchEnvironment["MAGDY_LIBRARY_UI_SEED"] = "1"
        app.launch()
    }

    override func tearDown() {
        if (testRun?.failureCount ?? 0) > 0 {
            let testName = name.split(separator: " ").last.map(String.init) ?? "test"
            captureEvidence("failure-\(testName)")
        }
        super.tearDown()
    }

    func testFourHubNavigationRetainsBrowserState() throws {
        waitForHittable(app.textFields["address-field"])
        guard app.tabBars.firstMatch.exists else {
            if UIDevice.current.userInterfaceIdiom == .pad {
                throw XCTSkip("Compact navigation is not visible in regular width.")
            }
            XCTFail("Compact navigation is missing on iPhone.")
            return
        }
        let tabButton = app.buttons["browser-tabs"]
        XCTAssertEqual(tabButton.value as? String, "1")
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        openSecondBrowserTab()
        XCTAssertEqual(tabButton.value as? String, "2")

        app.tabBars.buttons["Library"].tap()
        let library = app.collectionViews["library-collection"]
        waitForHittable(library)
        waitForHittable(app.searchFields["library-search"])
        XCTAssertTrue(app.buttons["library-filter-all"].isSelected)
        XCTAssertTrue(app.staticTexts["library-count"].exists)
        captureEvidence("phone-library")

        let search = app.searchFields["library-search"]
        search.tap()
        search.typeText("unlikely search result")
        waitForHittable(app.otherElements["library-no-results"])
        app.buttons["Show All"].tap()
        waitForHittable(library)
        XCTAssertFalse(app.otherElements["library-no-results"].exists)

        app.buttons["library-manage"].tap()
        let downloadsAction = app.buttons.matching(
            NSPredicate(format: "label == %@ AND isHittable == true", "Downloads")
        ).firstMatch
        waitForHittable(downloadsAction)
        downloadsAction.tap()
        waitForHittable(app.navigationBars["Downloads"].buttons["Library"])

        app.navigationBars["Downloads"].buttons["Library"].tap()
        waitForHittable(library)
        app.tabBars.buttons["Tools"].tap()
        waitForHittable(app.navigationBars["Tools"].buttons["Refresh"])

        app.tabBars.buttons["More"].tap()
        waitForHittable(app.tables["more-screen"].cells["more-settings"])
        app.tables["more-screen"].cells["more-settings"].tap()
        waitForHittable(app.navigationBars["Settings"].buttons["More"])

        app.navigationBars["Settings"].buttons["More"].tap()
        app.tabBars.buttons["Browser"].tap()
        waitForHittable(app.textFields["address-field"])
        XCTAssertEqual(tabButton.value as? String, "2")
    }

    func testRegularSidebarRetainsBrowserState() throws {
        waitForHittable(app.textFields["address-field"])
        guard !app.tabBars.firstMatch.exists else {
            if UIDevice.current.userInterfaceIdiom == .pad {
                XCTFail("Sidebar navigation is missing on iPad.")
                return
            }
            throw XCTSkip("Sidebar navigation is not visible in compact width.")
        }

        let browserTabs = app.buttons["browser-tabs"]
        XCTAssertEqual(browserTabs.value as? String, "1")
        openSecondBrowserTab()
        XCTAssertEqual(browserTabs.value as? String, "2")
        captureEvidence("ipad-browser-sidebar")
        let library = app.tables["app-sidebar"].cells["sidebar-library"]
        waitForHittable(library)
        library.tap()
        let libraryCollection = app.collectionViews["library-collection"]
        waitForHittable(libraryCollection)
        waitForHittable(app.searchFields["library-search"])
        captureEvidence("ipad-library-sidebar")
        XCTAssertTrue(app.buttons["library-filter-all"].isSelected)
        app.tables["app-sidebar"].cells["sidebar-browser"].tap()
        waitForHittable(app.textFields["address-field"])
        XCTAssertEqual(browserTabs.value as? String, "2")
    }

    func testMoreExplainsLocalDataAndNoAccountModel() throws {
        guard app.tabBars.firstMatch.waitForExistence(timeout: 5) else {
            throw XCTSkip("More is in the sidebar in regular width.")
        }
        app.tabBars.buttons["More"].tap()
        waitForHittable(app.tables["more-screen"].cells["more-about"])
        app.tables["more-screen"].cells["more-about"].tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "No account")).firstMatch.exists)
        alert.buttons["Done"].tap()
        XCTAssertFalse(alert.exists)
    }

    private func openSecondBrowserTab() {
        app.buttons["browser-new-tab"].tap()
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "2"),
            object: app.buttons["browser-tabs"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }

    private func captureEvidence(_ name: String) {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("build/shots")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try XCUIScreen.main.screenshot().pngRepresentation.write(
                to: directory.appendingPathComponent("\(name).png")
            )
            try app.debugDescription.write(
                to: directory.appendingPathComponent("\(name)-ui.txt"),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            XCTFail("Unable to capture \(name): \(error)")
        }
    }

    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval = 10) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true && isHittable == true"),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }
}
