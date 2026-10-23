import XCTest
@testable import MyApp

final class CounterTests: XCTestCase {
    func testIncrement() {
        var counter = Counter()
        counter.increment()
        counter.increment()
        XCTAssertEqual(counter.value, 2)
    }

    func testDecrementStopsAtZero() {
        var counter = Counter()
        counter.decrement()
        XCTAssertEqual(counter.value, 0)
    }
}
