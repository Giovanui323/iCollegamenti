import Foundation

/// A catalog match identifies only the USB bridge identity exposed by macOS.
/// It does not certify a cable, firmware, or the current connection bandwidth.
public struct BridgeInfo: Codable, Hashable, Sendable {
    public let family: String
    public let vendorID: Int
    public let productID: Int
    public let source: EvidenceSource

    public init(family: String, vendorID: Int, productID: Int, source: EvidenceSource = .catalogMatched) {
        self.family = family
        self.vendorID = vendorID
        self.productID = productID
        self.source = source
    }
}

public struct TechnicalProperty: Codable, Hashable, Sendable, Identifiable {
    public let key: String
    public let value: String

    public var id: String { key }

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct ConnectionSnapshot: Codable, Hashable, Sendable {
    public let protocolName: String?
    public let negotiatedLinkSpeedBps: UInt64?
    public let fileSystem: String?
    public let blockSizeBytes: UInt64?
    public let bridge: BridgeInfo?
    public let ioRegistryNodeNames: [String]?
    public let technicalProperties: [TechnicalProperty]

    public init(
        protocolName: String? = nil,
        negotiatedLinkSpeedBps: UInt64? = nil,
        fileSystem: String? = nil,
        blockSizeBytes: UInt64? = nil,
        bridge: BridgeInfo? = nil,
        ioRegistryNodeNames: [String]? = nil,
        technicalProperties: [TechnicalProperty] = []
    ) {
        self.protocolName = protocolName
        self.negotiatedLinkSpeedBps = negotiatedLinkSpeedBps
        self.fileSystem = fileSystem
        self.blockSizeBytes = blockSizeBytes
        self.bridge = bridge
        self.ioRegistryNodeNames = ioRegistryNodeNames
        self.technicalProperties = technicalProperties
    }
}

public enum BridgeCatalog {
    private struct Key: Hashable {
        let vendorID: Int
        let productID: Int
    }

    private static let entries: [Key: String] = [
        Key(vendorID: 0x152D, productID: 0x0583): "JMicron JMS583",
        Key(vendorID: 0x152D, productID: 0x0580): "JMicron JMS580",
        Key(vendorID: 0x174C, productID: 0x2362): "ASMedia ASM2362",
        Key(vendorID: 0x0BDA, productID: 0x9210): "Realtek RTL9210",
        Key(vendorID: 0x2109, productID: 0x0716): "VIA VL716"
    ]

    public static func match(vendorID: Int?, productID: Int?) -> BridgeInfo? {
        guard let vendorID, let productID,
              let family = entries[Key(vendorID: vendorID, productID: productID)] else {
            return nil
        }
        return BridgeInfo(family: family, vendorID: vendorID, productID: productID)
    }
}
