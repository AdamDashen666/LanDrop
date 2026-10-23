import XCTest

final class SendUITests: UITestCase {
    /// 没配对时发文本要提示先配对（CI 上没有电脑可连）
    func testSendTextWithoutPairing() {
        snap("01-launch")
        let input = app.textViews["textInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("hello")
        app.buttons["sendText"].tap()
        let status = app.staticTexts["status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "请先配对电脑")
        snap("02-not-paired")
    }
}
