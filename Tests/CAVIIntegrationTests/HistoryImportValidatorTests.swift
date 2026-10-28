import XCTest
@testable import CAVI

final class HistoryImportValidatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeResult(
        id: UUID = UUID(),
        label: String = "Cavo di prova",
        device: String = "SSD esterno",
        timestamp: Date? = nil,
        read: Double? = 400,
        write: Double? = 350
    ) -> CableTestResult {
        CableTestResult(
            id: id,
            cableLabel: label,
            timestamp: timestamp ?? now,
            deviceName: device,
            linkSpeedBps: 5_000_000_000,
            benchmarkReadMBps: read,
            benchmarkWriteMBps: write
        )
    }

    func testValidRecordIsAccepted() {
        XCTAssertTrue(HistoryImportValidator.isPlausible(makeResult(), now: now))
    }

    func testBlankLabelOrDeviceIsRejected() {
        XCTAssertFalse(HistoryImportValidator.isPlausible(makeResult(label: "   "), now: now))
        XCTAssertFalse(HistoryImportValidator.isPlausible(makeResult(device: ""), now: now))
    }

    func testImplausibleTimestampsAreRejected() {
        let tooOld = Date(timeIntervalSince1970: 0)
        let farFuture = now.addingTimeInterval(7 * 24 * 60 * 60)
        XCTAssertFalse(HistoryImportValidator.isPlausible(makeResult(timestamp: tooOld), now: now))
        XCTAssertFalse(HistoryImportValidator.isPlausible(makeResult(timestamp: farFuture), now: now))
    }

    func testNonFiniteOrNegativeBenchmarksAreRejected() {
        XCTAssertFalse(HistoryImportValidator.isPlausible(makeResult(read: .nan), now: now))
        XCTAssertFalse(HistoryImportValidator.isPlausible(makeResult(write: -1), now: now))
        XCTAssertFalse(HistoryImportValidator.isPlausible(makeResult(read: 1_000_000), now: now))
    }

    func testMissingBenchmarksAreStillValid() {
        XCTAssertTrue(HistoryImportValidator.isPlausible(makeResult(read: nil, write: nil), now: now))
    }

    func testPartitionKeepsValidRecordsAndCountsTheRest() {
        let valid = makeResult()
        let invalid = makeResult(label: "")
        let duplicateOfExisting = makeResult()
        let existingID = duplicateOfExisting.id

        let (accepted, summary) = HistoryImportValidator.partition(
            [valid, invalid, duplicateOfExisting],
            existingIDs: [existingID],
            now: now
        )

        XCTAssertEqual(accepted.map(\.id), [valid.id])
        XCTAssertEqual(summary, HistoryImportSummary(added: 1, rejectedInvalid: 1, skippedDuplicates: 1))
    }

    func testPartitionDoesNotAddTheSameIDTwiceFromOneFile() {
        let record = makeResult()
        let (accepted, summary) = HistoryImportValidator.partition([record, record], existingIDs: [], now: now)

        XCTAssertEqual(accepted.count, 1)
        XCTAssertEqual(summary.skippedDuplicates, 1)
    }
}
