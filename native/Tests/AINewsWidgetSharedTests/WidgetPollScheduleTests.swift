import XCTest
@testable import AINewsWidgetShared

final class WidgetPollScheduleTests: XCTestCase {
    func testSuccessUsesBaseInterval() {
        XCTAssertEqual(WidgetPollSchedule.delay(base: 3, consecutiveFailures: 0), 3)
        XCTAssertEqual(WidgetPollSchedule.delay(base: 12, consecutiveFailures: 0), 12)
    }

    func testFailuresDoubleUpToOneMinute() {
        XCTAssertEqual((1...6).map { WidgetPollSchedule.delay(base: 3, consecutiveFailures: $0) }, [6, 12, 24, 48, 60, 60])
        XCTAssertEqual((1...3).map { WidgetPollSchedule.delay(base: 12, consecutiveFailures: $0) }, [24, 48, 60])
        XCTAssertEqual(WidgetPollSchedule.delay(base: 12, consecutiveFailures: 10_000), 60)
    }
}
