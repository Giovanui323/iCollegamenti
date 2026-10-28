import XCTest
@testable import CAVICore

/// Records progress updates from the worker's `@Sendable` callback.
private actor ProgressRecorder {
    private(set) var updates: [BenchmarkProgress] = []
    func record(_ update: BenchmarkProgress) { updates.append(update) }
}

final class BenchmarkWorkerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CAVIWorkerTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func leftoverBenchmarkFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".cavi-benchmark-") }
    }

    private func assertMonotonic(_ updates: [BenchmarkProgress], file: StaticString = #filePath, line: UInt = #line) {
        let fractions = updates.map(\.fractionCompleted)
        XCTAssertEqual(fractions.first, 0, file: file, line: line)
        XCTAssertEqual(fractions.last, 1, file: file, line: line)
        for (previous, next) in zip(fractions, fractions.dropFirst()) {
            XCTAssertLessThanOrEqual(previous, next, "Progress went backwards: \(previous) → \(next)", file: file, line: line)
        }
        XCTAssertTrue(fractions.allSatisfy { (0...1).contains($0) }, file: file, line: line)
    }

    func testSimpleRunMeasuresFiniteSpeedsAndCleansUp() async throws {
        let recorder = ProgressRecorder()
        let measurement = try await BenchmarkWorker().run(mountPath: directory.path, testSizeBytes: 2 * 1_048_576 + 123) { update in
            await recorder.record(update)
        }

        XCTAssertTrue(measurement.sequentialReadMBps.isFinite && measurement.sequentialReadMBps > 0)
        XCTAssertTrue(measurement.sequentialWriteMBps.isFinite && measurement.sequentialWriteMBps > 0)
        XCTAssertGreaterThan(measurement.durationSeconds, 0)
        XCTAssertEqual(try leftoverBenchmarkFiles(), [])
        let updates = await recorder.updates
        assertMonotonic(updates)
        XCTAssertEqual(updates.last?.phase, .finished)
    }

    func testSimpleRunRejectsZeroSizeAndInvalidPaths() async throws {
        do {
            _ = try await BenchmarkWorker().run(mountPath: directory.path, testSizeBytes: 0)
            XCTFail("A zero-byte benchmark has no meaningful speed")
        } catch let error as BenchmarkError {
            XCTAssertEqual(error, .invalidPath)
        }

        do {
            _ = try await BenchmarkWorker().run(mountPath: directory.appendingPathComponent("missing").path, testSizeBytes: 1_024)
            XCTFail("Missing directories must be rejected")
        } catch let error as BenchmarkError {
            XCTAssertEqual(error, .invalidPath)
        }

        let file = directory.appendingPathComponent("not-a-directory")
        try Data("x".utf8).write(to: file)
        do {
            _ = try await BenchmarkWorker().run(mountPath: file.path, testSizeBytes: 1_024)
            XCTFail("A file is not a volume")
        } catch let error as BenchmarkError {
            XCTAssertEqual(error, .invalidPath)
        }
    }

    func testSimpleRunRejectsSizesThatCannotFit() async {
        do {
            _ = try await BenchmarkWorker().run(mountPath: directory.path, testSizeBytes: UInt64.max)
            XCTFail("An overflowing size must not pass the free-space check")
        } catch let error as BenchmarkError {
            XCTAssertEqual(error, .insufficientSpace)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
        XCTAssertEqual(try leftoverBenchmarkFiles(), [])
    }

    func testEveryAdvancedWorkloadReportsMonotonicProgressAndCleansUp() async throws {
        let size: UInt64 = 2 * 1_048_576
        for workload in BenchmarkWorkload.allCases {
            let recorder = ProgressRecorder()
            let configuration = AdvancedBenchmarkConfiguration(preset: .quick256MiB, workload: workload, randomBlockSize: .sixtyFourKiB)
            let result = try await BenchmarkWorker().runAdvanced(
                mountPath: directory.path,
                configuration: configuration,
                testSizeBytes: size
            ) { update in
                await recorder.record(update)
            }
            let updates = await recorder.updates
            assertMonotonic(updates)
            XCTAssertFalse(result.samples.isEmpty, "\(workload)")
            XCTAssertEqual(try leftoverBenchmarkFiles(), [], "\(workload)")
        }
    }

    func testAdvancedWorkloadsReportTheirOwnMetrics() async throws {
        let worker = BenchmarkWorker()
        let size: UInt64 = 1_048_576

        let integrity = try await worker.runAdvanced(
            mountPath: directory.path,
            configuration: AdvancedBenchmarkConfiguration(preset: .quick256MiB, workload: .integrity),
            testSizeBytes: size + 17
        )
        XCTAssertEqual(integrity.integrityPassed, true)
        XCTAssertEqual(integrity.bytesVerified, size + 17)
        XCTAssertEqual(integrity.errorCount, 0)

        let latency = try await worker.runAdvanced(
            mountPath: directory.path,
            configuration: AdvancedBenchmarkConfiguration(preset: .quick256MiB, workload: .latency),
            testSizeBytes: size
        )
        let minimum = try XCTUnwrap(latency.latencyMinimumMilliseconds)
        let p95 = try XCTUnwrap(latency.latencyP95Milliseconds)
        let maximum = try XCTUnwrap(latency.latencyMaximumMilliseconds)
        XCTAssertLessThanOrEqual(minimum, p95)
        XCTAssertLessThanOrEqual(p95, maximum)

        let randomRead = try await worker.runAdvanced(
            mountPath: directory.path,
            configuration: AdvancedBenchmarkConfiguration(preset: .quick256MiB, workload: .random4KRead),
            testSizeBytes: size
        )
        XCTAssertGreaterThan(try XCTUnwrap(randomRead.randomReadIOPS), 0)
        XCTAssertNil(randomRead.randomWriteIOPS)

        let randomWrite = try await worker.runAdvanced(
            mountPath: directory.path,
            configuration: AdvancedBenchmarkConfiguration(preset: .quick256MiB, workload: .random4KWrite),
            testSizeBytes: size
        )
        XCTAssertGreaterThan(try XCTUnwrap(randomWrite.randomWriteIOPS), 0)
        XCTAssertNil(randomWrite.randomReadIOPS)
    }

    func testAdvancedRunRejectsZeroSize() async {
        do {
            _ = try await BenchmarkWorker().runAdvanced(
                mountPath: directory.path,
                configuration: AdvancedBenchmarkConfiguration(preset: .quick256MiB, workload: .sequential),
                testSizeBytes: 0
            )
            XCTFail("Zero-byte advanced benchmark must fail")
        } catch let error as BenchmarkError {
            XCTAssertEqual(error, .invalidPath)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testCancellationStopsTheRunAndRemovesTheTemporaryFile() async throws {
        let path = directory.path
        let task = Task {
            try await BenchmarkWorker().runAdvanced(
                mountPath: path,
                configuration: AdvancedBenchmarkConfiguration(preset: .quick256MiB, workload: .stress, stressDurationSeconds: 30),
                testSizeBytes: 1_048_576
            )
        }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled stress test must not complete")
        } catch is CancellationError {
        }
        XCTAssertEqual(try leftoverBenchmarkFiles(), [])
    }
}
