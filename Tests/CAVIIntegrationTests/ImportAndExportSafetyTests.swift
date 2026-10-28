import XCTest
import CAVICore
@testable import CAVI

final class ImportAndExportSafetyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// A shared export drops `id` (see SharedExportSanitizer). Build the same shape from a real record.
    private func sharedExportWithoutIDs(_ results: [CableTestResult]) throws -> Data {
        let full = try JSONSerialization.jsonObject(with: encoder().encode(results)) as? [[String: Any]] ?? []
        let stripped = full.map { record -> [String: Any] in
            var copy = record
            copy.removeValue(forKey: "id")
            return copy
        }
        return try JSONSerialization.data(withJSONObject: stripped)
    }

    func testSharedExportWithoutIDsIsImportedAndKeepsItsRecords() throws {
        let results = [
            CableTestResult(cableLabel: "Cavo A", timestamp: now, deviceName: "SSD", linkSpeedBps: 5_000_000_000),
            CableTestResult(cableLabel: "Cavo B", timestamp: now, deviceName: "Hub", linkSpeedBps: 10_000_000_000)
        ]

        let decoded = try HistoryImportValidator.decodeRecords(from: sharedExportWithoutIDs(results), decoder: decoder())

        XCTAssertEqual(decoded.records.count, 2)
        XCTAssertEqual(decoded.undecodable, 0)
        XCTAssertEqual(Set(decoded.records.map(\.cableLabel)), ["Cavo A", "Cavo B"])
    }

    func testImportingTheSameSharedExportTwiceGivesTheSameIDs() throws {
        let data = try sharedExportWithoutIDs([
            CableTestResult(cableLabel: "Cavo A", timestamp: now, deviceName: "SSD", linkSpeedBps: 5_000_000_000)
        ])

        let first = try HistoryImportValidator.decodeRecords(from: data, decoder: decoder()).records
        let second = try HistoryImportValidator.decodeRecords(from: data, decoder: decoder()).records

        XCTAssertEqual(first.map(\.id), second.map(\.id), "Re-importing a file must not create new copies.")
    }

    func testOneMalformedElementDoesNotDiscardTheOthers() throws {
        let good = try JSONSerialization.jsonObject(with: encoder().encode([
            CableTestResult(cableLabel: "Cavo A", timestamp: now, deviceName: "SSD", linkSpeedBps: 5_000_000_000)
        ])) as? [[String: Any]] ?? []
        let mixed: [Any] = good + ["not a record", 42]
        let data = try JSONSerialization.data(withJSONObject: mixed)

        let decoded = try HistoryImportValidator.decodeRecords(from: data, decoder: decoder())

        XCTAssertEqual(decoded.records.count, 1)
        XCTAssertEqual(decoded.undecodable, 2)
    }

    func testNonArrayFileIsRejected() {
        let data = Data("{\"not\": \"an array\"}".utf8)
        XCTAssertThrowsError(try HistoryImportValidator.decodeRecords(from: data, decoder: decoder()))
    }

    func testCSVFieldNeutralizesFormulaPrefixes() {
        for value in ["=HYPERLINK(\"x\")", "+1+1", "-2", "@SUM(A1)", "\tcmd", "\rcmd"] {
            XCTAssertTrue(CSVEncoder.field(value).hasPrefix("\"'"), "\(value) must be stored as text")
        }
        XCTAssertEqual(CSVEncoder.field("Anker USB-C"), "\"Anker USB-C\"")
        XCTAssertEqual(CSVEncoder.field("a \"quoted\" name"), "\"a \"\"quoted\"\" name\"")
    }

    func testChargingHistoryDropsSamplesOutsideTheWindow() {
        let old = ChargingSample(timestamp: now.addingTimeInterval(-3_600), watts: 60)
        let recent = ChargingSample(timestamp: now.addingTimeInterval(-30), watts: 45)

        let kept = ChargingHistory.recent([old, recent], limit: 60, window: 600, now: now)

        XCTAssertEqual(kept.map(\.watts), [45])
    }

    func testChargingHistoryIsCappedAtTheLimit() {
        let samples = (0..<10).map { ChargingSample(timestamp: now.addingTimeInterval(TimeInterval($0)), watts: Double($0)) }

        let kept = ChargingHistory.recent(samples, limit: 3, window: 600, now: now.addingTimeInterval(20))

        XCTAssertEqual(kept.map(\.watts), [7, 8, 9])
    }
}
