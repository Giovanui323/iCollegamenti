import XCTest
@testable import CAVICore

final class BenchmarkLinkExpectationTests: XCTestCase {
    func testFiveGigabitLinkHasAnHonestUsefulSequentialRange() throws {
        let expectation = try XCTUnwrap(
            BenchmarkLinkExpectation.usefulSequentialRange(linkSpeedBps: 5_000_000_000)
        )

        XCTAssertEqual(expectation.minimumMBps, 375)
        XCTAssertEqual(expectation.maximumMBps, 500)
        XCTAssertEqual(expectation.theoreticalMaximumMBps, 625)
    }

    func testMissingOrZeroLinkDoesNotInventAnExpectedRange() {
        XCTAssertNil(BenchmarkLinkExpectation.usefulSequentialRange(linkSpeedBps: nil))
        XCTAssertNil(BenchmarkLinkExpectation.usefulSequentialRange(linkSpeedBps: 0))
    }
}
