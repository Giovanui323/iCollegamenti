import Foundation

/// Detailed sequential-transfer expectations derived from the negotiated transport link
/// and typical real-world drive categories (NVMe SSD, SATA SSD, USB Flash Drive, HDD).
public struct BenchmarkLinkExpectation: Hashable, Sendable {
    public let minimumMBps: Double
    public let maximumMBps: Double
    public let theoreticalMaximumMBps: Double
    public let realisticMaximumMBps: Double
    public let protocolName: String

    public init(
        minimumMBps: Double,
        maximumMBps: Double,
        theoreticalMaximumMBps: Double,
        realisticMaximumMBps: Double,
        protocolName: String
    ) {
        self.minimumMBps = minimumMBps
        self.maximumMBps = maximumMBps
        self.theoreticalMaximumMBps = theoreticalMaximumMBps
        self.realisticMaximumMBps = realisticMaximumMBps
        self.protocolName = protocolName
    }

    public static func usefulSequentialRange(linkSpeedBps: UInt64?) -> Self? {
        guard let linkSpeedBps, linkSpeedBps > 0 else { return nil }

        let theoreticalMaximumMBps = Double(linkSpeedBps) / 8_000_000
        let (realisticMax, protoName): (Double, String) = {
            if linkSpeedBps >= 80_000_000_000 {
                return (6500.0, "Thunderbolt 5 (80–120 Gb/s)")
            } else if linkSpeedBps >= 40_000_000_000 {
                return (3200.0, "Thunderbolt 3/4 / USB4 (40 Gb/s)")
            } else if linkSpeedBps >= 20_000_000_000 {
                return (2050.0, "USB 3.2 Gen 2x2 (20 Gb/s)")
            } else if linkSpeedBps >= 10_000_000_000 {
                return (1050.0, "USB 3.2 Gen 2 (10 Gb/s)")
            } else if linkSpeedBps >= 5_000_000_000 {
                return (460.0, "USB 3.2 Gen 1 (5 Gb/s)")
            } else if linkSpeedBps >= 480_000_000 {
                return (43.0, "USB 2.0 (480 Mb/s)")
            } else {
                return (theoreticalMaximumMBps * 0.70, "\(Double(linkSpeedBps) / 1_000_000) Mb/s")
            }
        }()

        let minMBps = realisticMax * 0.65
        let maxMBps = realisticMax

        return Self(
            minimumMBps: minMBps,
            maximumMBps: maxMBps,
            theoreticalMaximumMBps: theoreticalMaximumMBps,
            realisticMaximumMBps: realisticMax,
            protocolName: protoName
        )
    }

    /// Real-world expected speed range string formatted for display (e.g. "300 – 460 MB/s")
    public var realisticRangeFormatted: String {
        "\(Int(minimumMBps.rounded()))–\(Int(maximumMBps.rounded())) MB/s"
    }

    /// Theoretical maximum formatted for display (e.g. "625 MB/s")
    public var theoreticalMaxFormatted: String {
        "\(Int(theoreticalMaximumMBps.rounded())) MB/s"
    }
}
