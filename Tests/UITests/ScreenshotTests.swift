import XCTest

final class ScreenshotTests: XCTestCase {
    private let app = XCUIApplication()
    private let shotDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("build/shots")

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launchEnvironment["MAGDY_UI_TEST"] = "1"
        app.launchEnvironment["MAGDY_LIBRARY_UI_SEED"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        snap("00-launch")
    }

    override func tearDown() {
        if (testRun?.failureCount ?? 0) > 0 {
            let testName = name.split(separator: " ").last.map(String.init) ?? "test"
            snap("failure-\(testName)")
        }
        super.tearDown()
    }

    private func snap(_ name: String) {
        do {
            try FileManager.default.createDirectory(at: shotDirectory, withIntermediateDirectories: true)
            try app.debugDescription.write(
                to: shotDirectory.appendingPathComponent("\(name)-ui.txt"),
                atomically: true,
                encoding: .utf8
            )
            try XCUIScreen.main.screenshot().pngRepresentation.write(
                to: shotDirectory.appendingPathComponent("\(name).png")
            )
        } catch {
            XCTFail("Unable to capture \(name): \(error)")
        }
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 10) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true && isHittable == true"),
            object: element
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        if result != .completed {
            snap("timeout-\(element.identifier)")
        }
        XCTAssertEqual(result, .completed)
    }

    private func dismissKeyboardIntroductionIfNeeded() {
        let continueButton = app.buttons["Continue"]
        guard continueButton.waitForExistence(timeout: 3) else { return }
        waitUntilHittable(continueButton)
        continueButton.tap()
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: continueButton
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
    }

    func testCaptureScreens() {
        waitUntilHittable(app.buttons["download-video"])
        waitUntilHittable(app.textFields["address-field"])
        XCTAssertTrue(app.staticTexts["start-title"].waitForExistence(timeout: 10))
        snap("01-start")

        waitUntilHittable(app.buttons["browser-tabs"])
        app.buttons["browser-tabs"].tap()
        waitUntilHittable(app.buttons["tab-grid-done"])
        XCTAssertTrue(app.navigationBars["Tabs"].exists)
        snap("02-tabs-grid")

        app.buttons["tab-grid-done"].tap()
        waitUntilHittable(app.buttons["browser-menu"])
        app.buttons["browser-menu"].tap()
        waitUntilHittable(app.buttons["menu-close"])
        XCTAssertTrue(app.tables.firstMatch.exists)
        snap("03-menu")

        app.buttons["menu-close"].tap()
        waitUntilHittable(app.textFields["address-field"])
        app.buttons["start-search"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        dismissKeyboardIntroductionIfNeeded()
        app.textFields["address-field"].typeText("magdy")

        let suggestions = app.tables["search-suggestions"]
        waitUntilHittable(suggestions, timeout: 20)
        XCTAssertGreaterThan(suggestions.cells.count, 0)
        snap("04-suggestions")
    }

    func testTabLifecycleAndPrivateSuggestions() {
        waitUntilHittable(app.buttons["download-video"])
        let tabButton = app.buttons["browser-tabs"]
        XCTAssertEqual(tabButton.value as? String, "1")

        app.buttons["browser-new-tab"].tap()
        let opened = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "2"), object: tabButton)
        XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 10), .completed)
        XCTAssertEqual(tabButton.value as? String, "2")

        tabButton.tap()
        waitUntilHittable(app.buttons["tab-grid-done"])
        let closeButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tab-close-"))
        XCTAssertEqual(closeButtons.count, 2)
        closeButtons.firstMatch.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 1"), object: closeButtons)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed)
        XCTAssertEqual(closeButtons.count, 1)

        app.buttons["tab-grid-done"].tap()
        waitUntilHittable(app.buttons["browser-menu"])
        app.buttons["browser-menu"].tap()
        waitUntilHittable(app.cells["menu-item-2"])
        app.cells["menu-item-2"].tap()
        waitUntilHittable(app.buttons["download-video"])
        XCTAssertEqual(tabButton.value as? String, "2")
        snap("05-private-tab")

        waitUntilHittable(app.textFields["address-field"])
        app.textFields["address-field"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        dismissKeyboardIntroductionIfNeeded()
        app.textFields["address-field"].typeText("magdy")
        XCTAssertFalse(app.tables["search-suggestions"].isHittable)
    }
}
