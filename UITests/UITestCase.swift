import XCTest

/// UI 测试基类：snap() 截图，CI 上会存到 ios-screenshots/ui/ 下（文件名按测试名和步骤名）。
class UITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launch()
    }

    /// 截一张当前屏幕的图。name 用英文/数字，如 "01-launch"。
    func snap(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        // CI 通过 TEST_RUNNER_SCREENSHOT_DIR 传入目录；模拟器可以直接写主机文件系统
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty else { return }
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        // self.name 形如 "-[CounterUITests testFoo]"
        let method = self.name.split(separator: " ").last.map { String($0.dropLast()) } ?? "test"
        let test = String(describing: type(of: self)) + "-" + method
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(device)-\(test)-\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: url)
    }
}
