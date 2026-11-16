import XCTest

/// Runtime smoke test: launches the app on a real iOS Simulator, taps through
/// the main screens and writes screenshots to SHOT_DIR for artifact upload.
final class ScreenshotTests: XCTestCase {

    private func snap(_ app: XCUIApplication, _ name: String) {
        let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    func testCaptureScreens() {
        let app = XCUIApplication()
        app.launch()
        sleep(3)
        snap(app, "01-start")

        // Dock row: 5 equal slots — tabs button is the 3rd.
        dock(app, 2)
        sleep(2)
        snap(app, "02-tabs-grid")

        // Close the grid (Done bar button) if it appeared.
        let done = app.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 3) {
            done.tap()
            sleep(1)
        }

        // ⋯ menu: 5th slot.
        dock(app, 4)
        sleep(1)
        snap(app, "03-menu")

        // Dismiss by tapping the dimmed backdrop near the top.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        sleep(1)

        // Omnibox: focus the address field by element query, not blind taps.
        let field = app.textFields.firstMatch
        if field.waitForExistence(timeout: 5) {
            field.tap()
            sleep(1)
            if app.keyboards.firstMatch.exists {
                app.typeText("magdy.com")
                sleep(1)
            }
        }
        snap(app, "04-suggestions")
    }

    private func dock(_ app: XCUIApplication, _ slot: Int) {
        let x = (Double(slot) + 0.5) / 5.0
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.925)).tap()
    }
}
