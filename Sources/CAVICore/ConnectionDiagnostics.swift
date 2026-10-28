import Foundation

public struct ConnectionMeasurement: Sendable, Hashable {
    public let label: String
    public let value: String

    public static func usbLink(bps: UInt64) -> Self { Self(label: "Velocità link", value: TransferSpeedFormatter.linkSpeed(bps)) }
    public static func videoRequirement(bps: UInt64) -> Self { Self(label: "Banda stimata", value: String(format: "%.1f Gb/s", Double(bps) / 1_000_000_000)) }
    public static func charging(watts: Double) -> Self { Self(label: "Potenza osservata", value: String(format: "%.1f W", watts)) }
}

public enum BenchmarkEligibility {
    public static func canRun(isStorageDevice: Bool, isMounted: Bool, mountPath: String) -> Bool {
        isStorageDevice && isMounted && !mountPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum CSVEncoder {
    /// Spreadsheets run a cell that starts with `=`, `+`, `-`, `@`, tab or CR as a formula. Device names come
    /// from USB descriptors, so such a cell is prefixed with an apostrophe to stay plain text.
    public static func field(_ value: String) -> String {
        let startsLikeFormula = value.first.map { "=+-@\t\r".contains($0) } ?? false
        let safe = startsLikeFormula ? "'" + value : value
        return "\"\(safe.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
