import XCTest

final class CounterUITests: UITestCase {
    func testTapButtonsChangesCounter() {
        let value = app.staticTexts["counterValue"]
        XCTAssertTrue(value.waitForExistence(timeout: 10))
        XCTAssertEqual(value.label, "0")
        snap("01-launch")

        app.buttons["increment"].tap()
        app.buttons["increment"].tap()
        XCTAssertEqual(value.label, "2")
        snap("02-after-increment")

        app.buttons["decrement"].tap()
        XCTAssertEqual(value.label, "1")
        snap("03-after-decrement")
    }
}
