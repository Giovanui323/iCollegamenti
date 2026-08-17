import Foundation

/// Formats a measured transfer speed for labels and summary metrics.
public enum TransferSpeedFormatter {
    public static func linkSpeed(_ bps: UInt64) -> String {
        if bps >= 1_000_000_000 {
            let gbps = Double(bps) / 1_000_000_000
            return gbps.rounded() == gbps ? String(format: "%.0f Gb/s", gbps) : String(format: "%.1f Gb/s", gbps)
        }
        return "\(bps / 1_000_000) Mb/s"
    }

    public static func megabytesPerSecond(_ value: Double) -> String {
        guard value.isFinite, value >= 0.1 else { return "0 MB/s" }
        if value < 10 { return String(format: "%.1f MB/s", value) }
        return String(format: "%.0f MB/s", value)
    }
}
