import XCTest
@testable import CueMe

final class AsyncDeadlineTests: XCTestCase {
    func testReturnsTrueWhenWorkFinishesInTime() async {
        let finished = await withDeadline(.seconds(2)) {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(finished)
    }

    func testReturnsFalseAndDoesNotHangOnStuckWork() async {
        let clock = ContinuousClock()
        let start = clock.now

        let finished = await withDeadline(.milliseconds(120)) {
            // Ignores cancellation on purpose: this is the framework hang the
            // deadline exists to survive.
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline { }
        }

        XCTAssertFalse(finished)
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(2))
    }
}
