import Foundation

/// Identifiers exposed for one USB peripheral. The matcher intentionally
/// refuses an ambiguous VID/PID-only match so row actions cannot target a
/// different identical device.
public struct USBDeviceIdentity: Hashable, Sendable {
    public let bsdName: String?
    public let vendorID: Int?
    public let productID: Int?
    public let serialNumber: String?
    public let locationID: Int?

    public init(
        bsdName: String?,
        vendorID: Int?,
        productID: Int?,
        serialNumber: String?,
        locationID: Int?
    ) {
        self.bsdName = bsdName
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.locationID = locationID
    }
}

public enum USBDeviceMatchPolicy {
    public static func bestCandidateIndex(
        for observed: USBDeviceIdentity,
        candidates: [USBDeviceIdentity]
    ) -> Int? {
        if let bsdName = nonEmpty(observed.bsdName) {
            let matches = candidates.indices.filter { nonEmpty(candidates[$0].bsdName) == bsdName }
            if matches.count == 1 { return matches[0] }
        }

        if let locationID = observed.locationID {
            let matches = candidates.indices.filter { index in
                let candidate = candidates[index]
                guard candidate.locationID == locationID else { return false }
                return matchesKnown(observed.vendorID, candidate.vendorID)
                    && matchesKnown(observed.productID, candidate.productID)
            }
            if matches.count == 1 { return matches[0] }
        }

        if let serialNumber = nonEmpty(observed.serialNumber) {
            let matches = candidates.indices.filter { nonEmpty(candidates[$0].serialNumber) == serialNumber }
            if matches.count == 1 { return matches[0] }
        }

        guard let vendorID = observed.vendorID, let productID = observed.productID else { return nil }
        let matches = candidates.indices.filter {
            candidates[$0].vendorID == vendorID && candidates[$0].productID == productID
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func matchesKnown<T: Equatable>(_ observed: T?, _ candidate: T?) -> Bool {
        guard let observed else { return true }
        return observed == candidate
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
