import XCTest
@testable import LanDrop

final class ProtoTests: XCTestCase {
    func testAddressFromInput() {
        XCTAssertEqual(Proto.address(fromInput: " 192.168.1.5 "), "192.168.1.5:47380")
        XCTAssertEqual(Proto.address(fromInput: "10.0.0.2:8000"), "10.0.0.2:8000")
    }

    func testEncodeIsAsciiAndRoundTrips() {
        let name = "照片 a&b+c=d%.jpg"
        let encoded = Proto.encode(name)
        XCTAssertTrue(encoded.allSatisfy(\.isASCII))
        XCTAssertEqual(encoded.removingPercentEncoding, name)
    }

    func testRequest() throws {
        let r = try Proto.request(address: "1.2.3.4:47380", path: "/send", method: "POST", token: "tok", headers: ["X-Kind": "text"])
        XCTAssertEqual(r.url?.absoluteString, "http://1.2.3.4:47380/send")
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Token"), "tok")
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Kind"), "text")
    }

    func testSafeName() {
        XCTAssertEqual(Proto.safeName("../../etc/passwd"), "passwd")
        XCTAssertEqual(Proto.safeName(".."), "file")
        XCTAssertEqual(Proto.safeName(""), "file")
        XCTAssertEqual(Proto.safeName("报告.pdf"), "报告.pdf")
    }

    func testFileName() {
        let tmp = URL(fileURLWithPath: "/tmp/abc.heic")
        XCTAssertEqual(Proto.fileName(suggested: "IMG_1", fallback: tmp), "IMG_1.heic")
        XCTAssertEqual(Proto.fileName(suggested: "a.jpg", fallback: tmp), "a.jpg")
        XCTAssertEqual(Proto.fileName(suggested: nil, fallback: tmp), "abc.heic")
    }

    func testContentTypeSkipsURLTypes() {
        XCTAssertEqual(Proto.contentType(in: ["public.file-url", "public.data"]), "public.data")
        XCTAssertEqual(Proto.contentType(in: ["public.url", "public.file-url", "public.jpeg"]), "public.jpeg")
        XCTAssertNil(Proto.contentType(in: ["public.file-url"]))
    }

    func testTempCopyKeepsContent() throws {
        let src = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("hi".utf8).write(to: src)
        defer { try? FileManager.default.removeItem(at: src) }
        let copy = try Proto.tempCopy(of: src, name: "a.txt")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        XCTAssertEqual(copy.lastPathComponent, "a.txt")
        XCTAssertEqual(try Data(contentsOf: copy), Data("hi".utf8))
    }

    func testUniqueURLDoesNotOverwrite() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(Proto.uniqueURL(in: dir, name: "a.txt").lastPathComponent, "a.txt")
        try Data().write(to: dir.appendingPathComponent("a.txt"))
        XCTAssertEqual(Proto.uniqueURL(in: dir, name: "a.txt").lastPathComponent, "a (1).txt")
        try Data().write(to: dir.appendingPathComponent("a (1).txt"))
        XCTAssertEqual(Proto.uniqueURL(in: dir, name: "a.txt").lastPathComponent, "a (2).txt")
        try Data().write(to: dir.appendingPathComponent("noext"))
        XCTAssertEqual(Proto.uniqueURL(in: dir, name: "noext").lastPathComponent, "noext (1)")
    }
}
