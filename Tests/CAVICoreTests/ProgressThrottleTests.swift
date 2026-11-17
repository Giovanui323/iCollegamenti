import XCTest
@testable import CAVICore

final class ProgressThrottleTests: XCTestCase {
    func testDropsUpdatesInsideTheIntervalButKeepsPhaseChangesAndCompletion() {
        let throttle = ProgressThrottle(minimumInterval: 0.1)
        XCTAssertTrue(throttle.shouldForward(.init(phase: .writing, fractionCompleted: 0.01), now: 10))
        XCTAssertFalse(throttle.shouldForward(.init(phase: .writing, fractionCompleted: 0.02), now: 10.05))
        XCTAssertTrue(throttle.shouldForward(.init(phase: .writing, fractionCompleted: 0.03), now: 10.11))
        // A new phase is always forwarded, even right away.
        XCTAssertTrue(throttle.shouldForward(.init(phase: .reading, fractionCompleted: 0.5), now: 10.12))
        XCTAssertFalse(throttle.shouldForward(.init(phase: .reading, fractionCompleted: 0.6), now: 10.13))
        XCTAssertTrue(throttle.shouldForward(.init(phase: .reading, fractionCompleted: 1), now: 10.14))
        XCTAssertTrue(throttle.shouldForward(.init(phase: .finished, fractionCompleted: 1), now: 10.14))
    }

    func testSequentialBenchmarkSendsFarFewerUpdatesThanBlocks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cavi-throttle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let counter = UpdateCounter()
        // 64 blocks of 1 MiB written and read: unthrottled this was 130 main-actor hops.
        _ = try await BenchmarkWorker().run(mountPath: directory.path, testSizeBytes: 64 * 1_048_576) { _ in
            await counter.increment()
        }
        let count = await counter.value
        XCTAssertLessThan(count, 128)
        XCTAssertGreaterThanOrEqual(count, 3, "preparing, writing/reading and finished must still arrive")
    }
}

private actor UpdateCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
