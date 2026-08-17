import Foundation

/// Pure calculations shared by the app UI and the safety runner.
public enum AnalysisMetrics {
    public static let compactBenchmarkBytes: UInt64 = 256 * 1_024 * 1_024
    public static let standardBenchmarkBytes: UInt64 = 1 * 1_024 * 1_024 * 1_024
    public static let extendedBenchmarkBytes: UInt64 = 4 * 1_024 * 1_024 * 1_024

    public static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let midpoint = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[midpoint - 1] + sorted[midpoint]) / 2
        }
        return sorted[midpoint]
    }

    public static func range(_ values: [Double]) -> Double? {
        guard let minimum = values.min(), let maximum = values.max() else { return nil }
        return maximum - minimum
    }

    public static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Nearest-rank percentile, suitable for small benchmark sample sets.
    public static func percentile(_ values: [Double], fraction: Double) -> Double? {
        guard !values.isEmpty, fraction >= 0, fraction <= 1 else { return nil }
        let sorted = values.sorted()
        let index = max(0, Int(ceil(fraction * Double(sorted.count))) - 1)
        return sorted[index]
    }

    public static func linkUtilizationPercent(measuredMBps: Double, linkSpeedBps: UInt64?) -> Int? {
        guard let linkSpeedBps, linkSpeedBps > 0, measuredMBps >= 0 else { return nil }
        let theoreticalMBps = Double(linkSpeedBps) / 8_000_000
        return Int((measuredMBps / theoreticalMBps * 100).rounded())
    }
}

public enum DisplayPortBandwidth: CaseIterable, Sendable {
    case dp14
    case dp21

    public var rawGbps: Double {
        switch self {
        case .dp14: 32.4
        case .dp21: 80
        }
    }
}

public struct ChargingSample: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let watts: Double

    public init(id: UUID = UUID(), timestamp: Date = Date(), watts: Double) {
        self.id = id
        self.timestamp = timestamp
        self.watts = watts
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case watts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        watts = try container.decode(Double.self, forKey: .watts)
    }
}

public enum ChargingHistory {
    public static func trim(_ samples: [ChargingSample], limit: Int) -> [ChargingSample] {
        guard limit > 0 else { return [] }
        return Array(samples.filter { $0.watts >= 0 && $0.watts.isFinite }.suffix(limit))
    }
}

public enum DeviceRefreshPolicy {
    public static func selectedBSDName(previous: String?, available: [String]) -> String? {
        if let previous, available.contains(previous) { return previous }
        return available.count == 1 ? available[0] : nil
    }
}

public struct StorageDeviceSelectionCandidate: Sendable, Hashable {
    public let id: String
    public let isStorageDevice: Bool
    public let isMounted: Bool

    public init(id: String, isStorageDevice: Bool, isMounted: Bool = false) {
        self.id = id
        self.isStorageDevice = isStorageDevice
        self.isMounted = isMounted
    }
}

public enum StorageDeviceSelectionPolicy {
    public static func storageDeviceIDs(from devices: [StorageDeviceSelectionCandidate]) -> [String] {
        devices.filter(\.isStorageDevice).map(\.id)
    }

    public static func effectiveDeviceID(selected: String?, available devices: [StorageDeviceSelectionCandidate]) -> String? {
        let storageCandidates = devices.filter(\.isStorageDevice)
        let storageIDs = storageCandidates.map(\.id)
        if let selected, storageIDs.contains(selected) { return selected }
        if let mountedFirst = storageCandidates.first(where: \.isMounted)?.id {
            return mountedFirst
        }
        return storageIDs.first
    }
}

public struct USBIdentity: Sendable, Hashable {
    public let locationID: Int?
    public let vendorID: Int?
    public let productID: Int?

    public init(locationID: Int?, vendorID: Int?, productID: Int?) {
        self.locationID = locationID
        self.vendorID = vendorID
        self.productID = productID
    }
}

public enum USBAssociationPolicy {
    public static func matches(locationID: Int?, vendorID: Int?, productID: Int?, topology: [USBIdentity]) -> Bool {
        topology.contains { candidate in
            guard let locationID, candidate.locationID == locationID else { return false }
            return (vendorID == nil || candidate.vendorID == vendorID) &&
                (productID == nil || candidate.productID == productID)
        }
    }
}
