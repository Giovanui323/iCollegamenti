import XCTest
@testable import CAVICore

final class BenchmarkLinkExpectationTests: XCTestCase {
    func testFiveGigabitLinkHasAnHonestUsefulSequentialRange() throws {
        let expectation = try XCTUnwrap(
            BenchmarkLinkExpectation.usefulSequentialRange(linkSpeedBps: 5_000_000_000)
        )

        XCTAssertEqual(expectation.minimumMBps, 299, accuracy: 0.001)
        XCTAssertEqual(expectation.maximumMBps, 460, accuracy: 0.001)
        XCTAssertEqual(expectation.realisticMaximumMBps, 460, accuracy: 0.001)
        XCTAssertEqual(expectation.theoreticalMaximumMBps, 625, accuracy: 0.001)
    }

    func testMissingOrZeroLinkDoesNotInventAnExpectedRange() {
        XCTAssertNil(BenchmarkLinkExpectation.usefulSequentialRange(linkSpeedBps: nil))
        XCTAssertNil(BenchmarkLinkExpectation.usefulSequentialRange(linkSpeedBps: 0))
    }
}
