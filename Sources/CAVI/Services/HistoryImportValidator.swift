import Foundation
import CryptoKit

/// Result of importing a history file: how many records were added and why others were skipped.
struct HistoryImportSummary: Equatable {
    let added: Int
    let rejectedInvalid: Int
    let skippedDuplicates: Int
}

/// Checks each imported record on its own, so one malformed entry does not hide the rest.
enum HistoryImportValidator {
    /// Records older than this are treated as corrupt; the app did not exist before it.
    static let earliestPlausibleDate = Date(timeIntervalSince1970: 946_684_800) // 1 Jan 2000
    /// Allows a small clock skew between the exporting and importing Mac.
    static let maximumFutureSkew: TimeInterval = 24 * 60 * 60
    /// Upper bound for a single benchmark value; anything above is a parsing error.
    static let maximumPlausibleMBps: Double = 100_000

    static func isPlausible(_ result: CableTestResult, now: Date = Date()) -> Bool {
        guard !result.cableLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !result.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        guard result.timestamp >= earliestPlausibleDate,
              result.timestamp <= now.addingTimeInterval(maximumFutureSkew)
        else { return false }
        return isPlausibleBenchmark(result.benchmarkReadMBps) && isPlausibleBenchmark(result.benchmarkWriteMBps)
    }

    /// Splits decoded records into those to add, invalid ones, and ones already in the history.
    static func partition(
        _ records: [CableTestResult],
        existingIDs: Set<UUID>,
        now: Date = Date()
    ) -> (accepted: [CableTestResult], summary: HistoryImportSummary) {
        var seenIDs = existingIDs
        var accepted: [CableTestResult] = []
        var invalid = 0
        var duplicates = 0

        for record in records {
            guard isPlausible(record, now: now) else {
                invalid += 1
                continue
            }
            guard seenIDs.insert(record.id).inserted else {
                duplicates += 1
                continue
            }
            accepted.append(record)
        }

        let summary = HistoryImportSummary(
            added: accepted.count,
            rejectedInvalid: invalid,
            skippedDuplicates: duplicates
        )
        return (accepted, summary)
    }

    /// Decodes each element on its own, so one malformed entry does not discard the whole file.
    /// Exports made for sharing omit `id` (see `SharedExportSanitizer`). For those, the id is derived
    /// from the record content, so importing the same file twice does not duplicate results.
    static func decodeRecords(from data: Data, decoder: JSONDecoder) throws -> (records: [CableTestResult], undecodable: Int) {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var records: [CableTestResult] = []
        var undecodable = 0
        for element in array {
            guard var object = element as? [String: Any] else {
                undecodable += 1
                continue
            }
            if object["id"] == nil {
                guard let canonical = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
                    undecodable += 1
                    continue
                }
                object["id"] = deterministicID(for: canonical).uuidString
            }
            guard let itemData = try? JSONSerialization.data(withJSONObject: object),
                  let record = try? decoder.decode(CableTestResult.self, from: itemData)
            else {
                undecodable += 1
                continue
            }
            records.append(record)
        }
        return (records, undecodable)
    }

    private static func deterministicID(for content: Data) -> UUID {
        let bytes = Array(SHA256.hash(data: content).prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func isPlausibleBenchmark(_ value: Double?) -> Bool {
        guard let value else { return true }
        return value.isFinite && value >= 0 && value <= maximumPlausibleMBps
    }
}
