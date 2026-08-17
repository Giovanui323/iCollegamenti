import Foundation

public enum StorageConnectionKind: String, Codable, CaseIterable, Sendable {
    case usbOrThunderbolt
    case integratedSDReader

    public var connectionDescription: String {
        switch self {
        case .usbOrThunderbolt:
            return "Unità USB o Thunderbolt"
        case .integratedSDReader:
            return "Lettore SD integrato — nessun cavo da diagnosticare"
        }
    }

    public var supportsUSBTopology: Bool {
        self == .usbOrThunderbolt
    }
}

public enum StorageDiscoveryPolicy {
    public static func connectionKind(
        isInternal: Bool,
        isRemovable: Bool,
        protocolName: String?
    ) -> StorageConnectionKind? {
        let normalized = protocolName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if !isInternal && ["usb", "thunderbolt"].contains(normalized) {
            return .usbOrThunderbolt
        }

        let sdProtocols = ["sd", "sdhc", "sdxc", "secure digital"]
        if isRemovable && sdProtocols.contains(normalized) {
            return .integratedSDReader
        }

        return nil
    }
}
